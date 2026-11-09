

/// 排版规则层(codex `engraving.mjs` 的移植):符杠分组、符尾层数、休止
/// 符形、琶音/扫弦记号。纯函数、零画面依赖——画面层消费这些结果绘制。
///
/// 节奏语义来自一手数据;分组规则按移植源:
/// - 八分音符按四分音符拍两两相连(4/4);6/8 等复拍按三连组(1440 tick);
/// - 延音尾音仍参与符杠(原谱画法:重复数字隐藏,节奏可见);
/// - 符尾层数 = log2(时值分母) − 2(四分 0、八分 1、十六分 2);
/// - 休止符形 = Bravura 码点 0xE4E3 + log2(时值);
/// - 原网页在延音和弦处重复显示的琶音标记,照原样保留(只影响画面,
///   不给声音加一次弹奏——调度层延音已剔除)。
library;

import 'dart:math' as math;

import 'flowing_timeline.dart';

import 'reference_score.dart';

/// 一组符杠片段:from→to 事件,第 [level] 层(1 起);[hook] 非空表示
/// 只画短横钩(left/right 自 from 伸出),连横线为 null。
class BeamSegment {
  const BeamSegment({
    required this.from,
    required this.to,
    required this.level,
    this.hook,
  });

  final int from;
  final int to;
  final int level;
  final String? hook;
}

/// 一处琶音/扫弦记号。[isArpeggio] = 波浪琶音(brushType 3/4),否则直箭
/// 扫弦(1/2);[up] = 画面向上。
class BrushMark {
  const BrushMark({
    required this.eventId,
    required this.isArpeggio,
    required this.up,
  });

  final int eventId;
  final bool isArpeggio;
  final bool up;
}

/// 一个事件的节奏记谱要素。
class RhythmGlyph {
  const RhythmGlyph({
    required this.flags,
    required this.dots,
    required this.restCodePoint,
  });

  /// 符尾层数(连横线已盖住的层数由 [BeamSegment] 补足)。
  final int flags;
  final int dots;

  /// 休止符形 Bravura 码点;非休止事件无意义。
  final int restCodePoint;
}

/// 整曲排版要素(codex 同名字段语义)。
class EngravingPlan {
  const EngravingPlan({
    required this.beams,
    required this.beamSegments,
    required this.rhythms,
    required this.brushes,
  });

  /// 笛杠分组对(事件 id 对,已连横线;观察/回归用)。
  final List<(int, int)> beams;
  final List<BeamSegment> beamSegments;
  final Map<int, RhythmGlyph> rhythms;
  final List<BrushMark> brushes;

  RhythmGlyph? rhythmOf(int eventId) => rhythms[eventId];
}

int _flagsFor(RefEvent event) =>
    math.max(0, (math.log(event.durationValue) / math.ln2).round() - 2);

int _groupTicks(RefMeasure measure) =>
    measure.denominator == 8 && measure.numerator % 3 == 0 ? 1440 : 960;

int _restCodePoint(RefEvent event) =>
    0xE4E3 + (math.log(event.durationValue) / math.ln2).round();

