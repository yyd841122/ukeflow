/// 节奏型训练的练习状态（工单 08 练习状态函数的最小先行版）。
///
/// 与工单 08 的练习状态同构：都是「(时间网格, 引擎时刻) → 此刻状态」
/// 的纯函数，只是网格从"编译出的动作事件时间轴"简化为"循环八分网格"。
/// 一切时刻只认调用方传入的引擎时刻（ADR-0005），本文件无任何时钟。
library;

import '../audio/beat_scheduling.dart';
import '../model/strum_pattern.dart';

/// 一小节内的一个八分槽位上，节奏训练所处的全部状态。
class RhythmPracticeState {
  const RhythmPracticeState({
    required this.barIndex,
    required this.slotInBar,
    required this.beatInBar,
    required this.isStrongBeat,
    required this.stroke,
  });

  /// 小节序号（自 0，随循环累计）。
  final int barIndex;

  /// 小节内八分槽位（0..7）。
  final int slotInBar;

  /// 小节内拍（0..3，= slotInBar ~/ 2）。
  final int beatInBar;

  /// 是否强拍（每小节第 1 拍）。
  final bool isStrongBeat;

  /// 本槽扫弦动作；null = 空拍（手照摆、不触弦）。
  final StrumDirection? stroke;
}

/// 引擎时刻 [now] → 节奏训练状态；[periodMs] 为一拍（四分）毫秒数，
/// 槽周期即其半。槽位换算与 `beatAt`（core/audio）同一套取整语义，
/// 保证箭头网格与节拍声逐拍对齐。[now] 早于 [t0]（预备期）返回 null。
RhythmPracticeState? rhythmPracticeAt({
  required Duration now,
  required Duration t0,
  required double periodMs,
  required StrumPattern pattern,
}) {
  // 槽位经 beatAt 在**半拍周期**上取整派生(审计 2026-10-16 #20):连续
  // 网格 floor 与拍声的取整网格在非整除 BPM 下错亚毫秒(61BPM 拍界
  // round(2×983.6)=1967ms vs 槽界 2×983.6=1967.2ms),箭头翻页与节拍
  // 声不同毫秒——同一取整语义逐拍对齐;round(2k×p/2)=round(k×p),拍界
  // 与 beatAt 严格同刻。
  final slotVisual = beatAt(
    now: now,
    t0: t0,
    periodMs: periodMs / 2,
  );
  if (slotVisual == null) return null; // 预备期(now < t0)。
  final (globalSlot, _, _) = slotVisual;
  final slotInBar = globalSlot % eighthsPerBar;
  final beatInBar = slotInBar ~/ 2;
  return RhythmPracticeState(
    barIndex: globalSlot ~/ eighthsPerBar,
    slotInBar: slotInBar,
    beatInBar: beatInBar,
    isStrongBeat: beatInBar == 0,
    stroke: pattern.slots[slotInBar],
  );
}
