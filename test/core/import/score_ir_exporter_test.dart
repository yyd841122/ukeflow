import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/import/score_ir.dart';
import 'package:ukeflow/core/import/score_ir_exporter.dart';
import 'package:ukeflow/core/import/score_ir_validator.dart';
import 'package:ukeflow/core/model/tab_chart.dart';
import 'package:ukeflow/core/model/uke_string.dart';

/// 导出缝(工单 42):内置金标准三源(组合定义+双 TabChart)→ 识谱源。
/// 期望值手推自谱面台账(工单 37/39 与谱面注释),非代码复算——
/// 拍位/时值/声部休止的推导规则在这层钉死。
void main() {
  final charts = {for (final e in builtinTabChartCatalog) e.id: e.chart};
  final def = scoreSheetCatalog.single;
  final solo = charts[def.tabChartId]!;
  final melody = charts[def.melodyChartId]!;
  final ir = exportScoreIr(def: def, tabChart: solo, melodyChart: melody);

  group('金标准导出:爱你不是两三天三源 → IR', () {
    test('元信息与骨架:schema 1 / 4-4 拍 / 78bpm / 1=E / 27 小节 / 对齐 +20', () {
      expect(ir.schemaVersion, scoreIrSchemaVersion);
      expect(ir.id, 'ai-ni-bu-shi-liang-san-tian-solo');
      expect(ir.title, '爱你不是两三天');
      expect(ir.artist, '梁静茹');
      expect(ir.meter.beatsPerMeasure, 4);
      expect(ir.meter.beatUnit, 4);
      expect(ir.tempoMap, hasLength(1));
      expect(ir.tempoMap.first.beat, 0);
      expect(ir.tempoMap.first.bpm, 78);
      expect(ir.keyMap.single.key, '1=E');
      expect(ir.measures, hasLength(27));
      expect(ir.measures.first.number, 1);
      expect(ir.measures.first.startBeat, 0.0);
      expect(ir.measures.last.number, 27);
      expect(ir.measures.last.startBeat, 104.0);
      expect(ir.melodyAlignBeats, 20.0);
      expect(ir.tabChartId, def.tabChartId);
      expect(ir.melodyChartId, def.melodyChartId);
    });

    test('旋律声部 168 音,首音带缀字,拍位为层内本地拍位', () {
      expect(ir.melody.notes, hasLength(168));
      final first = ir.melody.notes.first;
      expect(first.beat, 0.0);
      expect(first.string, 2);
      expect(first.fret, 3);
      expect(first.lyric, '你');
      // 冗余 midi = 空弦 + 品(②3 = E4+3 = G4 = 67)。
      expect(first.midi, UkeString.e.midi + 3);
      final last = ir.melody.notes.last;
      expect(last.beat, 87.5);
      expect(last.lyric, '念');
    });

    test('伴奏声部 484 音,首音 = 拍4 ④4 堆成员,末音 = 拍107.75 ①3', () {
      expect(ir.accompaniment.notes, hasLength(484));
      final first = ir.accompaniment.notes.first;
      expect(first.beat, 4.0);
      expect(first.string, 4);
      expect(first.fret, 4);
      expect(first.midi, UkeString.g.midi + 4);
      expect(first.lyric, isNull);
      final last = ir.accompaniment.notes.last;
      expect(last.beat, 107.75);
      expect(last.string, 1);
      expect(last.fret, 3);
    });

    test('声部时值 = 距下音 gap,小节末音收到小节线(抽样手推值)', () {
      // 旋律 b6 首音:0 → 0.75(的)。
      expect(ir.melody.notes.first.durationBeats, 0.75);
      // 旋律 b9 拖腔:12.25 的延连音吃掉后续 3.25 拍气口(印张双休止
      // 不另立声部休止,gap 即时值——推导约定)。
      expect(
        ir.melody.notes
            .firstWhere((n) => n.beat == 12.25)
            .durationBeats,
        3.25,
      );
      // 旋律末音收到拍 88(小节线)。
      expect(ir.melody.notes.last.durationBeats, 0.5);
      // 伴奏 b2 堆:4 → 4.5;@82 长音柱收到拍 84(二拍占位)。
      expect(ir.accompaniment.notes.first.durationBeats, 0.5);
      expect(
        ir.accompaniment.notes.firstWhere((n) => n.beat == 82).durationBeats,
        2.0,
      );
    });

    test('声部休止 = 小节前静默簿记(手推全表:伴奏仅 b1 全休止,旋律无)', () {
      // gap 约定:音间静默由前一音时值表达,b2 八分休止@7 被 6.0 的
      // 时值(1.5)吸收——唯一声部休止是 b1 全小节休止(印张全休止符)。
      // 旋律每小节首拍都有音,无声部休止。
      expect(
        [for (final r in ir.accompaniment.rests) (r.beat, r.beats)],
        [(0.0, 4.0)],
      );
      expect(ir.melody.rests, isEmpty);
    });

    test('主轴事件表 1:1 照录组合定义(休止/滑音/震音/扫弦/和弦锚)', () {
      expect([for (final r in ir.rests) (r.beat, r.beats)], [(7.0, 0.5)]);
      expect(
        [for (final s in ir.slides) (s.fromBeat, s.toBeat)],
        [(9.5, 10.0)],
      );
      expect([for (final t in ir.tremolos) t.beat], [82.0]);
      expect(ir.strums, hasLength(def.strums.length));
      expect(ir.strums.first.beat, 4.0);
      expect(ir.strums.first.kind, ScoreStrumKind.roll);
      expect(ir.strums.map((s) => s.kind), def.strums.map((s) => s.kind));
      expect(ir.chordAnchors, hasLength(def.chords.length));
      expect(ir.chordAnchors.first.beat, 4.0);
      expect(ir.chordAnchors.first.label, 'E');
      expect(ir.chordAnchors.first.fingering.frets, [4, 4, 4, 2]);
      expect(ir.chordAnchors.last.label, 'G#7');
    });

    test('内置金标准往返:证据恒 null,无不支持记号,review 缺省', () {
      for (final v in [ir.melody, ir.accompaniment]) {
        for (final n in v.notes) {
          expect(n.evidence, isNull, reason: '内置往返不带证据:@${n.beat}');
        }
        for (final r in v.rests) {
          expect(r.evidence, isNull);
        }
      }
      expect(ir.unsupportedSymbols, isEmpty);
      expect(ir.review, isNull);
    });
  });

  group('边界:拍位恰落小节线的末音不静默丢(评审 2026-10-26)', () {
    const edgeDef = ScoreSheetDef(
      id: 'edge-at-barline',
      title: '压线边谱',
      tabChartId: 'edge-accomp',
      melodyChartId: 'edge-melody',
      melodyAlignBeats: 0,
      keySignature: '1=C',
      chords: [],
    );
    final edgeIr = exportScoreIr(
      def: edgeDef,
      tabChart: const TabChart(
        title: 'x',
        tempo: 90,
        notes: [TabNote(string: 1, fret: 0, beat: 8.0)],
      ),
      melodyChart: const TabChart(
        title: 'x',
        tempo: 90,
        notes: [TabNote(string: 2, fret: 0, beat: 0)],
      ),
    );

    test('拍 8 的末音归入第 3 小节(floor+1,非 ceil)', () {
      expect(edgeIr.accompaniment.notes, hasLength(1));
      expect(edgeIr.accompaniment.notes.single.beat, 8.0);
      // 该小节唯一的音收到小节线:时值整 4 拍。
      expect(edgeIr.accompaniment.notes.single.durationBeats, 4.0);
      expect(edgeIr.measures, hasLength(3));
      expect(edgeIr.measures.last.startBeat, 8.0);
      // 前两小节整小节休止簿记,产物闭合。
      expect(
        [for (final r in edgeIr.accompaniment.rests) (r.beat, r.beats)],
        [(0.0, 4.0), (4.0, 4.0)],
      );
    });

    test('导出产物过校验(导出/校验边界自洽)', () {
      expect(validateScoreIr(edgeIr), isEmpty);
    });
  });
}
