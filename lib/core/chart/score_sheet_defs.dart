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

/// 滑音事件(照印张):从 [fromBeat] 的音滑到 [toBeat] 的音,渲染为两
/// 品位数字间的斜线(方向随音高);KS 合成器的滑音声效另立票,播放先
/// 离散两音。
class ScoreSlideEvent {
  const ScoreSlideEvent(this.fromBeat, this.toBeat);

  /// 起音拍位(主轴)。
  final double fromBeat;

  /// 目标音拍位(主轴)。
  final double toBeat;
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
    this.slides = const [],
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

  /// 滑音事件,按起音拍位升序(印张两数字间斜线)。
  final List<ScoreSlideEvent> slides;

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

  /// 展示名替换(导入独奏谱的命名合并策略,工单 43):展示名一律以
  /// 入库名为准——名字相同则原样返回(StrumChart.withTitle 同款纪律)。
  ScoreSheetDef withTitle(String title) => title == this.title
      ? this
      : ScoreSheetDef(
          id: id,
          title: title,
          artist: artist,
          tabChartId: tabChartId,
          melodyChartId: melodyChartId,
          melodyAlignBeats: melodyAlignBeats,
          keySignature: keySignature,
          chords: chords,
          strums: strums,
          rests: rests,
          tremolos: tremolos,
          slides: slides,
        );
}

// ── 印张手读指形(frets ④③②① 序,即印张数字串 G 弦起读法;工单 37
// 台账逐张读定,并与谱卡逐音互证:E 堆 ④4③4②4①2 =「4442」)────────
// 手指编号印张未标,一律 0(点位不标指号);横按只 4444 同形的
// C#m7/Bsus4(整排四品)。

// ── 内置组合目录 ──
// 曾收录《爱你不是两三天》(PDF 印张对照转录,票37/39);2026-11-14
// 曲谱识别线终止(ADR-0013),唯一歌曲来源改为在线一手数据抓取(票07),
// 内置条目随曲删除。目录清空,类保留(导入独奏谱面仍物化到此结构)。
const scoreSheetCatalog = <ScoreSheetDef>[];