/// 从练习时间表推导整曲排版要素。规则与移植源逐条对应,真值闸:
/// 《天空之城》= 115 组符杠、88 处琶音/扫弦、9 个独立符尾。
EngravingPlan buildEngravingPlan(ReferenceScore score) {
  final events = score.events;
  final beams = <(int, int)>[];
  for (var i = 1; i < events.length; i++) {
    final a = events[i - 1];
    final b = events[i];
    // 八分音符在同一个四分音符拍内相连;休止不入杠;延音尾音照样入杠。
    if (a.measureIndex == b.measureIndex &&
        a.notes.isNotEmpty &&
        b.notes.isNotEmpty &&
        a.durationValue >= 8 &&
        b.durationValue >= 8 &&
        a.startTick ~/ _groupTicks(score.measures[a.measureIndex]) ==
            b.startTick ~/ _groupTicks(score.measures[b.measureIndex])) {
      beams.add((a.id, b.id));
    }
  }
  final beamSegments = <BeamSegment>[];
  final byId = {for (final e in events) e.id: e};
  for (final (fromId, toId) in beams) {
    final a = byId[fromId]!;
    final b = byId[toId]!;
    final levels = math.min(_flagsFor(a), _flagsFor(b));
    for (var level = 1; level <= levels; level++) {
      beamSegments.add(BeamSegment(from: fromId, to: toId, level: level));
    }
  }
  // 部分横钩:入杠事件更高层若无横线盖住,画一条短钩(方向按其在组内的位次)。
  for (final event in events) {
    if (event.notes.isEmpty) continue;
    final connected = beams.where((pair) => pair.$1 == event.id || pair.$2 == event.id);
    if (connected.isEmpty) continue;
    for (var level = 2; level <= _flagsFor(event); level++) {
      final covered = beamSegments.any(
          (s) => s.level == level && (s.from == event.id || s.to == event.id));
      if (covered) continue;
      final pair = connected.firstWhere((p) => p.$1 == event.id,
          orElse: () => connected.first);
      final other = pair.$1 == event.id ? pair.$2 : pair.$1;
      beamSegments.add(BeamSegment(
        from: event.id,
        to: other,
        level: level,
        hook: pair.$1 == event.id ? 'right' : 'left',
      ));
    }
  }
  final rhythms = <int, RhythmGlyph>{
    for (final e in events)
      e.id: RhythmGlyph(
        flags: _flagsFor(e),
        dots: e.dots,
        restCodePoint: _restCodePoint(e),
      ),
  };
  // 琶音/扫弦:brushType 1/2 = 直箭扫弦,3/4 = 波浪琶音;偶数向上。
  // 原网页在延音和弦处继续显示起点音的标记(续拍 brushType=0):照原样
  // 保留为画面记号,不加声音(调度层延音已剔除,天然一致)。
  final eventByNoteId = <int, RefEvent>{};
  for (final e in events) {
    for (final n in e.notes) {
      eventByNoteId[n.id] = e;
    }
  }
  final brushes = <BrushMark>[];
  for (final e in events) {
    if (e.notes.isEmpty) continue;
    var type = e.brushType;
    if (type == 0 &&
        e.notes.length > 1 &&
        e.notes.every((n) => n.isTieDestination)) {
      final originId = e.notes.first.tieOriginNoteId;
      final originEvent = originId == null ? null : eventByNoteId[originId];
      type = originEvent?.brushType ?? 0;
    }
    if (type == 0) continue;
    if (type < 1 || type > 4) {
      throw ScoreImportException('不支持的扫弦/琶音类型:$type');
    }
    brushes.add(BrushMark(
      eventId: e.id,
      isArpeggio: type >= 3,
      up: type % 2 == 0,
    ));
  }
  return EngravingPlan(
    beams: beams,
    beamSegments: beamSegments,
    rhythms: rhythms,
    brushes: brushes,
  );
}

/// ===== 排版层(纯函数,零绘制依赖) =====
///
/// codex 核心方法:所有字形的类型/位置在此一次算清,渲染层只消费
/// 数据作画。排版问题 → 改本层规则/参数(一处),渲染层永不动。
/// 全部坐标为逻辑像素。

/// 垂直几何:四弦行、杆底、时间尺、休止基线、画布高。
class FlowingGeometry {
  const FlowingGeometry();

  /// 四弦行 y(逻辑坐标)。
  static const List<double> rows = [124, 149, 174, 199];

  /// 界面弦号(1..4)的行 y。
  static double rowY(int stringNo) => rows[(stringNo - 1).clamp(0, 3)];

  /// 符杆/符杠底线(用户定案:杆下伸加空隙)。
  static const double stemBottom = 253;

  /// 符杠层距。
  static const double beamGap = 7;

  /// 时间尺刻度线/文字 y。
  static const double timeTick = 271;
  static const double timeLabel = 282;

