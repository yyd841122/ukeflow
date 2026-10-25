/// 谱面视图的组合定义(ADR-0008,GLOSSARY「谱面视图」):一份 Dart 常量
/// 引用既有三源——TAB 伴奏层(指弹谱模型,主轴)与简谱旋律层(同为指弹谱
/// 模型,恒定拍格偏移)按曲库 id 绑定,和弦行(拍位+和弦名+指形)照权威
/// 印张新落于此。**三源绑定与偏移只在此处记录**,不造统一谱格式、不动
/// ADR-0003 两模型分界;新增曲目在此逐首登记。
library;

import '../model/chord.dart';
import '../model/tab_chart.dart';

/// 扫弦事件(GLOSSARY「双轨混播」的声部记号,照印张):印张 TAB 行的
/// 箭头/波浪在转录时被解析成同拍逐弦 ×,本表把「这是扫弦不是拨弦」记回
/// 数据——渲染画箭头/波浪,播放按 [kind] 错峰发声。
enum ScoreStrumKind {
  /// 卷弦(印张波浪线)= 慢扫:逐弦慢错峰,④→①。
  roll,

  /// 下扫(直杆+下箭头)= 快扫,④→①。
  strumDown,

  /// 上扫(直杆+上箭头)= 快扫,①→④。
  strumUp,
}

/// 一个扫弦事件:第 [beat] 拍的同拍和弦音组按 [kind] 扫响。
class ScoreStrumEvent {
  const ScoreStrumEvent(this.beat, this.kind);

  /// 主轴拍位(与和弦行同网格)。
  final double beat;

  final ScoreStrumKind kind;
}

/// 震音记号(照印张):印张把密集拨弦 × 柱整柱套进瘦椭圆(实测高 59px
/// 罩满四弦),本表记回位置——渲染画椭圆框,柱内 × 照常画。
class ScoreTremoloEvent {
  const ScoreTremoloEvent(this.beat);

  /// 主轴拍位(柱所在拍)。
  final double beat;
}

/// 休止事件(照印张):印张 TAB 行的休止被转录拍平,本表记回——渲染画
/// 休止记号(八分 = 实心圆点+左下拖尾钩;二拍占位 = 「钩+带底杠数字+
/// 钩」三件套,工单 39 实测),发声本就是静默(数据无 attack,不动)。
class ScoreRestEvent {
  const ScoreRestEvent(this.beat, this.beats);

  /// 主轴拍位。
  final double beat;

  /// 休止拍数(0.5 = 八分;2 = 二分占位,渲染标数字)。
  final double beats;
}

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
    this.strums = const [],
    this.rests = const [],
    this.tremolos = const [],
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

  /// 扫弦/卷弦事件,严格按拍位升序(印张箭头/波浪;无则全拨弦)。
  final List<ScoreStrumEvent> strums;

  /// 休止事件,严格按拍位升序(印张休止记号;发声不受影响)。
  final List<ScoreRestEvent> rests;

  /// 震音记号,严格按拍位升序(印张椭圆框 × 柱)。
  final List<ScoreTremoloEvent> tremolos;

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

// ── 爱你不是两三天:扫弦/卷弦事件表(照印张,工单 37 台账+谱卡互证)──
// 判据:同拍 4 音且全落当前指形 = 扫弦/卷弦(3 音 = 主歌拨堆,D7 闷音柱
// 2 音,均不在表);方向:前奏照台账逐个读定,高置段/尾按「整拍下、
// 后半拍上」惯例预置,目验对印张纠正(工单 39)。
ScoreStrumEvent _r(double beat) => ScoreStrumEvent(beat, ScoreStrumKind.roll);
ScoreStrumEvent _sd(double beat) =>
    ScoreStrumEvent(beat, ScoreStrumKind.strumDown);
ScoreStrumEvent _su(double beat) =>
    ScoreStrumEvent(beat, ScoreStrumKind.strumUp);

final _aiNiStrums = <ScoreStrumEvent>[
  // ── 前奏(台账逐个读定)──
  _r(4), // b2 卷弦 E
  _r(6), // b2 卷弦 A
  _r(8), // b3 卷弦 B
  // b3 拍 9.5-10.5 照印张为二拍休止占位(钩+带底杠数字 2+钩),无扫弦。
  _r(14), // b4 B 全弦卷弦(印张波浪,2026-10-25 实测;旧讹下扫)
  _r(16), // b5 卷弦 E
  // ── 副歌A 收(卷弦)+ 高置段/尾扫弦(方向按惯例预置,目验纠正)──
  _r(80), // b21 卷弦收
  _sd(81), _su(81.5), _su(81.75),
  // 拍 82 照印张为椭圆框震音 × 柱(见 tremolos),非下扫。
  _sd(84), _sd(85), _su(85.5), _su(85.75),
  _sd(86.25), _su(86.5), _su(86.75), _sd(87), _su(87.5), _su(87.75),
  _sd(88), _sd(89), _su(89.5), _su(89.75),
  _sd(90.25), _sd(91), _su(91.5), _su(91.75),
  _sd(92), _sd(93), _su(93.5), _su(93.75),
  _sd(94), _sd(95), _su(95.5), _su(95.75),
  _sd(96), _sd(97), _su(97.5), _su(97.75),
  _sd(100), _sd(101), _su(101.5), _su(101.75),
  _sd(102.25), _su(102.5), _su(102.75), _sd(103), _su(103.5), _su(103.75),
  _sd(104), _sd(105), _su(105.5), _su(105.75),
  _sd(106.25), _su(106.5), _su(106.75), _sd(107), _su(107.5), _su(107.75),
];

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
    strums: _aiNiStrums,
    rests: const [
      ScoreRestEvent(7, 0.5), // b2:卷弦A(四分)后八分休止(实心点+拖尾钩),再上扫 A
      ScoreRestEvent(9.5, 2), // b3:二拍休止占位(钩+带底杠数字 2+钩,2026-10-25 实测)
    ],
    tremolos: const [
      ScoreTremoloEvent(82), // b22:椭圆框震音 × 柱(印张实测 19×59 瘦椭圆罩四弦)
    ],
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
