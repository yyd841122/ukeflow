import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/backup/backup_doc.dart';
import 'package:ukeflow/core/model/checkin.dart';

/// 工单 21 编解码缝(纯数据变换,零 drift 依赖):合法备份文档
/// toJsonMap → JSON 串 → parseBackupJson 全字段还原;坏文件全族
/// (版本/形状/重复主键/坏 base64)给可读中文错,不崩溃。
void main() {
  // 造一份全量非空的备份文档:四表各至少一条,图片谱带真实字节。
  BackupDoc fullDoc() => BackupDoc(
    settings: const {'reference_a4': '432', 'default_bpm': '96'},
    checkIns: const [
      BackupCheckIn(day: 1, kind: CheckInKind.completed, checkedOnDay: 20650),
      BackupCheckIn(day: 3, kind: CheckInKind.madeUp, checkedOnDay: 20655),
    ],
    customCharts: const [
      BackupCustomChart(id: 3, title: 'Beat It', source: '{title: Beat It}'),
      BackupCustomChart(id: 7, title: '小草', source: '[C]没有花香'),
    ],
    imageCharts: [
      BackupImageChart(
        id: 2,
        title: '手写谱',
        image: Uint8List.fromList(const [1, 2, 3, 255, 0]),
      ),
    ],
  );

  test('格式版本号:导出文档带 version=1', () {
    final map = fullDoc().toJsonMap();
    expect(map['version'], 1);
  });

  test('合法文档往返:四表全字段还原', () {
    final doc = fullDoc();
    final json = jsonEncode(doc.toJsonMap());

    final restored = parseBackupJson(json);

    expect(restored.settings, doc.settings);
    expect(restored.checkIns, doc.checkIns);
    expect(restored.customCharts, doc.customCharts);
    expect(restored.imageCharts.map((e) => e.id), doc.imageCharts.map((e) => e.id));
    expect(restored.imageCharts.single.title, '手写谱');
    expect(restored.imageCharts.single.image, doc.imageCharts.single.image);
  });

  // 注:「全空文档可还原」曾是本文件的旧契约,评审(2026-10-17)推翻——
  // 导入即覆盖语义下放全空文档过去等于一键清库,现由坏文件族的
  // 「全空文档拒绝」锁定。

  group('坏文件给可读错误(不崩溃)', () {
    String reEncode(Map<String, Object?> Function(Map<String, Object?>) mutate) {
      return jsonEncode(mutate(fullDoc().toJsonMap()));
    }

    BackupFormatException parseError(String json) {
      expect(
        () => parseBackupJson(json),
        throwsA(isA<BackupFormatException>()),
      );
      try {
        parseBackupJson(json);
      } on BackupFormatException catch (e) {
        expect(e.message, isNotEmpty);
        return e;
      }
      throw StateError('unreachable');
    }

    test('非 JSON 文本', () {
      final error = parseError('这不是 JSON{{{');
      expect(error.message, contains('JSON'));
    });

    test('JSON 数组冒充(非对象)', () {
      parseError(jsonEncode([1, 2, 3]));
    });

    test('缺版本号', () {
      final error = parseError(reEncode((root) => root..remove('version')));
      expect(error.message, contains('版本'));
    });

    test('版本号更新(App 旧):提示升级不硬解', () {
      final error = parseError(reEncode((root) => root..['version'] = 99));
      expect(error.message, contains('升级'));
    });

    test('版本号非正数(0/负):格式不对', () {
      final error = parseError(reEncode((root) => root..['version'] = 0));
      expect(error.message, contains('版本'));
    });

    test('全空文档(只有版本号):拒绝——导入它=清库,没有合法用例', () {
      final error = parseError(jsonEncode({'version': 1}));
      expect(error.message, contains('没有数据'));
    });

    test('设置段值非字符串', () {
      parseError(reEncode((root) => root..['settings'] = {'a4': 432}));
    });

    test('打卡条目缺字段', () {
      parseError(
        reEncode(
          (root) => root..['checkins'] = [
            {'day': 1},
          ],
        ),
      );
    });

    test('打卡条目种类越界', () {
      parseError(
        reEncode(
          (root) => root..['checkins'] = [
            {'day': 1, 'kind': 7, 'checked_on_day': 20650},
          ],
        ),
      );
    });

    test('打卡天数重复(还原会撞主键,编解码层拦下)', () {
      final error = parseError(
        reEncode(
          (root) => root..['checkins'] = [
            {'day': 1, 'kind': 0, 'checked_on_day': 20650},
            {'day': 1, 'kind': 1, 'checked_on_day': 20651},
          ],
        ),
      );
      expect(error.message, contains('重复'));
    });

    test('自建谱编号重复', () {
      final error = parseError(
        reEncode(
          (root) => root..['custom_charts'] = [
            {'id': 3, 'title': 'a', 'source': 'a'},
            {'id': 3, 'title': 'b', 'source': 'b'},
          ],
        ),
      );
      expect(error.message, contains('重复'));
    });

    test('图片谱编号重复', () {
      final error = parseError(
        reEncode(
          (root) => root..['image_charts'] = [
            {'id': 2, 'title': 'a', 'image': 'AAAA'},
            {'id': 2, 'title': 'b', 'image': 'BBBB'},
          ],
        ),
      );
      expect(error.message, contains('重复'));
    });

    test('图片谱 base64 坏', () {
      parseError(
        reEncode(
          (root) => root..['image_charts'] = [
            {'id': 2, 'title': 'a', 'image': '不是base64!!!'},
          ],
        ),
      );
    });

    test('合法文档不被误拒(负面对抗:守卫只拦真坏的)', () {
      // 全空段+单条最小形态都放行——丢弃/误拒合法内容是静默数据损失。
      final json = jsonEncode(
        BackupDoc(
          settings: const {'k': 'v'},
          checkIns: const [
            BackupCheckIn(day: 30, kind: CheckInKind.madeUp, checkedOnDay: 0),
          ],
          customCharts: const [],
          imageCharts: const [],
        ).toJsonMap(),
      );
      expect(parseBackupJson(json).settings['k'], 'v');
    });
  });
}
