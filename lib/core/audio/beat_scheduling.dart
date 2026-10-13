import 'dart:math' as math;

/// 单拍预定结果:拍序号与其引擎时刻。
typedef ScheduledBeat = (int beat, Duration time);

/// 每小节拍数。本工单固定 4/4(工单领域常量,强弱拍映射与视觉共用)。
const int beatsPerBar = 4;

/// 公共缝校验(BPM/变速比/拍周期):[value] 必须为有限正值,非法抛
/// [ArgumentError](release 也生效,不靠 assert)。全部调参缝共用同一
/// 谓词,[$name] 供错误定位,[$subject] 是面向人的主语。
void requirePositiveFinite(double value, String name, String subject) {
  if (value.isNaN || value <= 0 || value.isInfinite) {
    throw ArgumentError.value(value, name, '$subject必须为有限正值');
  }
}

/// 有效拍长(毫秒,四分)= 60000/BPM/变速比:BPM 与变速比的公共缝校验
/// (非正/非有限抛 [ArgumentError],release 也生效)与拍周期换算的单一
/// 来源。compileTimeline(弹唱)与 compileTabTimeline(指弹,工单 12)
/// 共用——两谱模型各自独立(ADR-0003),数值缝只此一处。
double effectivePeriodMs({required double bpm, required double speed}) {
  requirePositiveFinite(bpm, 'bpm', 'BPM');
  requirePositiveFinite(speed, 'speed', '变速比(产品范围 50%–100%)');
  final periodMs = 60000 / bpm / speed;
  if (periodMs.isInfinite) {
    throw ArgumentError.value(periodMs, 'periodMs', '有效拍长非有限(BPM×变速比过小)');
  }
  return periodMs;
}

/// 节拍时间轴的不可变状态:锚点 [t0]、首个未预定拍 [nextBeat]、拍周期
/// [periodMs](毫秒,= 60000/bpm)、可选总拍数 [totalBeats](null = 连续)。
///
/// 一切决策都是纯函数,只认调用方传入的引擎时刻(ADR-0005:禁止挂钟)。
/// 拍时刻定义:t0 + round(beat × periodMs) 毫秒(逐拍直接四舍五入,
/// 不累加误差——spike B 同语义)。
class BeatSchedule {
  /// [periodMs] 必须为有限正值(公共缝校验,release 也生效):非正会使
  /// [scheduleDue] 死循环/倒走,非有限值让时刻计算抛错。
  BeatSchedule({
    required this.t0,
    required this.nextBeat,
    required this.periodMs,
    this.totalBeats,
  }) {
    requirePositiveFinite(periodMs, 'periodMs', '拍周期');
  }

  /// 提前量窗口:窗口内的拍现在预定。spike B 真机验证参数。
  static const defaultLookahead = Duration(milliseconds: 400);

  /// 迟到容差:过期不超过该值的拍仍照响(覆盖轮询迟滞与启拍亚毫秒
  /// 漂移);再迟的过期拍越过不回放——追赶必须有界,否则迟滞轮询后
  /// 过期拍连发成机关枪。缺省与 BeatScheduler.pollInterval 同为 40ms
  /// (spike B);调度器显式传自己的轮询周期,生产路径不受此缺省影响,
  /// 改轮询周期时此处仅纯函数直调方跟随。
  static const defaultMaxLate = Duration(milliseconds: 40);

  final Duration t0;
  final int nextBeat;
  final double periodMs;
  final int? totalBeats;

  /// 第 [beat] 拍的引擎时刻。
  Duration beatTime(int beat) =>
      t0 + Duration(milliseconds: (beat * periodMs).round());

  /// 调度窗口决策:给出引擎时刻 [now],返回窗口 [now − maxLate,
  /// now + lookahead] 内尚未预定的拍,以及推进后的新状态。已预定拍绝不
  /// 重复;晚于 [maxLate] 的过期拍**跳过不回放**(nextBeat 直接越过,
  /// 不回头)——有界迟到策略:超容差的拍放弃,迟滞轮询不产生机关枪式
  /// 补响,网格时刻不受追赶扰动。
  (BeatSchedule, List<ScheduledBeat>) scheduleDue({
    required Duration now,
    Duration lookahead = defaultLookahead,
    Duration maxLate = defaultMaxLate,
  }) {
    final from = now - maxLate;
    final limit = now + lookahead;
    final due = <ScheduledBeat>[];
    var next = nextBeat;
    var time = beatTime(next);
    while ((totalBeats == null || next < totalBeats!) && time <= limit) {
      if (time >= from) due.add((next, time));
      next++;
      time = beatTime(next);
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
  /// 本纯函数只管网格连续:新网格保证首个未预定拍落在 now + 剩余相位 ×
  /// 新周期 处,elapsed(已逝拍数,含相位)在旧新网格间连续,听感
  /// "同一拍内平滑变速"。调度态感知(已排队未响拍的取消与重排)在
  /// [BeatScheduler.changePeriod]:它把 nextBeat 回拨到最早被取消的拍号,
  /// 交还正常过窗按新网格重排——大跨度变速不重排会新旧拍倒挂。
  BeatSchedule reanchored(Duration now, double newPeriodMs) {
    // 入口校验先于一切:构造器也会拦,但下方 t0 表达式先求值,非有限
    // 周期会先在 round() 炸出 UnsupportedError 而非 ArgumentError。
    requirePositiveFinite(newPeriodMs, 'newPeriodMs', '拍周期');
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

  /// 拷贝并改写首个未预定拍(变速重排回拨用),其余字段不变。
  BeatSchedule withNextBeat(int nextBeat) => BeatSchedule(
    t0: t0,
    nextBeat: nextBeat,
    periodMs: periodMs,
    totalBeats: totalBeats,
  );
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
  final elapsed = now - t0;
  if (elapsed < Duration.zero) return null;
  final index = _beatIndexAt(elapsed, periodMs);
  final beatInBar = index % beatsPerBar;
  return (index, beatInBar, beatInBar == 0);
}

/// 当前拍序号 = 最大的 b 使 round(b × periodMs) ≤ elapsed 毫秒——与
/// [BeatSchedule.beatTime] 同一取整边界:拍声预定在 round(b×periodMs),
/// 视觉在同一毫秒翻转,声画同刻(跟练条带跨小节不再有亚毫秒空白帧)。
/// 先按连续网格估算,再对取整边界 ±1 修正(|round(b·p)−b·p| ≤ 0.5ms,
/// 估算至多偏一拍;对 ≥1ms 的现实拍周期可证充分,<0.5ms 即 >120000 BPM
/// 的极端域取整平台期会滞留一拍,产品域不可达)。
int _beatIndexAt(Duration elapsed, double periodMs) {
  requirePositiveFinite(periodMs, 'periodMs', '拍周期');
  final e = elapsed.inMilliseconds;
  var index = (e / periodMs).floor();
  if (((index + 1) * periodMs).round() <= e) {
    index++;
  } else if (index > 0 && (index * periodMs).round() > e) {
    index--;
  }
  return index;
}
