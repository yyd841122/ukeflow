/// 谱面布局内核(工单 39 测试缝①,GLOSSARY「谱面视图」):组合定义 →
/// 连续横带坐标(和弦图+和弦名 / TAB 伴奏 / 简谱旋律 / 歌词 四层纵带,
/// 横向 = 拍位×像素) + 简谱符号推导 + 跟随高亮当位查询。纯函数、零引擎
/// 依赖,CustomPainter 只做笔画——绘制与数据一致的保证点全在这里。
///
/// 横带展示(用户真机反馈 2026-10-24:流水式,弹过的向左滑出、后面的
/// 从右补上,播放头恒在视口左 1/3;和弦图照印张压在其拍位正上方,与行
/// 首留出距离)。早先的「屏宽折行系统」几何已按此方向移除。
library;

import 'dart:math' as math;

import '../audio/beat_scheduling.dart' show beatsPerBar;
import '../chart/score_sheet_defs.dart';
import '../model/tab_chart.dart';
import '../model/uke_string.dart';

/// 一个简谱符号的全部排版素材(自旋律层音符推导,GLOSSARY「谱面视图」)。
/// 显示与 C 指位数据无关:度数与八度点自实际音高推导(转录保度数,谱角
/// 1=E 照读;印张八度点比实际多一枚——「印张点数=实际+1」,工单 37 台账)。
class NumNote {
  const NumNote({
    required this.mainBeat,
    required this.degree,
    required this.highDots,
    required this.lowDots,
    required this.underlines,
    required this.dotted,
    required this.dashes,
    required this.arcOut,
    required this.restAfter,
    required this.lyric,
  });

  /// 主轴拍位(旋律拍 + 组合定义偏移)。
  final double mainBeat;

  /// 度数 1..7。
  final int degree;

  /// 高音点/低音点枚数(实际音高所在八度,C4..B4 无点)。
  final int highDots;
  final int lowDots;

  /// 时值线:0 素四分、1 八分单线、2 十六分双线。
  final int underlines;

  /// 附点(1.5/2.5/3.5 拍及 0.75 拍)。
  final bool dotted;

  /// 整拍延长横杠枚数(≥2 拍时 = 整数拍 − 1)。
  final int dashes;

  /// 到后继延续音(无缀字音符)的延音线/连音弧。
  final bool arcOut;

  /// 本音是延续音且距下音 ≥1 拍:本音记 1 拍封顶,余量出休止 0(时长),
  /// null = 无休止。数据只含 attack(「0」不落音,工单 37),拖腔后的
  /// 印张休止由该余量恢复。
  final double? restAfter;

  /// 逐音歌词缀字,null = 延续音(器乐/拖腔)。
  final String? lyric;
}

/// 跟随高亮的当位(GLOSSARY「跟随高亮」):四层同刻点亮的三索引,各层
/// -1 = 该层尚无当前元素(前奏/曲首)。歌词字随简谱当前音(逐音缀字)。
class ScoreCursor {
  const ScoreCursor({
    required this.chordIndex,
    required this.tabIndex,
    required this.melodyIndex,
  });

  final int chordIndex;
  final int tabIndex;
  final int melodyIndex;

  @override
  bool operator ==(Object other) =>
      other is ScoreCursor &&
      other.chordIndex == chordIndex &&
      other.tabIndex == tabIndex &&
      other.melodyIndex == melodyIndex;

  @override
  int get hashCode => Object.hash(chordIndex, tabIndex, melodyIndex);
}

/// 系统内一个元素:数据下标 + 系统内横坐标(px)。
class ScoreGlyph {
  const ScoreGlyph(this.anchorIndex, this.anchor, this.x);
  final int anchorIndex;
  final ScoreChordAnchor anchor;
  final double x;
}

class ScoreTabPoint {
  const ScoreTabPoint(
    this.noteIndex,
    this.note,
    this.x, {
    required this.isChordPluck,
    required this.hiddenByStrum,
    required this.groupDuration,
    required this.groupEndX,
  });

