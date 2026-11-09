import 'dart:math' as math;

import 'reference_score.dart';

/// 流水谱的「时间 → 画面位置」唯一对照表（codex engraving 的移植）。
///
/// codex 方法（2026-11-08 核验）：每个小节起点留 [leftGutter]、末尾留
/// [rightGutter] 排版空白；画面位置 = 时间 × 每秒像素 + 逐小节固定留白。
/// **留白只影响画面，不影响声音时间**——相机（跟滚偏移）与每个音形
/// （数字/小节线/时间刻度）共用 [positionAt]，跨界平滑穿过留白，绝不
/// 在小节边界跳变，也绝不允许任何消费方用「秒 × 像素」另算一套。
class FlowingLayout {
  FlowingLayout._(
    this.pixelsPerSecond,
    this.measureLeftX,
    this._slopes,
    this.endX,
    this._anchorTimes,
    this._anchorXs,
  );

  /// 从练习时间表构建。锚点 = **每个事件起点 + 曲末**(codex 忠实方案,
  /// 2026-11-08 真机教训:不得插入小节末锚点)。
  ///
  /// **全曲匀速等宽**(2026-11-08 用户定案「照抄 codex/匀速」终版):
  /// x = 原点 + 时间 ×每秒像素,零留白、无密度地板——小节交界只随拍速
  /// 自然变化,无任何突跳;小节首音画在小节线上(线由画笔左移 15px
  /// 绘制,给首音让位,原谱同款:首音就在小节线上)。数字 13.5px 配
  /// 19.5px 八分间距 = 原谱比例(10.92/19.8),不重叠。
  factory FlowingLayout.fromScore(
    ReferenceScore score, {
    required double pixelsPerSecond,
  }) {
    if (!(pixelsPerSecond > 0)) {
      throw ArgumentError.value(pixelsPerSecond, 'pixelsPerSecond', '必须为正');
    }
    final measureLeftX = List<double>.filled(score.measures.length, 0);
    final slopes = List<double>.filled(score.measures.length, 0);
    var cursor = 0.0;
    for (final m in score.measures) {
      final ticksPerSecond = 16.0 * m.tempo; // 960 tick/拍 × bpm/60
      slopes[m.index] = pixelsPerSecond; // px/秒(全曲匀速)
      measureLeftX[m.index] = cursor;
      final contentTicks = m.numerator * 3840 / m.denominator;
      cursor += contentTicks * (pixelsPerSecond / ticksPerSecond);
    }
    final last = score.measures.last;
    final anchorTimes = <double>[];
    final anchorXs = <double>[];
    for (final e in score.events) {
      final m = score.measures[e.measureIndex];
      anchorTimes.add(e.startSeconds);
      anchorXs.add(measureLeftX[e.measureIndex] +
          (e.startSeconds - m.startSeconds) * slopes[e.measureIndex]);
    }
    // 曲末锚点:时间 = 曲长,位置 = 末小节右缘。锚点时间严格递增,
    // positionAt 全曲斜率恒定(拍速变化处按比例,连续无跳变)。
    anchorTimes.add(score.durationSeconds);
    anchorXs.add(measureLeftX[last.index] +
        last.durationSeconds * slopes[last.index]);
    return FlowingLayout._(
      pixelsPerSecond,
      measureLeftX,
      slopes,
      anchorXs.last,
      anchorTimes,
      anchorXs,
    );
  }

  /// 每音乐秒的像素数(基准值;实际斜率逐小节见 [slopeOf])。
  final double pixelsPerSecond;

  /// 各小节小节线(左缘)的绝对 x。
  final List<double> measureLeftX;

  /// 各小节内的实际像素斜率(px/秒;密度地板会抬高低密基准)。
  final List<double> _slopes;

  /// 小节内的像素斜率(px/秒),画谱与测试共用单一来源。
  double slopeOf(int measureIndex) => _slopes[measureIndex];

  /// 曲末(终止线)绝对 x。
  final double endX;

  final List<double> _anchorTimes;
  final List<double> _anchorXs;

