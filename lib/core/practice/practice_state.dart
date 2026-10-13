/// 跟练的练习状态（GLOSSARY「跟练」）：(动作事件时间轴, 引擎时刻) → 此刻状态。
///
/// UI 以 ~16ms 轮询本函数重绘（spike B 已验证），是练习状态的唯一来源：
/// 当前拍与 core/audio `beatAt` 同一取整语义（节拍声/拍视觉逐拍对齐），
/// 当前动作/行/段落按二分查找定位（架构约定），预告取 (now, now+窗口]
/// 时间窗。一切时刻只认调用方传入的引擎时刻（ADR-0005），本文件无时钟。
///
/// 纯函数、零引擎依赖（spec 测试接缝一），标准 flutter test 覆盖。
library;

import '../audio/beat_scheduling.dart';
import 'play_timeline.dart';

/// 视觉预告窗的缺省宽度。量级是「肉眼提前读谱」；音频预定提前量
/// （400ms）是 BeatSchedule 的事，两窗各管各的，工单 10 的俄罗斯方块
/// 预告可传自己的窗口。
const Duration defaultPreviewWindow = Duration(seconds: 2);

/// 引擎时刻 [now] 处的跟练练习状态。
class PracticeState {
  const PracticeState({
    required this.beat,
    required this.beatInBar,
    required this.isStrongBeat,
    required this.currentStrum,
    required this.upcomingStrums,
    required this.currentLine,
    required this.currentSection,
  });

  /// 全曲拍序号（自 0，随节拍网格连续推进）。
  final int beat;

  /// 小节内拍（0..3）。
  final int beatInBar;

  /// 是否强拍（每小节第 1 拍）。
  final bool isStrongBeat;

  /// 当前扫弦动作＝最后一个时刻 ≤ now 的扫弦事件；持稳到下一动作，
  /// 空拍槽不翻转（手照摆不触弦）。曲首还没有任何动作时为 null。
  final PlayStrumEvent? currentStrum;

  /// 预告窗口 (now, now+previewWindow] 内的扫弦动作，按时刻升序、
  /// 已完成的绝不回流。当前动作不在其中。
  final List<PlayStrumEvent> upcomingStrums;

  /// 当前高亮歌词行＝最后一个时刻 ≤ now 的歌词行事件；null 同上。
  final PlayLyricEvent? currentLine;

  /// 当前段落＝最后一个时刻 ≤ now 的段落事件；null 同上。
  final PlaySectionEvent? currentSection;
}

/// 引擎时刻 [now] → 跟练练习状态。
///
/// [now] 早于 [t0]（预备期）返回 null；节拍网格走出最后一拍（beat ≥
/// [PlayTimeline.totalBeats]）即曲末，返回 null——曲末边界认网格：beatAt
/// 与 [BeatSchedule.beatTime] 同一取整边界后，拍 totalBeats 的翻转时刻
/// 恰等于名义曲长 [PlayTimeline.totalDuration]（同为 round(totalBeats ×
/// periodMs)），富余窗归末拍，杜绝 beat == totalBeats 的幻拍。空时间轴
/// 恒为 null。
PracticeState? practiceStateAt({
  required PlayTimeline timeline,
  required Duration t0,
  required Duration now,
  Duration previewWindow = defaultPreviewWindow,
}) {
  final elapsed = now - t0;
  if (elapsed < Duration.zero) return null;

  // 当前拍：直接复用节拍器的视觉拍函数，保证跟练与节拍器逐拍同语义。
  final (beat, beatInBar, isStrongBeat) =
      beatAt(now: now, t0: t0, periodMs: timeline.periodMs)!;
  if (beat >= timeline.totalBeats) return null; // 曲末（见函数注释）

  final strums = timeline.strums;
  final lastStrum = _lastAtOrBefore(strums, elapsed);
  return PracticeState(
    beat: beat,
    beatInBar: beatInBar,
    isStrongBeat: isStrongBeat,
    currentStrum: lastStrum < 0 ? null : strums[lastStrum],
    upcomingStrums: List.unmodifiable([
      for (var i = lastStrum + 1;
          i < strums.length && strums[i].time <= elapsed + previewWindow;
          i++)
        strums[i],
    ]),
    currentLine: _current(timeline.lyrics, elapsed),
    currentSection: _current(timeline.sections, elapsed),
  );
}

/// 预备数拍状态（工单 10）：预备期还剩几拍（4..1 倒计）。
class PrepState {
  const PrepState({required this.count});

  /// 剩余预备拍数（自 [prepBeats] 倒数到 1）。
  final int count;
}

/// 引擎时刻 [now] → 预备数拍状态。预备窗为 [t0Prep, t0Prep +
/// prepBeats×periodMs)（节拍网格的前 prepBeats 拍）：窗内返回剩余倒计
/// （第 k 预备拍倒数 prepBeats−k），曲头起（第 prepBeats 拍边界含富余窗）
/// 预备已结束返回 null；[t0Prep] 之前（产品不可达，纯函数自守）同样
/// null。
///
/// 锚必须是**预备第 0 拍**（调度器网格原点 t0，无取整），不能是「曲头 =
/// t0 + round(prepBeats×periodMs)」——取整后的曲头反推剩余拍会出
/// ±1 拍误差（208BPM：4×288.46 取整 1154，0 时刻剩余 4.0005 拍，
/// ceil 炸成 5 被误判窗外）。取整语义与 beatAt 同族：拍内 floor。
PrepState? prepStateAt({
  required Duration now,
  required Duration t0Prep,
  required double periodMs,
  int prepBeats = 4,
}) {
  requirePositiveFinite(periodMs, 'periodMs', '拍周期');
  final elapsedUs = (now - t0Prep).inMicroseconds;
  if (elapsedUs < 0) return null;
  final beat = elapsedUs / (periodMs * 1000);
  if (beat >= prepBeats) return null;
  return PrepState(count: prepBeats - beat.floor());
}

/// 时刻 ≤ [time] 的最后一个事件的通用取用（二分查找已定位，直接取）。
T? _current<T extends PlayEvent>(List<T> events, Duration time) {
  final i = _lastAtOrBefore(events, time);
  return i < 0 ? null : events[i];
}

/// 升序事件列表里最后一个 time ≤ [time] 的下标；无则 -1。二分查找。
int _lastAtOrBefore<T extends PlayEvent>(List<T> events, Duration time) {
  var low = 0;
  var high = events.length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (events[mid].time <= time) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low - 1;
}
