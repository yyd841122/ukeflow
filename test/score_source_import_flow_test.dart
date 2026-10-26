import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/features/library/score_source_import_flow.dart';

import 'helpers/score_ir_fixtures.dart';

/// 工单 44 识谱源导入流程:选文件 → 解码验形 → 校验全检 → 重导入查重
/// → Ready 出预览命名页。控制器纯编排,picker 与查重注入,不碰平台
/// 通道与库(权限姿态与取消语义的验收见 backup/image flow 同型测试)。
void main() {
  final validSource = jsonEncode(validTinyIr().toJson());

  Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

  ScoreSourceImportFlow flow({
    Future<({Uint8List bytes, String? name})?> Function()? pick,
    Future<String?> Function(String sha)? findDuplicateTitle,
  }) =>
      ScoreSourceImportFlow(
        pick: pick,
        findDuplicateTitle: findDuplicateTitle ?? (_) async => null,
      );

  group('合法源 → Ready', () {
    test('物化三件套齐备,建议名 = 文件名去扩展名', () async {
      final outcome = await flow(
        pick: () async => (bytes: bytesOf(validSource), name: 'ai-ni-score.json'),
      ).pickAndValidate();

      final ready = outcome as ScoreSourceReady;
      expect(ready.sourceJson, validSource, reason: '落库存的就是原样文本');
      expect(ready.suggestedTitle, 'ai-ni-score');
      expect(ready.ir.id, 'test-tiny-solo');
      expect(ready.ir.review?.reviewedAt, '2026-10-26T10:00:00.000');
      expect(ready.materialization.accompaniment.notes, hasLength(2));
      expect(ready.materialization.melody.notes, hasLength(3));
    });

    test('无文件名/纯扩展名 → suggestedTitle null(命名回退源内曲名)', () async {
      for (final name in [null, '', '.json']) {
        final outcome = await flow(
          pick: () async => (bytes: bytesOf(validSource), name: name),
        ).pickAndValidate();
        expect(
          (outcome as ScoreSourceReady).suggestedTitle,
          isNull,
          reason: '文件名 $name 不产生建议名',
        );
      }
    });
  });

  test('同内容已入库 → Duplicate(带已有条目名),不进 Ready', () async {
    final outcome = await flow(
      pick: () async => (bytes: bytesOf(validSource), name: 'x.json'),
      findDuplicateTitle: (_) async => '旧谱',
    ).pickAndValidate();

    final dup = outcome as ScoreSourceDuplicate;
    expect(dup.existingTitle, '旧谱');
  });

  test('坏 JSON → Invalid 单条解码错误', () async {
    final outcome = await flow(
      pick: () async => (bytes: bytesOf('{bad'), name: 'x.json'),
    ).pickAndValidate();

    final invalid = outcome as ScoreSourceInvalid;
    expect(invalid.errors, hasLength(1));
    expect(invalid.errors.single, contains('源 JSON 解析失败'));
  });

  test('校验阻塞 → Invalid 逐条全量(不支持记号在内)', () async {
    final blocked = jsonEncode(tinyScoreIr().toJson());
    final outcome = await flow(
      pick: () async => (bytes: bytesOf(blocked), name: 'x.json'),
    ).pickAndValidate();

    final invalid = outcome as ScoreSourceInvalid;
    expect(invalid.errors.any((e) => e.contains('不支持记号')), isTrue);
    expect(invalid.errors.length, greaterThanOrEqualTo(1));
  });

  test('用户取消 → Cancelled,不查重', () async {
    var shaLookups = 0;
    final outcome = await flow(
      pick: () async => null,
      findDuplicateTitle: (_) async {
        shaLookups++;
        return null;
      },
    ).pickAndValidate();

    expect(outcome, isA<ScoreSourceCancelled>());
    expect(shaLookups, 0, reason: '取消即静默返回,库不碰');
  });

  test('选到重复源时,校验先行:坏 JSON 不查重直接 Invalid', () async {
    var shaLookups = 0;
    final outcome = await flow(
      pick: () async => (bytes: bytesOf('{bad'), name: 'x.json'),
      findDuplicateTitle: (_) async {
        shaLookups++;
        return '旧谱';
      },
    ).pickAndValidate();

    expect(outcome, isA<ScoreSourceInvalid>());
    expect(shaLookups, 0, reason: '坏源不值得查重');
  });

  test('picker 平台层失败 → Failed 可读文案', () async {
    final outcome = await flow(
      pick: () async => throw StateError('no picker'),
    ).pickAndValidate();

    expect(outcome, isA<ScoreSourceFailed>());
  });

  test('非 UTF-8 字节 → Failed 可读文案(不进校验层)', () async {
    final outcome = await flow(
      pick: () async => (bytes: Uint8List.fromList([0xff, 0xfe, 0x00]), name: 'x.json'),
    ).pickAndValidate();

    final failed = outcome as ScoreSourceFailed;
    expect(failed.message, contains('文本'));
  });
}