  final int noteIndex;
  final TabNote note;
  final double x;

  /// 印张 ×:该音 (弦,品) 恰为当前和弦指形的按位——印张「×=拨该弦,
  /// 品位按当小节和弦指形」(工单 37);画 × 与画品位数字是同一个物理
  /// 动作,× 照印张更直观。旋律音不落在指形位,保持数字(印张同)。
  final bool isChordPluck;

  /// 被扫弦/卷弦事件覆盖(同拍 4 音组画箭头/波浪,不再逐弦画 ×)。
  final bool hiddenByStrum;

  /// 组时值(距下一组;节奏带符杆/符杠由此推导,industry 画法见
  /// [rhythmBeams])。
  final double groupDuration;

  /// 组时值 ≥ 2 拍 = 长音(印张画法 2026-10-25 实测:品位数字外套椭圆;
  /// × 柱长音不套框,只由节奏带长杆表达——「不添加原版没有的符号」)。
  bool get groupHoldBeats => groupDuration >= 2;

  /// 组尾 x(下一组的 x 或带尾),长音延音弧画到这儿。
  final double groupEndX;
}

class ScoreNumPoint {
  const ScoreNumPoint(this.noteIndex, this.symbol, this.x);
  final int noteIndex;
  final NumNote symbol;
  final double x;
}

/// 时值标记(纯函数):拍数 → 下线枚数/附点/横杠枚数。简谱推导与
/// 休止 0 的画笔共用同一标记语义。
class NumDurationMark {
  const NumDurationMark(this.underlines, this.dotted, this.dashes);
  final int underlines;
  final bool dotted;
  final int dashes;
}

NumDurationMark durationMarkOf(double beats) {
  final underlines = beats <= 0.25 + 1e-9
      ? 2
      : (beats <= 0.5 + 1e-9 || (beats - 0.75).abs() < 1e-9 ? 1 : 0);
  final dotted = (beats >= 1 && (beats - beats.truncateToDouble()) == 0.5) ||
      (beats - 0.75).abs() < 1e-9;
  final dashes = beats >= 2.0 - 1e-9 ? beats.truncate() - 1 : 0;
  return NumDurationMark(underlines, dotted, dashes);
}

/// 简谱符号推导(纯函数):逐音「度数+八度点+时值线+延音线弧+逐音歌词
/// +休止 0」。时值 = 距下音 gap(末音到小节收口);延续音(无缀字)距
/// 下音 ≥1 拍时本音记 1 拍、余量出休止(节奏总量与印张逐拍闭合;个别
/// 印张「音·+休」细分差半拍,目验再调)。
/// [alignBeats] = 旋律层 → 主轴的恒定偏移(组合定义唯一记录处):
/// [NumNote.mainBeat] 由此落主轴拍位(弧线端点等按主轴坐标消费)。
List<NumNote> deriveNumberedNotes(TabChart melodyChart,
    {double alignBeats = 0.0}) {
  final notes = sortedTabNotes(melodyChart.notes);
  if (notes.isEmpty) return const [];
  // 小节收口:末音保有整拍后收到整小节线(末音时长的下界,只用于推导)。
  final maxBeat = notes.map((n) => n.beat).reduce(math.max);
  final gridEnd =
      (maxBeat.ceil() / beatsPerBar).ceil() * beatsPerBar;

  final out = <NumNote>[];
  for (var i = 0; i < notes.length; i++) {
    final note = notes[i];
    // midi = 空弦 midi + 品位(整数精确,与发声频率同一换算源,免对数)。
    final midi = UkeString.byNumber(note.string).midi + note.fret;
    // 转录域全为自然音级(C 调白键);染色音说明数据漂移,当场报错。
    final degree = _degreeOfPitchClass(midi % 12);
    final octave = midi ~/ 12 - 5; // midi 60..71(=C4..B4)为 0

    final nextBeat = i + 1 < notes.length ? notes[i + 1].beat : gridEnd;
    final rawDuration = nextBeat - note.beat;
    final isTie = note.lyric == null;
    final shown = isTie && rawDuration > 1.0 ? 1.0 : rawDuration;
    final mark = durationMarkOf(shown);

    out.add(NumNote(
      mainBeat: note.beat + alignBeats,
      degree: degree,
      highDots: math.max(0, octave),
      lowDots: math.max(0, -octave),
      underlines: mark.underlines,
      dotted: mark.dotted,
      dashes: mark.dashes,
      arcOut: i + 1 < notes.length && notes[i + 1].lyric == null,
      restAfter: isTie && rawDuration > 1.0 ? rawDuration - 1.0 : null,
      lyric: note.lyric,
    ));
  }
  return out;
}

