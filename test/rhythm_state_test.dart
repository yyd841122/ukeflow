import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/beat_scheduling.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';
import 'package:ukeflow/core/model/strum_pattern.dart';
import 'package:ukeflow/core/practice/rhythm_state.dart';

/// 节奏训练练习状态纯函数(工单 08 练习状态函数的最小先行版):
/// (网格, 引擎时刻)→状态,时间源一律是调用方传入的引擎时刻(ADR-0005)。
void main() {
  const pattern = StrumPattern(
    id: 't',
    name: '下 下上 上下上',
    slots: [
      StrumDirection.down,
      null,
      StrumDirection.down,
      StrumDirection.up,
      null,
      StrumDirection.up,
      StrumDirection.down,
      StrumDirection.up,
    ],
  );

  final t0 = const Duration(milliseconds: 1234); // 非零锚点,防偶然对齐
  // 120 BPM:一拍 500ms,一槽(八分)250ms,一小节 2000ms。
  const periodMs = 500.0;
  Duration at(int ms) => t0 + Duration(milliseconds: ms);

  test('t0 之前(预备期)返回 null(语义同 beatAt)', () {
    expect(rhythmPracticeAt(now: t0 - const Duration(milliseconds: 1), t0: t0, periodMs: periodMs, pattern: pattern), isNull);
  });

  test('t0 恰好落槽 0:小节 0、拍 1(强拍)、下扫', () {
    final state = rhythmPracticeAt(now: t0, t0: t0, periodMs: periodMs, pattern: pattern)!;
    expect(state.barIndex, 0);
    expect(state.slotInBar, 0);
    expect(state.beatInBar, 0);
    expect(state.isStrongBeat, isTrue);
    expect(state.stroke, StrumDirection.down);
  });

  test('半拍推进逐槽走,空拍槽 stroke 为 null', () {
    // 250ms = 槽 1(空拍);375ms 仍槽 1;500ms = 槽 2。
    final slot1 = rhythmPracticeAt(now: at(250), t0: t0, periodMs: periodMs, pattern: pattern)!;
    expect(slot1.slotInBar, 1);
    expect(slot1.stroke, isNull, reason: '槽 1 是空拍');
    expect(slot1.beatInBar, 0, reason: '槽 1 仍在拍 1 内');

    final midSlot1 = rhythmPracticeAt(now: at(374), t0: t0, periodMs: periodMs, pattern: pattern)!;
    expect(midSlot1.slotInBar, 1);

    final slot2 = rhythmPracticeAt(now: at(500), t0: t0, periodMs: periodMs, pattern: pattern)!;
    expect(slot2.slotInBar, 2);
    expect(slot2.stroke, StrumDirection.down);
    expect(slot2.beatInBar, 1);
    expect(slot2.isStrongBeat, isFalse);
  });

  test('拍 3 空过(槽 4)与 3& 上扫(槽 5):岛国节奏型的时值骨架', () {
    final slot4 = rhythmPracticeAt(now: at(1000), t0: t0, periodMs: periodMs, pattern: pattern)!;
    expect(slot4.slotInBar, 4);
    expect(slot4.stroke, isNull);
    expect(slot4.beatInBar, 2);

    final slot5 = rhythmPracticeAt(now: at(1250), t0: t0, periodMs: periodMs, pattern: pattern)!;
    expect(slot5.slotInBar, 5);
    expect(slot5.stroke, StrumDirection.up);
  });

  test('跨小节循环:槽位取模,小节号累计', () {
    // 2000ms = 第 2 小节槽 0;2500ms = 第 2 小节槽 2;第 3 小节拍 3。
    final bar2 = rhythmPracticeAt(now: at(2000), t0: t0, periodMs: periodMs, pattern: pattern)!;
    expect(bar2.barIndex, 1);
    expect(bar2.slotInBar, 0);
    expect(bar2.isStrongBeat, isTrue);

    // 7750ms = 全局槽 31 = 第 3 小节(自 0)槽 7 = 第 4 拍后半。
    final bar3beat4 = rhythmPracticeAt(now: at(7750), t0: t0, periodMs: periodMs, pattern: pattern)!;
    expect(bar3beat4.barIndex, 3);
    expect(bar3beat4.slotInBar, 7);
    expect(bar3beat4.beatInBar, 3);
  });

  test('慢速 40 BPM:网格随 periodMs 伸缩(慢练验收的机制面)', () {
    // 40 BPM:一拍 1500ms,一槽 750ms;700ms 仍槽 0,750ms 进槽 1。
    const slow = 60000 / 40;
    expect(rhythmPracticeAt(now: at(700), t0: t0, periodMs: slow, pattern: pattern)!.slotInBar, 0);
    expect(rhythmPracticeAt(now: at(750), t0: t0, periodMs: slow, pattern: pattern)!.slotInBar, 1);
  });

  test('与 beatAt 同拍对齐:同一时刻拍归属一致(音画同步的接缝保证)', () {
    final island = builtinStrumPatterns.last;
    // 整倍周期(120)+奇 BPM(61,periodMs/2 非二进制精确)都须对齐。
    for (final periodMs in [500.0, 60000 / 61]) {
      for (var ms = 0; ms <= 10000; ms += 37) {
        final now = at(ms);
        final visual = beatAt(now: now, t0: t0, periodMs: periodMs)!;
        final state = rhythmPracticeAt(now: now, t0: t0, periodMs: periodMs, pattern: island)!;
        expect(state.beatInBar, visual.$2, reason: '$ms 处拍归属应与节拍器视觉一致');
        expect(state.isStrongBeat, visual.$3, reason: '$ms 处强弱应与节拍器视觉一致');
        expect(state.stroke, island.slots[state.slotInBar]);
      }
    }
  });
}
