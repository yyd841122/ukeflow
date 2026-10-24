/// 谱面视图的组合定义(ADR-0008,GLOSSARY「谱面视图」):一份 Dart 常量
/// 引用既有三源——TAB 伴奏层(指弹谱模型,主轴)与简谱旋律层(同为指弹谱
/// 模型,恒定拍格偏移)按曲库 id 绑定,和弦行(拍位+和弦名+指形)照权威
/// 印张新落于此。**三源绑定与偏移只在此处记录**,不造统一谱格式、不动
/// ADR-0003 两模型分界;新增曲目在此逐首登记。
library;

import '../model/chord.dart';
import '../model/tab_chart.dart';

/// 和弦行的一个拍锚:第 [beat] 拍起换 [label] 和弦,指形照印张自绘
/// (不走 chords-db 查表——G#7/F#m/C#m7/D7 为印张手读形)。
class ScoreChordAnchor {
  const ScoreChordAnchor({
    required this.beat,
    required this.label,
    required this.fingering,
  });

  /// 锚拍位(主轴拍格,四分拍,自曲头)。
  final double beat;

  /// 和弦名(照印张原样,含 Bsus4 这类前奏专用记号)。
  final String label;

  /// 指形(frets ④③②① 序,× = -1;ChordDiagram 直绘)。
  final ChordFingering fingering;
}

/// 一首组合谱面:曲名元信息 + 三源 id + 恒定拍格偏移 + 和弦行。
class ScoreSheetDef {
  const ScoreSheetDef({
    required this.id,
    required this.title,
    this.artist,
    required this.tabChartId,
    required this.melodyChartId,
    required this.melodyAlignBeats,
    required this.keySignature,
    required this.chords,
  });

  /// 组合定义 id:随主轴谱卡(独奏谱类型,工单 38)。
  final String id;

  /// 曲名(歌本体;不带「·独奏」后缀——独奏谱列表的类型位已表达)。
  final String title;

  /// 演唱者,无则 null。
  final String? artist;

  /// TAB 伴奏层(主轴)的内置指弹谱 id。
  final String tabChartId;

  /// 简谱旋律层的内置指弹谱 id。
  final String melodyChartId;

  /// 旋律层 → 主轴的恒定拍格偏移:旋律音拍位 + 此值 = 主轴拍位。
  /// 本曲旋律层从原曲 b6(主轴拍 20)起录,偏移恒 20。
  final double melodyAlignBeats;

  /// 谱角调号(照印张,如「1=E」)。
  final String keySignature;

  /// 和弦行拍锚,严格按拍位升序。
  final List<ScoreChordAnchor> chords;

  /// 副标题行:「artist · 78 BPM · 1=E」——曲库独奏卡与谱面页元信息共用
  /// (谱面页再前置类型名,单一拼装源在此)。
  String subtitleLine(TabChart tabChart) {
    final artist = this.artist;
    return [
      if (artist != null && artist.isNotEmpty) artist,
      '${tabChart.tempo} BPM',
      keySignature,
    ].join(' · ');
  }
}

// ── 印张手读指形(frets ④③②① 序,即印张数字串 G 弦起读法;工单 37
// 台账逐张读定,并与谱卡逐音互证:E 堆 ④4③4②4①2 =「4442」)────────
// 手指编号印张未标,一律 0(点位不标指号);横按只 4444 同形的
// C#m7/Bsus4(整排四品)。

const _e = ChordFingering(
  frets: [4, 4, 4, 2],
  fingers: [0, 0, 0, 0],
  baseFret: 1,
  barres: [],
);
const _a = ChordFingering(
  frets: [2, 1, 0, 0],
  fingers: [0, 0, 0, 0],
  baseFret: 1,
  barres: [],
);
const _b = ChordFingering(
  frets: [4, 3, 2, 2],
  fingers: [0, 0, 0, 0],
  baseFret: 1,
  barres: [],
);
const _cSharpM7 = ChordFingering(
  frets: [4, 4, 4, 4],
  fingers: [0, 0, 0, 0],
  baseFret: 1,
  barres: [4],
);
const _gSharp7 = ChordFingering(
  frets: [1, 3, 2, 3],
  fingers: [0, 0, 0, 0],
  baseFret: 1,
  barres: [],
);
const _fSharpM = ChordFingering(
  frets: [2, 1, 2, 0],
  fingers: [0, 0, 0, 0],
  baseFret: 1,
  barres: [],
);
const _d7 = ChordFingering(
  frets: [-1, 2, -1, 3],
  fingers: [0, 0, 0, 0],
  baseFret: 1,
  barres: [],
);
const _bsus4 = _cSharpM7; // 同形异名:前奏记 Bsus4,主歌起记 C#m7。

