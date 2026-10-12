import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/beat_scheduling.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';
import 'package:ukeflow/core/model/strum_pattern.dart';
import 'package:ukeflow/core/practice/play_timeline.dart';
import 'package:ukeflow/core/practice/practice_state.dart';

import 'helpers/chart_fixtures.dart';

/// 工单 08 接缝二：(动作事件时间轴, 引擎时刻) → 练习状态。
/// 期望值一律手算字面量；时间源只有调用方传入的引擎时刻（ADR-0005）。
void main() {
  // 五小节 fixtures：主歌 2 行（C / Am）+ 副歌 2 行（F / G,C），@120BPM：
  // 小节 0=C、1=Am、2=F、3=G、4=C；每小节全下扫落在 bar×2000+{0,500,1000,1500}ms。
  const fiveBarChart = '{start_of_verse}\n[C]啦\n[Am]啦啦\n{end_of_verse}\n'
      '{start_of_chorus: 副歌}\n[F]啦\n[G]啦啦 [C]啦啦\n{end_of_chorus}\n';

  final t0 = const Duration(milliseconds: 1234); // 非零锚点，防偶然对齐
  Duration at(int ms) => t0 + Duration(milliseconds: ms);

  /// 五小节 @120BPM 全下扫时间轴：曲长 10000ms。
  PlayTimeline fiveBars() => compileTimeline(
        chart: parseChart(fiveBarChart),
        pattern: builtinStrumPatterns.first,
        bpm: 120,
      );

  test('t0 之前（预备期）与曲末之后（≥t0+曲长）返回 null', () {
    final timeline = fiveBars();
    expect(
      practiceStateAt(
        timeline: timeline,
        t0: t0,
        now: t0 - const Duration(milliseconds: 1),
      ),
      isNull,
    );
    // 曲长 10000ms：恰在曲末即出界（半开区间），曲末前 1ms 仍在曲内。
    expect(practiceStateAt(timeline: timeline, t0: t0, now: at(10000)), isNull);
    expect(
      practiceStateAt(timeline: timeline, t0: t0, now: at(9999)),
      isNotNull,
    );
  });

  test('空时间轴任意时刻都是 null', () {
    final empty = compileTimeline(
      chart: parseChart('{title: 空谱}\n'),
      pattern: builtinStrumPatterns.first,
      bpm: 120,
    );
    expect(practiceStateAt(timeline: empty, t0: t0, now: at(0)), isNull);
    expect(practiceStateAt(timeline: empty, t0: t0, now: at(5000)), isNull);
  });

  test('t0 时刻：第 0 拍强拍，当前动作/行/段落全部就位', () {
    final timeline = fiveBars();
    final state = practiceStateAt(timeline: timeline, t0: t0, now: t0)!;

    expect(state.beat, 0);
    expect(state.beatInBar, 0);
    expect(state.isStrongBeat, isTrue);
    expect(state.currentStrum!.time, Duration.zero);
    expect(state.currentStrum!.chord, 'C');
    expect(state.currentStrum!.slotInBar, 0);
    expect(identical(state.currentLine, timeline.lyrics.first), isTrue);
    expect(identical(state.currentSection, timeline.sections.first), isTrue);
  });

  test('当前动作在事件时刻翻转、持稳到下一动作（事件边界精确）', () {
    final timeline = fiveBars();
    int currentMs(Duration now) =>
        practiceStateAt(timeline: timeline, t0: t0, now: now)!
            .currentStrum!
            .time
            .inMilliseconds;

    expect(currentMs(at(499)), 0, reason: '事件时刻前 1ms 仍是上一动作');
    expect(currentMs(at(500)), 500, reason: '恰在事件时刻翻转');
    expect(currentMs(at(1500)), 1500);
    expect(currentMs(at(1999)), 1500, reason: '小节末持稳在本小节最后一扫');

    // 岛国型：拍 3 空过（槽 4 无事件），当前动作持稳在槽 3 的 750ms。
    final island = compileTimeline(
      chart: parseChart('{start_of_verse}\n[C]啦\n{end_of_verse}\n'),
      pattern: builtinStrumPatterns.last,
      bpm: 120,
    );
    int islandMs(Duration now) =>
        practiceStateAt(timeline: island, t0: t0, now: now)!
            .currentStrum!
            .time
            .inMilliseconds;
    expect(islandMs(at(999)), 750);
    expect(islandMs(at(1000)), 750, reason: '空拍槽没有动作事件，当前动作不翻转');
    expect(islandMs(at(1249)), 750);
    expect(islandMs(at(1250)), 1250);
  });

  test('行与段落随节拍切换，拍号跨小节累计', () {
    final timeline = fiveBars();

    PracticeState stateAt(int ms) =>
        practiceStateAt(timeline: timeline, t0: t0, now: at(ms))!;

    var state = stateAt(1999);
    expect(state.beat, 3);
    expect(identical(state.currentLine, timeline.lyrics[0]), isTrue);
    expect(identical(state.currentSection, timeline.sections[0]), isTrue);

    state = stateAt(2000); // 第 2 小节起：主歌第 2 行（Am）。
    expect(state.beat, 4);
    expect(state.isStrongBeat, isTrue);
    expect(identical(state.currentLine, timeline.lyrics[1]), isTrue);

    state = stateAt(4000); // 第 3 小节起：副歌开场。
    expect(identical(state.currentSection, timeline.sections[1]), isTrue);
    expect(state.currentSection!.section.label, '副歌');
    expect(identical(state.currentLine, timeline.lyrics[2]), isTrue);

    state = stateAt(3999);
    expect(identical(state.currentSection, timeline.sections[0]), isTrue,
        reason: '段落切换前 1ms 仍是主歌');
  });

  test('预告窗口 (now, now+窗口]：按序、去已完成、含右端点', () {
    final timeline = fiveBars();

    List<int> previewMs(int ms, Duration window) => practiceStateAt(
          timeline: timeline,
          t0: t0,
          now: at(ms),
          previewWindow: window,
        )!
            .upcomingStrums
            .map((e) => e.time.inMilliseconds)
            .toList();

    // t0+100 起 1s 内：(100, 1100] → 500、1000；按时刻升序。
    expect(previewMs(100, const Duration(milliseconds: 1000)), [500, 1000]);
    // 恰在 now 的动作不算预告（它是当前动作）；恰在 now+窗口 的算预告。
    expect(previewMs(0, const Duration(milliseconds: 1000)), [500, 1000]);
    // 已扫过的不回流：600 起只剩 1000、1500。
    expect(previewMs(600, const Duration(milliseconds: 1000)), [1000, 1500]);
    // 窗口随参数伸缩：500ms 窗口在 600 处只看到 1000。
    expect(previewMs(600, const Duration(milliseconds: 500)), [1000]);
    // 曲末附近窗口走空。
    expect(previewMs(9600, const Duration(milliseconds: 1000)), isEmpty);
    // 预告携带后续和弦（换和弦提前量靠它）。
    final preview = practiceStateAt(
      timeline: timeline,
      t0: t0,
      now: at(1600),
      previewWindow: const Duration(milliseconds: 1000),
    )!;
    expect(preview.upcomingStrums.map((e) => e.chord), everyElement('Am'));
  });

  test('无任何扫弦的节奏型：拍照走、动作为 null，不崩', () {
    final silent = compileTimeline(
      chart: parseChart('{start_of_verse}\n[C]啦\n{end_of_verse}\n'),
      pattern: const StrumPattern(
        id: 'rest',
        name: '全空拍',
        slots: [null, null, null, null, null, null, null, null],
      ),
      bpm: 120,
    );
    expect(practiceStateAt(timeline: silent, t0: t0, now: at(400))!.beatInBar, 0,
        reason: '400ms 仍在第 1 拍（0 起）');
    final state = practiceStateAt(timeline: silent, t0: t0, now: at(700))!;
    expect(state.currentStrum, isNull);
    expect(state.upcomingStrums, isEmpty);
    expect(state.beatInBar, 1, reason: '700ms 已入第 2 拍（500ms 起拍）');
    expect(identical(state.currentLine, silent.lyrics.single), isTrue);
  });

  test('曲末四舍五入富余窗内不出现幻拍（拍号走出最后一拍即曲末）', () {
    // BPM 61 两小节：第 8 拍网格起点 7868.85ms，名义曲长四舍五入为 7869ms；
    // [7868.85, 7869) 的亚毫秒富余窗内不得给出 beat=8 的状态。
    final timeline = compileTimeline(
      chart: parseChart('{start_of_verse}\n[C]啦 [G]啦\n{end_of_verse}\n'),
      pattern: builtinStrumPatterns.first,
      bpm: 61,
    );
    expect(timeline.totalBeats, 8);
    expect(
      practiceStateAt(
        timeline: timeline,
        t0: t0,
        now: t0 + const Duration(milliseconds: 7868),
      ),
      isNotNull,
      reason: '7868ms 仍在末拍（第 8 拍，自 0 数第 7）内',
    );
    expect(
      practiceStateAt(
        timeline: timeline,
        t0: t0,
        now: t0 + const Duration(milliseconds: 7868, microseconds: 900),
      ),
      isNull,
      reason: '富余窗内节拍网格已走出最后一拍',
    );
  });

  test('拍字段与 beatAt 全程一致（奇 BPM 61 逐 37ms 扫描）', () {
    final timeline = compileTimeline(
      chart: parseChart('{start_of_verse}\n[C]啦 [G]啦\n{end_of_verse}\n'),
      pattern: builtinStrumPatterns.last,
      bpm: 61,
    );
    final periodMs = timeline.periodMs;
    for (var ms = 0; ms < 7869; ms += 37) {
      final now = at(ms);
      final state = practiceStateAt(timeline: timeline, t0: t0, now: now)!;
      final visual = beatAt(now: now, t0: t0, periodMs: periodMs)!;
      expect(state.beat, visual.$1, reason: '$ms 处全曲拍号应与节拍器一致');
      expect(state.beatInBar, visual.$2, reason: '$ms 处拍内位置应与节拍器一致');
      expect(state.isStrongBeat, visual.$3, reason: '$ms 处强弱应与节拍器一致');
    }
  });
}
