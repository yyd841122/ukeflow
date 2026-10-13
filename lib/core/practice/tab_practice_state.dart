/// 逐音练习状态(GLOSSARY「练习状态」的指弹对应物):(逐音事件时间轴,
/// 引擎时刻) → 此刻状态。UI 以 ~16ms 轮询本函数重绘,是逐音跟练视图的
/// 唯一数据源:当前拍与 core/audio `beatAt` 同一取整语义(预备数拍与
/// 拍视觉逐拍对齐),当前音/预告按事件时刻定位——时刻是编译进时间轴的
/// 相对量(与示范声预定同一毫秒),高亮与示范声同刻是结构保证(工单 13)。
///
/// 纯函数、零引擎依赖,标准 flutter test 覆盖,本文件无任何时钟。
/// 与弹唱的 practice_state.dart 同纪律、不同事件族(ADR-0003:两谱
/// 模型不统一,本文件不 import 弹唱谱的任何类型)。
library;

import '../audio/beat_scheduling.dart';
import 'tab_timeline.dart';

/// 逐音预亮窗的缺省宽度(「左手可提前移动」的量级)。与弹唱预告窗
/// (practice_state 的 defaultPreviewWindow)各是各的产品决策,数值
/// 相同不互相引用。
const Duration tabPreviewWindow = Duration(seconds: 2);

/// 引擎时刻 [now] 处的逐音练习状态。
class TabPracticeState {
  const TabPracticeState({
    required this.beat,
    required this.beatInBar,
    required this.isStrongBeat,
    required this.currentNoteIndex,
    required this.upcomingNoteIndexes,
  });

  /// 全曲拍序号(自 0,随节拍网格连续推进)。
  final int beat;

  /// 小节内拍(0..3)。
  final int beatInBar;

  /// 是否强拍(每小节第 1 拍)。
  final bool isStrongBeat;

  /// 当前音 = 最后一个时刻 ≤ now 的音事件在 [TabTimeline.notes] 里的
  /// 下标;持稳到下一音(长音不闪断),曲首还没有任何音时为 -1。
  /// 下标与四线谱布局 TabChartLayout.notes 同序(同为 sortedTabNotes 序)。
  final int currentNoteIndex;

  /// 预亮窗 (now, now+tabPreviewWindow] 内的音事件下标,升序连续;
  /// 当前音不在其中,已响的绝不回流。
  final List<int> upcomingNoteIndexes;
}

/// 引擎时刻 [now] → 逐音练习状态。
///
/// [now] 早于 [t0](预备期)返回 null;节拍网格走出最后一拍(beat ≥
/// [TabTimeline.totalBeats])即曲末,返回 null——曲末边界认网格,与
/// 弹唱 practiceStateAt 同界:拍 totalBeats 的翻转时刻恰等于名义曲长。
/// 空时间轴(全曲 0 拍)恒为 null。
TabPracticeState? tabPracticeStateAt({
  required TabTimeline timeline,
  required Duration t0,
  required Duration now,
  Duration previewWindow = tabPreviewWindow,
}) {
  final elapsed = now - t0;
  if (elapsed < Duration.zero) return null;

  // 当前拍:直接复用节拍器的视觉拍函数,保证逐音跟练与节拍器逐拍同语义。
  final (beat, beatInBar, isStrongBeat) = beatAt(
    now: now,
    t0: t0,
    periodMs: timeline.periodMs,
  )!;
  if (beat >= timeline.totalBeats) return null; // 曲末(见函数注释)

  final notes = timeline.notes;
  final current = _lastAtOrBefore(notes, elapsed);
  final until = elapsed + previewWindow;
  return TabPracticeState(
    beat: beat,
    beatInBar: beatInBar,
    isStrongBeat: isStrongBeat,
    currentNoteIndex: current,
    upcomingNoteIndexes: List.unmodifiable([
      for (var i = current + 1; i < notes.length && notes[i].time <= until; i++)
        i,
    ]),
  );
}

/// 升序事件列表里最后一个 time ≤ [time] 的下标;无则 -1。二分查找。
int _lastAtOrBefore(List<TabNoteEvent> events, Duration time) {
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
