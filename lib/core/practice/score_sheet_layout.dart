/// 谱面布局内核(工单 39 测试缝①,GLOSSARY「谱面视图」「谱表系统」):
/// (组合定义, 内容宽) → 系统切分 + 四层元素坐标 + 简谱符号推导 + 跟随
/// 高亮当位查询。纯函数、零引擎依赖,CustomPainter 只做笔画——绘制与
/// 数据一致的保证点全在这里,与 TabChartLayout 同一分工。
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
  });

  final int noteIndex;
  final TabNote note;
  final double x;

  /// 印张 ×:该音 (弦,品) 恰为当前和弦指形的按位——印张「×=拨该弦,
  /// 品位按当小节和弦指形」(工单 37);画 × 与画品位数字是同一个物理
  /// 动作,× 照印张更直观。旋律音不落在指形位,保持数字(印张同)。
  final bool isChordPluck;
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

/// 谱面布局:一次构造,全部几何与系统切片就位(谱面整页不变,缓存一次;
/// 跟随高亮只查 [currentAt],不改几何)。
class ScoreSheetLayout {
  ScoreSheetLayout({
    required this.def,
    required this.tabChart,
    required this.melodyChart,
    required double contentWidth,
  }) : contentWidth = math.max(0.0, contentWidth) {
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
    barsPerSystem = contentWidth <= 0
        ? 1
        : (contentWidth / (beatsPerBar * minPxPerBeat))
            .floor()
            .clamp(1, maxBarsPerSystem);
    pxPerBeat = contentWidth / (barsPerSystem * beatsPerBar);
    systemCount = barCount == 0 ? 0 : (barCount / barsPerSystem).ceil();

    // 预切片:每系统的 TAB/简谱下标区间(音符按拍位升序,二分定位)。
    _tabBeats = [for (final n in tabNotes) n.beat];
    _melodyBeats = [
      for (final n in melodyNotes) n.beat + def.melodyAlignBeats,
    ];
    _chordBeats = [for (final c in def.chords) c.beat];
    _tabChordPluck = _computeChordPlucks();
    _tabSlices = _slices(_tabBeats);
    _melodySlices = _slices(_melodyBeats);

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

  /// 系统内容宽(px,页面按屏宽扣除边距后传入)。
  final double contentWidth;

  // ── 横向参数 ──
  /// 一档拍位的最小像素宽(16 分符位可辨的下限,定每系统小节数)。
  static const minPxPerBeat = 36.0;

  /// 每系统小节数上限(A4 印张版面)。
  static const maxBarsPerSystem = 4;

  /// 和弦图窗宽与防重叠最小间距。
  static const chordGlyphWidth = 44.0;
  static const chordGlyphGap = 6.0;

  // ── 纵向参数(系统内四层纵带,自上而下)──
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
  static const numBandHeight = 38.0;
  static const lyricBandHeight = 22.0;
  static const systemGap = 16.0;
  static const systemHeight = chordBandHeight +
      chordTabGap +
      tabBandHeight +
      numBandHeight +
      lyricBandHeight;

  late final List<TabNote> tabNotes;
  late final List<TabNote> melodyNotes;
  late final List<NumNote> numberedNotes;

  /// 全曲小节数(主轴网格收口)与系统切分。
  late final int barCount;
  late final int barsPerSystem;

  /// 系统内一档拍位的像素宽(系统满幅均分)。
  late final double pxPerBeat;
  late final int systemCount;

  /// 四层皆无元素的小节(全休止,画 0)。
  late final List<int> emptyBars;

  double get barWidth => beatsPerBar * pxPerBeat;

  int systemOfBar(int bar) => bar ~/ barsPerSystem;

  int firstBarOfSystem(int system) => system * barsPerSystem;

  int barsInSystem(int system) =>
      math.min(barsPerSystem, barCount - firstBarOfSystem(system));

  double systemStartBeat(int system) =>
      firstBarOfSystem(system) * beatsPerBar.toDouble();

  double systemEndBeat(int system) =>
      (firstBarOfSystem(system) + barsInSystem(system)) *
      beatsPerBar.toDouble();

  /// 主轴拍位 → 系统(末小节线后的尾拍钳进最后小节,曲末尾拍不越界)。
  int systemOfBeat(double mainBeat) {
    final bar = (mainBeat ~/ beatsPerBar).toInt().clamp(0, barCount - 1);
    return systemOfBar(bar);
  }

  /// 第 [system] 系统内第 [bar] 小节线的横坐标(0 = 行首)。
  double barXInSystem(int system, int bar) =>
      (bar - firstBarOfSystem(system)) * barWidth;

  /// 主轴拍位在该系统内的横坐标。
  double beatXInSystem(int system, double mainBeat) =>
      (mainBeat - systemStartBeat(system)) * pxPerBeat;

  /// 系统的和弦层:锚拍在系统内的拍锚,防重叠右移后钳回行宽。
  List<ScoreGlyph> chordsInSystem(int system) {
    final start = systemStartBeat(system);
    final end = systemEndBeat(system);
    final glyphs = <ScoreGlyph>[];
    double? prevRight;
    for (var i = 0; i < def.chords.length; i++) {
      final anchor = def.chords[i];
      if (anchor.beat < start || anchor.beat >= end) continue;
      var x = beatXInSystem(system, anchor.beat);
      if (prevRight != null && x < prevRight) {
        x = prevRight; // 与前一枚图留最小间距(拍距密于图宽时顺移)。
      }
      x = math.min(x, math.max(0.0, contentWidth - chordGlyphWidth));
      prevRight = x + chordGlyphWidth + chordGlyphGap;
      glyphs.add(ScoreGlyph(i, anchor, x));
    }
    return glyphs;
  }

  /// 系统的 TAB 层音点(按拍位升序,带印张 × 标记)。
  List<ScoreTabPoint> tabInSystem(int system) {
    final (start, end) = _tabSlices[system];
    return [
      for (var i = start; i < end; i++)
        ScoreTabPoint(
          i,
          tabNotes[i],
          beatXInSystem(system, _tabBeats[i]),
          isChordPluck: _tabChordPluck[i],
        ),
    ];
  }

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

  /// 系统的简谱层符号(含歌词,按拍位升序)。
  List<ScoreNumPoint> numberedInSystem(int system) {
    final (start, end) = _melodySlices[system];
    return [
      for (var i = start; i < end; i++)
        ScoreNumPoint(
          i,
          numberedNotes[i],
          beatXInSystem(system, _melodyBeats[i]),
        ),
    ];
  }

  /// 跟随高亮当位查询:主轴拍位 → 四层当前元素(GLOSSARY「跟随高亮」)。
  /// 尾拍越过网格钳到最后元素(拍 108-112 的无声尾段谱面驻留收尾)。
  ScoreCursor currentAt(double mainBeat) => ScoreCursor(
    chordIndex: _lastAtOrBefore(_chordBeats, mainBeat),
    tabIndex: _lastAtOrBefore(_tabBeats, mainBeat),
    melodyIndex: _lastAtOrBefore(_melodyBeats, mainBeat),
  );

  late final List<bool> _tabChordPluck;
  late final List<double> _tabBeats;
  late final List<double> _melodyBeats;
  late final List<double> _chordBeats;
  late final List<(int, int)> _tabSlices;
  late final List<(int, int)> _melodySlices;

  /// 每系统的音序下标区间 [start, end):按系统起讫拍二分切片。
  List<(int, int)> _slices(List<double> beats) {
    final slices = <(int, int)>[];
    var cursor = 0;
    for (var s = 0; s < systemCount; s++) {
      final start = _lowerBound(beats, systemStartBeat(s), cursor);
      final end = _lowerBound(beats, systemEndBeat(s), start);
      slices.add((start, end));
      cursor = start;
    }
    return slices;
  }

  static int _lowerBound(List<double> beats, double value, int from) {
    var low = from;
    var high = beats.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (beats[mid] < value) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
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