  /// 休止符基线 y。
  static const double restY = 170;

  /// 逻辑画布高。
  static const double height = 294;
}

/// 一颗品位数字的字形(x = 数字中心,渲染层骑线垂直居中)。
class DigitGlyph {
  const DigitGlyph(this.text, this.x, this.rowY, this.noteId);
  final String text;
  final double x;
  final double rowY;
  final int noteId;
}

/// 一条滑音线(x1,y1 → x2,y2)。
class SlideGlyph {
  const SlideGlyph(this.x1, this.y1, this.x2, this.y2);
  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

/// 一根附点(附于杆右)。
class DotGlyph {
  const DotGlyph(this.x, this.y);
  final double x;
  final double y;
}

/// 一条独立符尾(q 曲线,自杆底向上)。
class FlagGlyph {
  const FlagGlyph(this.x, this.y, this.count);
  final double x;
  final double y;
  final int count;
}

/// 事件级字形包:该事件要画的全部东西,位置全部预计算。
/// 「是否当弹」是渲染层呈现态,不在排版数据里。
class EventGlyphs {
  const EventGlyphs({
    required this.event,
    required this.x,
    required this.isTieChord,
    required this.digits,
    required this.slides,
    required this.stemX,
    required this.stemTop,
    required this.flag,
    required this.dots,
    required this.restX,
    required this.restGlyph,
    required this.waveBx,
    required this.waveTop,
    required this.waveBottom,
    required this.waveUp,
    required this.waveIsArpeggio,
    required this.chordX,
    required this.chord,
  });

  final RefEvent event;
  final double x;
  final bool isTieChord;
  final List<DigitGlyph> digits;
  final List<SlideGlyph> slides;
  final double? stemX;
  final double stemTop;
  final FlagGlyph? flag;
  final List<DotGlyph> dots;
  final double? restX;
  final String restGlyph;
  final double? waveBx;
  final double waveTop;
  final double waveBottom;
  final bool waveUp;
  final bool waveIsArpeggio;
  final double? chordX;
  final RefChord? chord;
}

/// 一根小节线 + 编号(线在时间原点左 15px;编号在线右、谱上方)。
class MeasureBar {
  const MeasureBar(this.lineX, this.numberX, this.numberY, this.number);
  final double lineX;
  final double numberX;
  final double numberY;
  final String number;
}

/// 绝对坐标的符杠段(x1→x2 同高;短钩时 x2 为钩端)。
class BeamBar {
  const BeamBar(this.x1, this.x2, this.y, this.level);
  final double x1;
  final double x2;
  final double y;
  final int level;
}

/// 时间尺刻度。
class TimeTickGlyph {
  const TimeTickGlyph(this.x, this.label);
  final double x;
  final String label;
}

/// 排版总产物:渲染层唯一的输入。
class FlowingEngraving {
  FlowingEngraving._({
    required this.layout,
    required this.geometry,
    required this.bars,
    required this.eventGlyphs,
    required this.beamBars,
    required this.timeTicks,
    required this.endBarX,
    required this.tieArcs,
    required this.headerTexts,
  });

  final FlowingLayout layout;
  final FlowingGeometry geometry;
  final List<MeasureBar> bars;
  final List<EventGlyphs> eventGlyphs;
  final List<BeamBar> beamBars;
  final List<TimeTickGlyph> timeTicks;
  final double endBarX;

  /// 全曲时长(秒)。
  double get durationSeconds => layout.durationSecondsOfSong;

  /// 延音小弧(事件 id → 弧的起止 x,画在谱面上方)。
  final Map<int, (double, double)> tieArcs;

  /// 谱面文字标记(段落名 + 曲头调号/拍号/速度)。
  final List<({double x, String text, bool bold})> headerTexts;

  /// 查延音小弧。
  ({double x1, double x2})? tieArcOf(int eventId) {
    final arc = tieArcs[eventId];
    return arc == null ? null : (x1: arc.$1, x2: arc.$2);
  }