int _degreeOfPitchClass(int pitchClass) {
  const map = {0: 1, 2: 2, 4: 3, 5: 4, 7: 5, 9: 6, 11: 7};
  final degree = map[pitchClass];
  if (degree == null) {
    throw ArgumentError('简谱推导遇非自然音级(pitch class $pitchClass):'
        '旋律层数据漂移,拒绝静默渲染');
  }
  return degree;
}

/// 谱面布局:一次构造,横带元素坐标全部就位(谱面整带不变,缓存一次;
/// 跟随高亮只查 [currentAt],不改几何)。
class ScoreSheetLayout {
  ScoreSheetLayout({
    required this.def,
    required this.tabChart,
    required this.melodyChart,
  }) {
    tabNotes = sortedTabNotes(tabChart.notes);
    melodyNotes = sortedTabNotes(melodyChart.notes);
    numberedNotes = deriveNumberedNotes(
      melodyChart,
      alignBeats: def.melodyAlignBeats,
    );

    // 主轴小节:末音保有整拍、收到整小节线(与 tabTotalBeats 同界但
    // 不 +1:谱面照印张收口,不画空白尾小节;曲末判定归时间轴)。
    if (tabNotes.isEmpty) {
      barCount = 0;
    } else {
      final maxBeat = tabNotes.map((n) => n.beat).reduce(math.max);
      barCount = (maxBeat.ceil() / beatsPerBar).ceil();
    }

    // 横带元素预计算(绝对 x,一次构造,播放期只读)。
    _tabBeats = [for (final n in tabNotes) n.beat];
    _melodyBeats = [
      for (final n in melodyNotes) n.beat + def.melodyAlignBeats,
    ];
    _chordBeats = [for (final c in def.chords) c.beat];
    _tabChordPluck = _computeChordPlucks();
    _tabHiddenByStrum = _computeStrumHidden();
    chordGlyphs = [
      for (var i = 0; i < def.chords.length; i++)
        ScoreGlyph(
          i,
          def.chords[i],
          stripX(def.chords[i].beat) - chordGlyphWidth / 2,
        ),
    ];
    // 组时值:同拍一组,距下一组的拍距 = 印张节奏杆(与简谱同推导)。
    final distinctBeats = _tabBeats.toSet().toList()..sort();
    double groupDuration(double beat) {
      final idx = distinctBeats.indexOf(beat);
      final next = idx + 1 < distinctBeats.length
          ? distinctBeats[idx + 1]
          : (distinctBeats.isEmpty
              ? 0
              : (distinctBeats.last.ceil() / beatsPerBar).ceil() *
                  beatsPerBar);
      return next - beat;
    }

    double groupEndX(double beat) {
      final idx = distinctBeats.indexOf(beat);
      final next = idx + 1 < distinctBeats.length
          ? distinctBeats[idx + 1]
          : (distinctBeats.isEmpty
              ? 0.0
              : ((distinctBeats.last.ceil() / beatsPerBar).ceil() *
                  beatsPerBar)
                  .toDouble());
      return stripX(next);
    }

    tabPoints = [
      for (var i = 0; i < tabNotes.length; i++)
        ScoreTabPoint(
          i,
          tabNotes[i],
          stripX(_tabBeats[i]),
          isChordPluck: _tabChordPluck[i],
          hiddenByStrum: _tabHiddenByStrum[i],
          groupDuration: groupDuration(_tabBeats[i]),
          groupEndX: groupEndX(_tabBeats[i]),
        ),
    ];
    numPoints = [
      for (var i = 0; i < numberedNotes.length; i++)
        ScoreNumPoint(i, numberedNotes[i], stripX(_melodyBeats[i])),
    ];

    // 全休止小节:四层皆无(前奏 bar 1;画全休止 0)。
    final barsWithTab = {
      for (final n in tabNotes) (n.beat ~/ beatsPerBar),
    };
    final barsWithMelody = {
      for (final n in melodyNotes)
        ((n.beat + def.melodyAlignBeats) ~/ beatsPerBar),
    };
    final barsWithChords = {
      for (final c in def.chords) (c.beat ~/ beatsPerBar),
    };
    emptyBars = [
      for (var bar = 0; bar < barCount; bar++)
        if (!barsWithTab.contains(bar) &&
            !barsWithMelody.contains(bar) &&
            !barsWithChords.contains(bar))
          bar,
    ];
  }

