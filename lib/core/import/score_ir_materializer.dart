/// 识谱源物化器(工单 42,spec 测试缝⑤总闸):ScoreIr → 既有组合结构
/// (ScoreSheetDef + TAB 伴奏层 TabChart + 简谱旋律层 TabChart),喂
/// buildScorePlaybackChart 即可跟练。**纯函数**:源变则产物变,物化
/// 永不改源(App 内轻改 = 改源再物化,ADR-0009)。
///
/// 物化前先过 [validateScoreIr],任何阻塞错误抛
/// [ScoreIrMaterializationException](错误清单原样上抛,工单 43 的
/// Broken 兜底显示用)——坏源不物化,不带病进曲库。
///
/// 时值在物化侧被丢弃是**约定而非损耗**:运行时 TabNote 本就无时值
/// (时值/符杠/附点/tie 由拍位推导,ADR-0003),IR 的 durationBeats/
/// 声部休止只服务校验器的拍长闭合与证据链。tie 按既有约定落:延续音
/// 在源里就是独立拍位上的音、lyric 为 null,物化照录(旋律层延续音
/// 不带字,简谱推导据此出延音弧)。
library;

import '../chart/score_sheet_defs.dart';
import '../model/tab_chart.dart';
import 'score_ir.dart';
import 'score_ir_validator.dart';

/// 物化三件套:双声部谱 + 组合定义。
class ScoreIrMaterialization {
  const ScoreIrMaterialization({
    required this.accompaniment,
    required this.melody,
    required this.def,
  });

  /// TAB 伴奏层(主轴)。
  final TabChart accompaniment;

  /// 简谱旋律层(层内本地拍位;主轴定位在 [def].melodyAlignBeats)。
  final TabChart melody;

  /// 组合定义(谱面视图/双轨混播的绑定源)。
  final ScoreSheetDef def;
}

/// 物化被阻塞:源未过校验,[errors] 为逐条人话阻塞错误。
class ScoreIrMaterializationException implements Exception {
  ScoreIrMaterializationException(this.errors);

  final List<String> errors;

  @override
  String toString() => 'ScoreIrMaterializationException(${errors.length} 项):\n'
      '${errors.map((e) => '  - $e').join('\n')}';
}

/// 物化:校验 → 三源直落。[ir] 合法是前置条件,不合法当场抛。
ScoreIrMaterialization materializeScoreIr(ScoreIr ir) {
  final errors = validateScoreIr(ir);
  if (errors.isNotEmpty) {
    throw ScoreIrMaterializationException(errors);
  }
  final tempo = ir.tempoMap.first.bpm;
  final accompaniment = validateTabChart(
    TabChart(
      title: ir.title,
      artist: ir.artist,
      tempo: tempo,
      notes: [
        for (final n in ir.accompaniment.notes)
          TabNote(
            string: n.string,
            fret: n.fret,
            beat: n.beat,
            lyric: n.lyric,
          ),
      ],
    ),
    context: '${ir.id}(伴奏层)',
  );
  final melody = validateTabChart(
    TabChart(
      title: ir.title,
      artist: ir.artist,
      tempo: tempo,
      notes: [
        for (final n in ir.melody.notes)
          TabNote(
            string: n.string,
            fret: n.fret,
            beat: n.beat,
            lyric: n.lyric,
          ),
      ],
    ),
    context: '${ir.id}(旋律层)',
  );
  final def = ScoreSheetDef(
    id: ir.id,
    title: ir.title,
    artist: ir.artist,
    tabChartId: ir.tabChartId,
    melodyChartId: ir.melodyChartId,
    melodyAlignBeats: ir.melodyAlignBeats,
    keySignature: ir.keyMap.first.key,
    chords: [
      for (final c in ir.chordAnchors)
        ScoreChordAnchor(
          beat: c.beat,
          label: c.label,
          fingering: c.fingering,
        ),
    ],
    strums: [
      for (final s in ir.strums) ScoreStrumEvent(s.beat, s.kind),
    ],
    rests: [
      for (final r in ir.rests) ScoreRestEvent(r.beat, r.beats),
    ],
    tremolos: [
      for (final t in ir.tremolos) ScoreTremoloEvent(t.beat),
    ],
    slides: [
      for (final s in ir.slides) ScoreSlideEvent(s.fromBeat, s.toBeat),
    ],
  );
  return ScoreIrMaterialization(
    accompaniment: accompaniment,
    melody: melody,
    def: def,
  );
}
