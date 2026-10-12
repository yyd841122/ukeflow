import 'dart:math' as math;

/// 单拍预定结果:拍序号与其引擎时刻。
typedef ScheduledBeat = (int beat, Duration time);

/// 每小节拍数。本工单固定 4/4(工单领域常量,强弱拍映射与视觉共用)。
const int beatsPerBar = 4;

/// 节拍时间轴的不可变状态:锚点 [t0]、首个未预定拍 [nextBeat]、拍周期
/// [periodMs](毫秒,= 60000/bpm)、可选总拍数 [totalBeats](null = 连续)。
///
/// 一切决策都是纯函数,只认调用方传入的引擎时刻(ADR-0005:禁止挂钟)。
/// 拍时刻定义:t0 + round(beat × periodMs) 毫秒(逐拍直接四舍五入,
/// 不累加误差——spike B 同语义)。
class BeatSchedule {
  const BeatSchedule({
    required this.t0,
    required this.nextBeat,
    required this.periodMs,
    this.totalBeats,
  });

  /// 提前量窗口:窗口内的拍现在预定。spike B 真机验证参数。
  static const defaultLookahead = Duration(milliseconds: 400);

  final Duration t0;
  final int nextBeat;
  final double periodMs;
  final int? totalBeats;

  /// 第 [beat] 拍的引擎时刻。
  Duration beatTime(int beat) =>
      t0 + Duration(milliseconds: (beat * periodMs).round());

  /// 调度窗口决策:给出引擎时刻 [now],返回窗口 [now, now+lookahead] 内
  /// 尚未预定的拍,以及推进后的新状态。已预定拍绝不重复。
  (BeatSchedule, List<ScheduledBeat>) scheduleDue({
    required Duration now,
    Duration lookahead = defaultLookahead,
  }) {
    final limit = now + lookahead;
    final due = <ScheduledBeat>[];
    var next = nextBeat;
    while ((totalBeats == null || next < totalBeats!) &&
        beatTime(next) <= limit) {
      due.add((next, beatTime(next)));
      next++;
    }
    return (
      BeatSchedule(
        t0: t0,
        nextBeat: next,
        periodMs: periodMs,
        totalBeats: totalBeats,
      ),
      due,
    );
  }

  /// 运行中换 BPM 即时生效:保持拍内相位重锚定时间轴。
  ///
  /// 已预定拍(nextBeat 之前)不重排——它们已交给引擎,重排必然错乱;
  /// 新网格保证首个未预定拍落在 now + 剩余相位 × 新周期 处:
  /// elapsed(已逝拍数,含相位)在旧新网格间连续,听感"同一拍内平滑变速"。
  BeatSchedule reanchored(Duration now, double newPeriodMs) {
    final elapsedBeats = (now - t0).inMicroseconds / (periodMs * 1000);
    // 守卫:尚无任何拍预定时不跳拍(正常运行 start 即过窗,不可达此分支)。
    final newNextBeat = nextBeat == 0
        ? 0
        : math.max(nextBeat, elapsedBeats.floor() + 1);
    return BeatSchedule(
      t0: now - Duration(milliseconds: (elapsedBeats * newPeriodMs).round()),
      nextBeat: newNextBeat,
      periodMs: newPeriodMs,
      totalBeats: totalBeats,
    );
  }
}

/// 视觉拍状态:拍序号、小节内位置(0..3)、是否强拍。
typedef BeatVisual = (int beatIndex, int beatInBar, bool isStrong);

/// 引擎时刻 → 节拍视觉状态的纯函数(UI 轮询薄渲染用,ADR-0005)。
/// [now] 早于 [t0](预备期)返回 null。
BeatVisual? beatAt({
  required Duration now,
  required Duration t0,
  required double periodMs,
  int beatsPerBar = beatsPerBar,
}) {
  final elapsedMs = (now - t0).inMicroseconds / 1000;
  if (elapsedMs < 0) return null;
  final index = (elapsedMs / periodMs).floor();
  final beatInBar = index % beatsPerBar;
  return (index, beatInBar, beatInBar == 0);
}
