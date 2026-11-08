

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