ScoreChordAnchor _anchor(double beat, String label, ChordFingering shape) =>
    ScoreChordAnchor(beat: beat, label: label, fingering: shape);

/// 组合谱面清单(逐首登记;首曲=爱你不是两三天,数据三源全复用)。
final scoreSheetCatalog = <ScoreSheetDef>[
  ScoreSheetDef(
    id: 'ai-ni-bu-shi-liang-san-tian-solo',
    title: '爱你不是两三天',
    artist: '梁静茹',
    tabChartId: 'ai-ni-bu-shi-liang-san-tian-solo',
    melodyChartId: 'ai-ni-bu-shi-liang-san-tian',
    melodyAlignBeats: 20,
    keySignature: '1=E',
    chords: [
      // ── 前奏 b2-5(拍 4-20):E-A-B-Bsus4-A-B-E,工单 37 前奏台账 ──
      _anchor(4, 'E', _e),
      _anchor(6, 'A', _a),
      _anchor(8, 'B', _b),
      _anchor(10, 'Bsus4', _bsus4),
      _anchor(12, 'A', _a),
      _anchor(14, 'B', _b),
      _anchor(16, 'E', _e),
      // ── 主歌两遍 b6-13(拍 20-52):|E A|B C#m7|A B|E| ×2,延展小节 ──
      // E 整小节不重锚。
      _anchor(20, 'E', _e),
      _anchor(22, 'A', _a),
      _anchor(24, 'B', _b),
      _anchor(26, 'C#m7', _cSharpM7),
      _anchor(28, 'A', _a),
      _anchor(30, 'B', _b),
      _anchor(32, 'E', _e),
      _anchor(36, 'E', _e),
      _anchor(38, 'A', _a),
      _anchor(40, 'B', _b),
      _anchor(42, 'C#m7', _cSharpM7),
      _anchor(44, 'A', _a),
      _anchor(46, 'B', _b),
      _anchor(48, 'E', _e),
      // ── 移位句 b14-17(拍 52-68):|E|A B|C#m7 A|B E| ──
      _anchor(52, 'E', _e),
      _anchor(56, 'A', _a),
      _anchor(58, 'B', _b),
      _anchor(60, 'C#m7', _cSharpM7),
      _anchor(62, 'A', _a),
      _anchor(64, 'B', _b),
      _anchor(66, 'E', _e),
      // ── 副歌A b18-21(拍 68-84):|A E|G#7 C#m7|A B|B 卷弦收 ──
      _anchor(68, 'A', _a),
      _anchor(70, 'E', _e),
      _anchor(72, 'G#7', _gSharp7),
      _anchor(74, 'C#m7', _cSharpM7),
      _anchor(76, 'A', _a),
      _anchor(78, 'B', _b),
      _anchor(80, 'B', _b),
      // ── 副歌B 高置段 b22-24(拍 84-96):|E|G#7 C#m7|A E(2+2 变拍)| ──
      _anchor(84, 'E', _e),
      _anchor(88, 'G#7', _gSharp7),
      _anchor(90, 'C#m7', _cSharpM7),
      _anchor(92, 'A', _a),
      _anchor(94, 'E', _e),
      // ── 尾 b25-27(拍 96-108):|F#m D7|E|G#7| ──
      _anchor(96, 'F#m', _fSharpM),
      _anchor(98, 'D7', _d7),
      _anchor(100, 'E', _e),
      _anchor(104, 'G#7', _gSharp7),
    ],
  ),
];
