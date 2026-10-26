import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/import/imported_solo_charts.dart';
import 'package:ukeflow/core/import/score_ir.dart';
import 'package:ukeflow/core/import/score_ir_materializer.dart';

import '../../helpers/score_ir_fixtures.dart';

/// 导入独奏谱读出管线(工单 43):源 JSON → 解析+校验+物化。
/// 与自建谱 parseCustomChart 同型的最后一道闸——不信任存储:
/// JSON 坏损/schemaVersion 不符/校验阻塞三类坏源当场抛,
/// 工单 43 的 Ready/Broken 兜底吃这里的异常面。
void main() {
  final validSource = jsonEncode(validTinyIr().toJson());

  group('合法源:物化三件套照落', () {
    final m = materializeImportedSoloChart(
      sourceJson: validSource,
      title: '入库名',
    );

    test('def 三源绑定与事件表照源', () {
      final expected = materializeScoreIr(validTinyIr());
      expect(m.def.id, expected.def.id, reason: 'def.id 照录源(组合绑定证据)');
      expect(m.def.tabChartId, expected.def.tabChartId);
      expect(m.def.melodyChartId, expected.def.melodyChartId);
      expect(m.def.melodyAlignBeats, expected.def.melodyAlignBeats);
      expect(m.def.keySignature, expected.def.keySignature);
      expect(m.def.chords, hasLength(expected.def.chords.length));
      expect(m.def.strums, hasLength(expected.def.strums.length));
      expect(m.def.slides, hasLength(expected.def.slides.length));
      expect(m.accompaniment.notes, hasLength(2));
      expect(m.melody.notes, hasLength(3));
    });

    test('展示名以入库名为准:def 与两层谱题同源覆盖', () {
      expect(m.def.title, '入库名', reason: '源内曲名(测试小谱)不入展示');
      expect(m.accompaniment.title, '入库名');
      expect(m.melody.title, '入库名');
    });
  });

  group('坏源当场抛(存储不信任闸)', () {
    test('非 JSON 文本 → ScoreIrFormatException(带解码期定位)', () {
      expect(
        () => materializeImportedSoloChart(sourceJson: '{bad', title: 'x'),
        throwsA(
          isA<ScoreIrFormatException>().having(
            (e) => e.message,
            'message',
            contains('源 JSON 解析失败'),
          ),
        ),
      );
    });

    test('根非对象(数组/标量)→ ScoreIrFormatException', () {
      expect(
        () => materializeImportedSoloChart(sourceJson: '[1,2]', title: 'x'),
        throwsA(isA<ScoreIrFormatException>()),
      );
      expect(
        () => materializeImportedSoloChart(sourceJson: '"串"', title: 'x'),
        throwsA(isA<ScoreIrFormatException>()),
      );
    });

    test('schemaVersion 不符 → ScoreIrFormatException', () {
      final stale = jsonEncode({
        ...validTinyIr().toJson(),
        'schemaVersion': scoreIrSchemaVersion + 1,
      });
      expect(
        () => materializeImportedSoloChart(sourceJson: stale, title: 'x'),
        throwsA(
          isA<ScoreIrFormatException>().having(
            (e) => e.message,
            'message',
            contains('schemaVersion 不符'),
          ),
        ),
      );
    });

    test('校验阻塞(不支持记号未消解)→ ScoreIrMaterializationException', () {
      // tinyScoreIr 带 hammer-on:导出必经管线后仍被校验器拦下。
      final blocked = jsonEncode(tinyScoreIr().toJson());
      expect(
        () => materializeImportedSoloChart(sourceJson: blocked, title: 'x'),
        throwsA(
          isA<ScoreIrMaterializationException>().having(
            (e) => e.errors,
            'errors',
            isNotEmpty,
          ),
        ),
      );
    });
  });
}
