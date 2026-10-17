import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/backup/backup_doc.dart';
import 'package:ukeflow/core/model/checkin.dart';
import 'package:ukeflow/features/settings/backup_flow.dart';

/// 工单 21 平台缝(同工单 18 image_pick_flow 模式):pick/share 注入,
/// 测试不碰平台通道。取消静默、坏文件可读失败、好文件出待还原文档、
/// 导出走 share 缝带文件名与字节。
void main() {
  final validJson = jsonEncode(
    BackupDoc(
      settings: const {'reference_a4': '432'},
      checkIns: const [
        BackupCheckIn(day: 1, kind: CheckInKind.completed, checkedOnDay: 20650),
      ],
      customCharts: const [],
      imageCharts: const [],
    ).toJsonMap(),
  );

  test('用户取消选文件:静默返回', () async {
    final flow = BackupFlow(pick: () async => null);

    final outcome = await flow.pickAndParse();

    expect(outcome, isA<BackupImportCancelled>());
  });

  test('坏文件:可读失败(编解码层的中文错误直通)', () async {
    final flow = BackupFlow(
      pick: () async => Uint8List.fromList(utf8.encode('这不是 JSON{{{')),
    );

    final outcome = await flow.pickAndParse();

    expect(outcome, isA<BackupImportFailed>());
    expect((outcome as BackupImportFailed).message, contains('JSON'));
  });

  test('非 UTF-8 字节:可读失败不崩溃', () async {
    final flow = BackupFlow(pick: () async => Uint8List.fromList([0xff, 0xfe, 0x00]));

    final outcome = await flow.pickAndParse();

    expect(outcome, isA<BackupImportFailed>());
    expect((outcome as BackupImportFailed).message, isNotEmpty);
  });

  test('好文件:出待还原文档', () async {
    final flow = BackupFlow(
      pick: () async => Uint8List.fromList(utf8.encode(validJson)),
    );

    final outcome = await flow.pickAndParse();

    expect(outcome, isA<BackupReadyToRestore>());
    final ready = outcome as BackupReadyToRestore;
    expect(ready.doc.settings, {'reference_a4': '432'});
    expect(ready.doc.checkIns.single.day, 1);
  });

  test('导出:share 缝收到默认文件名(带日期)与 UTF-8 字节', () async {
    String? sharedName;
    Uint8List? sharedBytes;
    final flow = BackupFlow(
      share: (name, bytes) async {
        sharedName = name;
        sharedBytes = bytes;
        return BackupShareResult.shared;
      },
    );

    final outcome = await flow.export(validJson);

    expect(outcome, isA<BackupExported>());
    expect(sharedName, matches(RegExp(r'^ukeflow-backup-\d{4}-\d{2}-\d{2}\.json$')));
    expect(utf8.decode(sharedBytes!), validJson);
  });

  test('导出被用户取消(分享面板 dismissed):独立结果,不冒充成功', () async {
    final flow = BackupFlow(
      share: (name, bytes) async => BackupShareResult.dismissed,
    );

    final outcome = await flow.export(validJson);

    expect(outcome, isA<BackupExportDismissed>());
  });

  test('导出结果不可知(旧设备 unavailable):按已生成反馈', () async {
    final flow = BackupFlow(
      share: (name, bytes) async => BackupShareResult.unavailable,
    );

    final outcome = await flow.export(validJson);

    expect(outcome, isA<BackupExported>());
  });

  test('导出失败(平台层抛错):可读失败不崩溃', () async {
    final flow = BackupFlow(
      share: (name, bytes) async => throw Exception('分享面板没了'),
    );

    final outcome = await flow.export(validJson);

    expect(outcome, isA<BackupExportFailed>());
    expect((outcome as BackupExportFailed).message, isNotEmpty);
  });
}