  final ScoreSheetDef def;
  final TabChart tabChart;
  final TabChart melodyChart;

  // ── 横向参数(连续横带)──
  /// 一档拍位的像素宽:16 分符位 10px 可辨,全曲 108 拍约 4.3kpx。
  static const stripPxPerBeat = 40.0;

  /// 带首留白:谱角调号 + 首和弦与左缘的距离(照印张行首留气口)。
  static const stripLeftPad = 56.0;
  static const stripRightPad = 24.0;

  /// 和弦图窗宽(居中压在锚拍上)与防重叠最小间距。
  static const chordGlyphWidth = 44.0;
  static const chordGlyphGap = 6.0;

  // ── 纵向参数(横带内四层纵带,自上而下)──
  /// 和弦层带高(名+图窗 52px);其下留 [chordTabGap] 再接琴弦层——
  /// 真机两轮反馈:和弦图与琴弦贴得太近,一轮加 10px 仍挤,再加到 20。
  static const chordBandHeight = 68.0;

  /// 和弦层与琴弦层的间隔。
  static const chordTabGap = 20.0;
  static const tabTopPad = 8.0;
  static const tabLineGap = 14.0;
  static const tabBandHeight = tabTopPad + 3 * tabLineGap + 8.0;

  /// 简谱带(高音点 8 + 度数 14 + 时值线 6 + 上下余量)与歌词带——
  /// 琴弦行与歌词行之间同步放宽(真机反馈 2026-10-24)。
  /// 节奏带(TAB staff 下方,industry 惯例:alphaTab rhythmHeight 默认 25,
  /// 「rendered below the tab staff」;Soundslice/Songsterr 同式)。
  static const rhythmBandHeight = 25.0;
  static const numBandHeight = 38.0;
  static const lyricBandHeight = 22.0;

  // 字号(静态带与当位覆盖层重绘必须逐像素同位,字号一并单源)。
  static const numFontSize = 14.0;
  static const lyricFontSize = 11.0;
  static const tabFontSize = 10.0;

  // ── 纵带 y 坐标(唯一来源;静态带与当位覆盖层共用,改间距只动这里)──

  /// TAB 弦线区顶(①弦线 y)。
  static double get tabBandTop =>
      chordBandHeight + chordTabGap + tabTopPad;

  /// TAB 弦线区底(④弦线 y)。
  static double get tabBandBottom => tabBandTop + 3 * tabLineGap;

  /// 节奏带顶(staff 下方符杆/符杠区)。
  static double get rhythmBandTop => tabBandBottom + 6;

  /// 简谱带顶。
  static double get numBandTop =>
      chordBandHeight + chordTabGap + tabBandHeight + rhythmBandHeight;

  /// 简谱度数行的纵中心。
  static double get numCenterY => numBandTop + 8 + numFontSize / 2;

  /// 歌词行的纵中心。
  static double get lyricCenterY =>
      numBandTop + numBandHeight + lyricBandHeight / 2;
  static const systemGap = 16.0;
  static const systemHeight = chordBandHeight +
      chordTabGap +
      tabBandHeight +
      numBandHeight +
      lyricBandHeight;