  /// 锚点序列(time 升序;测试与诊断用)。
  List<({double time, double x})> get anchors => [
        for (var i = 0; i < _anchorTimes.length; i++)
          (time: _anchorTimes[i], x: _anchorXs[i]),
      ];

  /// 音乐秒 → 绝对 x;相邻锚点间线性内插,两端钳制。
  double positionAt(double seconds) {
    var t = seconds;
    if (t.isNaN) return 0;
    if (t < _anchorTimes.first) t = _anchorTimes.first;
    if (t > _anchorTimes.last) t = _anchorTimes.last;
    // 最后一个 time <= t 的锚点(与移植源同款二分)。
    var low = 0;
    var high = _anchorTimes.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (_anchorTimes[mid] <= t) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    final ax = _anchorXs[low];
    if (low + 1 >= _anchorTimes.length) return ax;
    final bx = _anchorXs[low + 1];
    final span = _anchorTimes[low + 1] - _anchorTimes[low];
    if (span <= 0) return ax;
    return ax + (bx - ax) * (t - _anchorTimes[low]) / span;
  }
}

/// 一帧流水画面决策（codex flowing-timeline 的移植）：当前音乐时刻
/// 轮到谁（变色）、相机偏移、所在小节、是否曲末。
class FlowingFrame {
  const FlowingFrame({
    required this.seconds,
    required this.translateX,
    required this.event,
    required this.measureIndex,
    required this.noteIds,
    required this.finished,
  });

  final double seconds;

  /// 画面内容整体平移量：内容绝对 x + [translateX] 后，
  /// 当前时刻对应的谱面位置恰落在固定红线（cursorX）上。
  final double translateX;

  /// 当前正在响/停占位的事件（含休止）；间隙期（上一音已尽、下一音
  /// 未到）为 null——与移植源一致：变色只覆盖事件自身时长。
  final RefEvent? event;

  /// 最近一个（含越过）事件所在小节下标；尚无事件时 0。
  final int measureIndex;

  /// 当前事件的音 id 集合（变色查取）；无活动事件为空。
  final Set<int> noteIds;
  final bool finished;
}

/// 计算音乐时刻 [seconds] 的一帧。事件查取 = 二分「最后一个
/// startSeconds <= seconds」的事件；活动条件 = 事件自身时长内且未曲末。
FlowingFrame frameAt(
  ReferenceScore score,
  FlowingLayout layout,
  double seconds,
  double cursorX,
) {
  if (seconds.isNaN) {
    throw ArgumentError.value(seconds, 'seconds', '不能是 NaN');
  }
  final duration = score.durationSeconds;
  var clamped = seconds;
  if (clamped < 0) clamped = 0;
  if (clamped > duration) clamped = duration;
  final events = score.events;
  var low = 0;
  var high = events.length - 1;
  var index = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (events[mid].startSeconds <= clamped) {
      index = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  RefEvent? event;
  var noteIds = const <int>{};
  if (index >= 0) {
    final candidate = events[index];
    if (clamped < candidate.startSeconds + candidate.durationSeconds &&
        clamped < duration) {
      event = candidate;
      noteIds = {for (final n in candidate.notes) n.id};
    }
  }
  return FlowingFrame(
    seconds: clamped,
    translateX: cursorX - layout.positionAt(clamped),
    event: event,
    measureIndex: index >= 0 ? events[index].measureIndex : 0,
    noteIds: noteIds,
    finished: clamped >= duration,
  );
}

/// 把 MIDI 音高换算为频率(Hz),KS 拨弦音源与画面共用同一换算
/// (单一来源,近音高不碰撞由 PluckPlayer 键规则保证)。
double midiToFrequency(int midi) => 440.0 * math.pow(2, (midi - 69) / 12);

/// 音乐时刻所在小节下标(按「最后一个已越过的事件」定,与画面一致);
/// 尚无事件越过时 0。信息栏/测试用——与 [frameAt] 同一二分语义。
int measureIndexAt(ReferenceScore score, double seconds) {
  final events = score.events;
  var low = 0;
  var high = events.length - 1;
  var index = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (events[mid].startSeconds <= seconds) {
      index = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return index >= 0 ? events[index].measureIndex : 0;
}