  /// 构建整曲排版。
  factory FlowingEngraving.build(
    ReferenceScore score, {
    required FlowingLayout layout,
    required EngravingPlan plan,
  }) {
    // 小节线:时间原点左 15px(首音净空);编号在线右侧、谱面上方。
    final bars = <MeasureBar>[
      for (final m in score.measures)
        MeasureBar(
          layout.measureLeftX[m.index] - 15,
          layout.measureLeftX[m.index] - 12,
          110,
          '${m.index + 1}',
        ),
    ];

    // 音符 id → 所属事件;延音和弦及其源头。
    final eventByNoteId = <int, RefEvent>{};
    for (final e in score.events) {
      for (final n in e.notes) {
        eventByNoteId[n.id] = e;
      }
    }
    final tieChords = <int>{};
    final tieOrigin = <int, RefEvent>{};
    for (final e in score.events) {
      if (e.notes.isNotEmpty && e.notes.every((n) => n.isTieDestination)) {
        tieChords.add(e.id);
        final oid = e.notes.first.tieOriginNoteId;
        if (oid != null) {
          final oe = eventByNoteId[oid];
          if (oe != null) tieOrigin[e.id] = oe;
        }
      }
    }

    // 滑音终点表:同弦上此事件之后第一个带音事件(顺序单扫,全曲 O(n))。
    final slideTarget = <int, (RefEvent, RefNote)>{};
    final pending = <int, (RefEvent, RefNote)>{}; // 行 0 基弦 → (事件, 起点音)
    for (final e in score.events) {
      if (e.notes.isNotEmpty) {
        for (final row in pending.keys.toList()) {
          final hit = e.notes.where((n) => n.stringNo - 1 == row).firstOrNull;
          if (hit != null) {
            slideTarget[pending[row]!.$2.id] = (e, hit);
            pending.remove(row);
          }
        }
      }
      for (final n in e.notes) {
        if (n.hasSlideOut) pending[n.stringNo - 1] = (e, n);
      }
    }

    // 逐事件字形包。
    final glyphs = <EventGlyphs>[];
    for (final e in score.events) {
      final x = layout.positionAt(e.startSeconds);
      final isTie = tieChords.contains(e.id);
      final rhythm = plan.rhythmOf(e.id);
      final rowY = FlowingGeometry.rowY;

      final digits = <DigitGlyph>[];
      if (!isTie) {
        for (final n in e.notes) {
          digits.add(DigitGlyph(
            n.isNaturalHarmonic ? '<${n.fret}>' : '${n.fret}',
            x,
            rowY(n.stringNo),
            n.id,
          ));
        }
      }

      final slides = <SlideGlyph>[];
      for (final n in e.notes) {
        final hit = slideTarget[n.id];
        if (hit == null) continue;
        final y = rowY(n.stringNo);
        final ty = rowY(hit.$2.stringNo);
        final dir = hit.$2.fret > n.fret ? -1.0 : 1.0;
        slides.add(SlideGlyph(
          x + 12,
          y + 4 * dir,
          layout.positionAt(hit.$1.startSeconds) - 12,
          ty - 4 * dir,
        ));
      }

      // 符杆:与数字列正中对齐,杆顶 = 最低音弦的下一根弦线(钳到 G 弦)。
      final beamed = plan.beams.any((p) => p.$1 == e.id || p.$2 == e.id);
      double? stemX;
      double? stemTop;
      if (e.notes.isNotEmpty && !isTie) {
        stemX = x;
        final lowest = e.notes.map((n) => n.stringNo).reduce(math.max);
        stemTop = rowY(math.min(lowest, 3)) + 2;
      }
      final flag = (!beamed && e.notes.isNotEmpty && (rhythm?.flags ?? 0) > 0)
          ? FlagGlyph(x, FlowingGeometry.stemBottom, rhythm?.flags ?? 0)
          : null;

      final dots = <DotGlyph>[
        for (var d = 0; d < (rhythm?.dots ?? 0); d++)
          DotGlyph(x + 9 + d * 5, FlowingGeometry.stemBottom - 21),
      ];

      final wave = plan.brushes.where((b) => b.eventId == e.id).firstOrNull;
      final waveBx = wave == null || e.notes.isEmpty
          ? null
          : x - (e.notes.any((n) => n.isNaturalHarmonic) ? 20.0 : 9.0);
      final waveTop = e.notes.isEmpty
          ? 0.0
          : e.notes.map((n) => rowY(n.stringNo)).reduce(math.min) - 3;
      final waveBottom = e.notes.isEmpty
          ? 0.0
          : e.notes.map((n) => rowY(n.stringNo)).reduce(math.max) + 3;

      glyphs.add(EventGlyphs(
        event: e,
        x: x,
        isTieChord: isTie,
        digits: digits,
        slides: slides,
        stemX: stemX,
        stemTop: stemTop ?? 0,
        flag: flag,
        dots: dots,
        restX: e.isRest ? x : null,
        restGlyph: String.fromCharCode(rhythm?.restCodePoint ?? 0xE4E5),
        waveBx: waveBx,
        waveTop: waveTop,
        waveBottom: waveBottom,
        waveUp: wave?.up ?? false,
        waveIsArpeggio: wave?.isArpeggio ?? false,
        chordX: e.chord == null ? null : x + 4,
        chord: e.chord,
      ));
    }

    // 绝对符杠段(杆位 = 事件原点,与符杆同一来源)。
    final byId = {for (final e in score.events) e.id: e};
    final beamBars = <BeamBar>[];
    for (final seg in plan.beamSegments) {
      final first = byId[seg.from]!;
      final last = byId[seg.to]!;
      final x1 = layout.positionAt(first.startSeconds);
      final x2 = seg.hook != null
          ? x1 + (seg.hook == 'left' ? -12 : 12)
          : layout.positionAt(last.startSeconds);
      beamBars.add(BeamBar(
        x1,
        x2,
        FlowingGeometry.stemBottom - (seg.level - 1) * FlowingGeometry.beamGap,
        seg.level,
      ));
    }

    final timeTicks = <TimeTickGlyph>[];
    for (var sec = 0.0; sec <= score.durationSeconds; sec += 5) {
      final total = sec.floor().clamp(0, 36000);
      timeTicks.add(TimeTickGlyph(
        layout.positionAt(sec),
        '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}',
      ));
    }

    // 延音小弧:延音和弦 → 源头和弦(谱面上方,源右缘 → 本位置右缘)。
    final tieArcs = <int, (double, double)>{};
    for (final e in score.events) {
      final origin = tieOrigin[e.id];
      if (origin == null) continue;
      tieArcs[e.id] = (
        layout.positionAt(origin.startSeconds) + 3,
        layout.positionAt(e.startSeconds) + 3,
      );
    }

    // 谱面文字标记:段落名(起始小节上方)+ 曲头调号/拍号/速度。
    final headerTexts = <({double x, String text, bool bold})>[
      for (final m in score.measures)
        if (m.section != null)
          (
            x: layout.measureLeftX[m.index] - 12,
            text: m.section!,
            bold: true,
          ),
      (
        x: layout.measureLeftX.first + 2,
        text:
            'key = ${keyName(score.keySignature)} ${score.measures.first.numerator}/${score.measures.first.denominator}',
        bold: true,
      ),
      (
        x: layout.measureLeftX.first + 120,
        text: '= ${score.measures.first.tempo}',
        bold: false,
      ),
    ];

    return FlowingEngraving._(
      layout: layout,
      geometry: const FlowingGeometry(),
      bars: bars,
      eventGlyphs: glyphs,
      beamBars: beamBars,
      timeTicks: timeTicks,
      endBarX: layout.endX - 15,
      tieArcs: tieArcs,
      headerTexts: headerTexts,
    );
  }
}