  late final List<TabNote> tabNotes;
  late final List<TabNote> melodyNotes;
  late final List<NumNote> numberedNotes;

  /// 全曲小节数(主轴网格收口)。
  late final int barCount;

  /// 横带四层元素(绝对坐标,一次预计算)。
  late final List<ScoreGlyph> chordGlyphs;
  late final List<ScoreTabPoint> tabPoints;
  late final List<ScoreNumPoint> numPoints;

  /// 四层皆无元素的小节(全休止,画 0)。
  late final List<int> emptyBars;

  /// 主轴拍位 → 横带绝对 x(线性:时值即距离)。
  double stripX(double mainBeat) =>
      stripLeftPad + mainBeat * stripPxPerBeat;

  /// 第 [bar] 小节线(0 起)的绝对 x。
  double barX(int bar) => stripX(bar * beatsPerBar.toDouble());

  /// 横带总宽:覆盖主轴网格收口 + 右留白。
  double get stripWidth =>
      (barCount == 0 ? stripLeftPad : barX(barCount)) + stripRightPad;

  /// 休止事件(照印张渲染;x 坐标预计算)。
  late final List<({double x, double beat, double beats})> restEvents = [
    for (final e in def.rests) (x: stripX(e.beat), beat: e.beat, beats: e.beats),
  ];

  /// 震音记号(照印张渲染:瘦椭圆罩四弦 × 柱;x 坐标预计算)。
  late final List<({double x, double beat})> tremoloMarks = [
    for (final e in def.tremolos) (x: stripX(e.beat), beat: e.beat),
  ];

  /// 连音 × 柱(印张「×柱带连音弧=不占拍无攻击」):扫弦段(有 ≥3 个
  /// 扫弦事件的小节)的小节第 3 拍,若该拍无攻击,画淡 × 柱并从上一组
  /// 引延音弧(高置段/尾每小节一处,数据空档与印张逐一吻合)。
  late final List<double> tiedColumns = _computeTiedColumns();

  List<double> _computeTiedColumns() {
    final barsWithStrums = <int>{};
    for (final e in def.strums) {
      barsWithStrums.add(e.beat ~/ beatsPerBar);
    }
    final attacked = _tabBeats.toSet();
    final out = <double>[];
    for (final bar in barsWithStrums) {
      final beat = (bar * beatsPerBar + 2).toDouble();
      if (beat >= barCount * beatsPerBar) continue;
      if (attacked.contains(beat)) continue;
      // 休止区间内不画连音柱(那是休止记号的地盘,照印张)。
      if (def.rests.any((r) => beat >= r.beat && beat < r.beat + r.beats)) {
        continue;
      }
      out.add(beat);
    }
    return out..sort();
  }

  // ── 节奏带(industry 画法:杆下垂、同拍组符杠横连、孤立组符尾)──

  /// 每组一根符杆(x,时值;二分以上更长裸杆,四分裸杆)。
  late final List<({double x, double duration})> rhythmStems = [
    for (final p in tabPoints)
      if (identical(p, tabPoints.firstWhere((q) => q.note.beat == p.note.beat)))
        (x: p.x, duration: p.groupDuration),
  ];

  /// 符杠:同一整数拍窗内连续可连组(时值 ≤ 0.5)横连一条;
  /// 相邻对都 ≤ 0.25 再加第二条(十六分)。
  late final List<({double x0, double x1, int level})> rhythmBeams = () {
    final beams = <({double x0, double x1, int level})>[];
    final groups = rhythmStems;
    var i = 0;
    while (i < groups.length) {
      if (groups[i].duration > 0.5) {
        i++;
        continue;
      }
      var j = i;
      while (j + 1 < groups.length &&
          groups[j + 1].duration <= 0.5 &&
          groups[j + 1].x ~/ stripPxPerBeat == groups[i].x ~/ stripPxPerBeat) {
        j++;
      }
      if (j > i) {
        beams.add((x0: groups[i].x, x1: groups[j].x, level: 1));
        for (var k = i; k < j; k++) {
          if (groups[k].duration <= 0.25 && groups[k + 1].duration <= 0.25) {
            beams.add((x0: groups[k].x, x1: groups[k + 1].x, level: 2));
          }
        }
      }
      i = j + 1;
    }
    return beams;
  }();

