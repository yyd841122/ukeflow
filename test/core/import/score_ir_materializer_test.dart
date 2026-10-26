import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/import/score_ir.dart';
import 'package:ukeflow/core/import/score_ir_exporter.dart';
import 'package:ukeflow/core/import/score_ir_materializer.dart';
import 'package:ukeflow/core/model/tab_chart.dart';
import 'package:ukeflow/core/practice/dual_track_timeline.dart';

import '../../helpers/score_ir_fixtures.dart';

/// 物化缝(工单 42 测试缝⑤,**总闸**):内置金标准常量 → 导出识谱源 →
/// JSON 往返 → 物化 → 与原 Dart 常量逐位相等(音/拍位/歌词/休止/滑音/
/// 扫弦/和弦锚)。等值不过,43 以后全部不接(ADR-0009)。
void main() {
  final charts = {for (final e in builtinTabChartCatalog) e.id: e.chart};
  final def = scoreSheetCatalog.single;
  final solo = charts[def.tabChartId]!;
  final melody = charts[def.melodyChartId]!;

  final ir = exportScoreIr(def: def, tabChart: solo, melodyChart: melody);
  // 工作台↔App 交换走 JSON **字符串域**:物化吃的是经 jsonEncode →
  // jsonDecode(文件读写同路)往返后的源,不是内存对象直传。
  final restored = ScoreIr.fromJson(
    jsonDecode(jsonEncode(ir.toJson())) as Map<String, dynamic>,
  );
  final out = materializeScoreIr(restored);

  group('金标准往返等值(总闸)', () {
    test('伴奏层 484 音逐位相等(弦/品/拍位/歌词)+ tempo', () {
      expect(out.accompaniment.tempo, solo.tempo);
      expectTabNotesBitwiseEqual(out.accompaniment.notes, solo.notes, '伴奏层');
    });

    test('旋律层 168 音逐位相等(弦/品/拍位/歌词)+ tempo', () {
      expect(out.melody.tempo, melody.tempo);
      expectTabNotesBitwiseEqual(out.melody.notes, melody.notes, '旋律层');
    });

    test('组合定义逐字段相等(三源绑定/偏移/调号/五类事件表)', () {
      expectScoreSheetDefEqual(out.def, def);
    });

    test('复用 buildScorePlaybackChart:往返前后的播放谱逐位相等', () {
      final before = buildScorePlaybackChart(def, solo, melodyChart: melody);
      final after =
          buildScorePlaybackChart(out.def, out.accompaniment, melodyChart: out.melody);
      expectTabNotesBitwiseEqual(after.notes, before.notes, '播放谱');
      expect(after.tempo, before.tempo);
    });

    test('物化出谱过 validateTabChart(旋律 +4 半音后 ①16 仍合法)', () {
      expect(
        () => validateTabChart(out.accompaniment, context: '金标准往返'),
        returnsNormally,
      );
      expect(
        () => validateTabChart(out.melody, context: '金标准往返'),
        returnsNormally,
      );
    });
  });

  group('坏源不物化', () {
    test('改一个品:冗余 midi 与闭合双双告破,阻塞清单逐条列出', () {
      final notes = [
        for (final n in restored.accompaniment.notes)
          n.beat == 4.0 && n.string == 4
              ? ScoreIrNote(
                  beat: n.beat,
                  durationBeats: n.durationBeats,
                  string: n.string,
                  fret: n.fret + 1,
                  midi: n.midi,
                )
              : n,
      ];
      final tampered = ScoreIr(
        schemaVersion: restored.schemaVersion,
        id: restored.id,
        title: restored.title,
        meter: restored.meter,
        tempoMap: restored.tempoMap,
        keyMap: restored.keyMap,
        measures: restored.measures,
        melodyAlignBeats: restored.melodyAlignBeats,
        tabChartId: restored.tabChartId,
        melodyChartId: restored.melodyChartId,
        melody: restored.melody,
        accompaniment: ScoreIrVoice(
          notes: notes,
          rests: restored.accompaniment.rests,
        ),
      );
      expect(
        () => materializeScoreIr(tampered),
        throwsA(isA<ScoreIrMaterializationException>().having(
          (e) => e.errors.join('\n'),
          'errors',
          allOf(contains('midi'), contains('伴奏')),
        )),
      );
    });

    test('不支持记号在场 = 拒绝物化(禁止静默丢)', () {
      final withUnsupported = tinyScoreIr();
      expect(
        () => materializeScoreIr(withUnsupported),
        throwsA(isA<ScoreIrMaterializationException>().having(
          (e) => e.errors,
          'errors',
          anyElement(contains('不支持')),
        )),
      );
    });
  });
}