  /// 孤立可连组(无符杠伙伴)的符尾枚数:八分 1、十六分 2。
  late final List<({double x, int flags})> rhythmFlags = [
    for (var i = 0; i < rhythmStems.length; i++)
      if (rhythmStems[i].duration > 0 && rhythmStems[i].duration <= 0.5)
        if (!rhythmBeams.any((bm) =>
            rhythmStems[i].x >= bm.x0 - 1 && rhythmStems[i].x <= bm.x1 + 1))
          (
            x: rhythmStems[i].x,
            flags: rhythmStems[i].duration <= 0.25 ? 2 : 1,
          )
  ];

  /// 跟随高亮的跟滚锚点:播放头恒在视口左 1/3(流水展示,用户 2026-10-24)。
  static const followViewportFraction = 1 / 3;

  /// 跟随高亮当位查询:主轴拍位 → 四层当前元素(GLOSSARY「跟随高亮」)。
  /// 尾拍越过网格钳到最后元素(拍 108-112 的无声尾段谱面驻留收尾)。
  ScoreCursor currentAt(double mainBeat) => ScoreCursor(
    chordIndex: _lastAtOrBefore(_chordBeats, mainBeat),
    tabIndex: _lastAtOrBefore(_tabBeats, mainBeat),
    melodyIndex: _lastAtOrBefore(_melodyBeats, mainBeat),
  );

  late final List<bool> _tabChordPluck;
  late final List<bool> _tabHiddenByStrum;
  late final List<double> _tabBeats;
  late final List<double> _melodyBeats;
  late final List<double> _chordBeats;

  /// 逐音 × 判定:(弦,品) == 当前和弦锚(拍 ≤ 该音)指形的按位。
  /// 无锚(前奏 bar 1 前)或指形闷音位(-1)不判 ×。
  List<bool> _computeChordPlucks() {
    final plucks = List<bool>.filled(tabNotes.length, false);
    for (var i = 0; i < tabNotes.length; i++) {
      final anchorIdx = _lastAtOrBefore(_chordBeats, _tabBeats[i]);
      if (anchorIdx < 0) continue;
      final note = tabNotes[i];
      final shapeFret =
          def.chords[anchorIdx].fingering.frets[4 - note.string];
      plucks[i] = shapeFret == note.fret;
    }
    return plucks;
  }

  /// 扫弦事件的种类查询(同拍一组);无事件 null。
  ScoreStrumKind? strumKindAt(double mainBeat) {
    for (final e in def.strums) {
      if (e.beat == mainBeat) return e.kind;
    }
    return null;
  }

  /// 被扫弦遮蔽的逐音 ×:该拍有扫弦事件且本音落指形位
  /// (旋律音即使在扫弦拍也保持数字)。休止区间 [beat, beat+beats) 内的
  /// 音同样遮蔽(显示照印张画休止记号;发声不受影响)。
  List<bool> _computeStrumHidden() {
    final hidden = List<bool>.filled(tabNotes.length, false);
    for (var i = 0; i < tabNotes.length; i++) {
      final inRest = def.rests.any(
        (r) => _tabBeats[i] >= r.beat && _tabBeats[i] < r.beat + r.beats,
      );
      hidden[i] =
          (strumKindAt(_tabBeats[i]) != null && _tabChordPluck[i]) || inRest;
    }
    return hidden;
  }

  /// 升序拍位列表里最后一个 ≤ [beat] 的下标;无则 -1。二分查找。
  static int _lastAtOrBefore(List<double> beats, double beat) {
    if (beats.isEmpty || beat < beats.first) return -1;
    var low = 0;
    var high = beats.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (beats[mid] <= beat) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
  }
}
