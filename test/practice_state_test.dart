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

  test('曲末四舍五入富余窗内不出现幻拍(拍号走出最后一拍即曲末)', () {
    // BPM 61 两小节:第 8 拍网格起点 7868.85ms,取整边界 7869ms(=名义
    // 曲长);统一取整后富余窗 [7868.85, 7869) 归末拍,7869ms 即曲末——
    // 任何时刻都不会给出 beat=8 的状态。
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
        now: t0 + const Duration(milliseconds: 7868, microseconds: 900),
      ),
      isNotNull,
      reason: '7868.9ms 仍在末拍(第 8 拍,自 0 数第 7)内',
    );
    expect(
      practiceStateAt(
        timeline: timeline,
        t0: t0,
        now: t0 + const Duration(milliseconds: 7869),
      ),
      isNull,
      reason: '取整边界 7869ms = 名义曲长,走出即曲末',
    );
  });

  test('拍字段与动作查找同毫秒翻转:条带跨小节无空白帧(61BPM 3934ms)', () {
    // 61BPM:小节 1 首扫弦取整在 3934ms;拍 4 网格点 3934.43ms 取整同为
    // 3934ms。beatAt 与事件查找同一取整边界 → 同一毫秒一起翻小节,
    // 跟练条带的跨小节守卫不再有 ~0.4ms 的空白帧(歌词行跨这两小节,
    // 同行不翻页)。
    final timeline = compileTimeline(
      chart: parseChart('{start_of_verse}\n[C]啦 [G]啦\n{end_of_verse}\n'),
      pattern: builtinStrumPatterns.first,
      bpm: 61,
    );
    final before = practiceStateAt(timeline: timeline, t0: t0, now: at(3933))!;
    expect(before.beat, 3);
    expect(before.currentStrum!.barIndex, 0);
    expect(identical(before.currentLine, timeline.lyrics.single), isTrue);

    final atBoundary = practiceStateAt(timeline: timeline, t0: t0, now: at(3934))!;
    expect(atBoundary.beat, 4, reason: '拍 4 与小节 1 首扫弦同毫秒翻转');
    expect(atBoundary.currentStrum!.barIndex, 1);
    expect(atBoundary.currentStrum!.time.inMilliseconds, 3934);
    expect(identical(atBoundary.currentLine, timeline.lyrics.single), isTrue);
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

  // ── 工单 10:控制态查询 ────────────────────────────────────────────

  test('prepStateAt:预备窗内返回剩余倒计,窗前/窗后 null', () {
    // 预备 4 拍 @ 750ms/拍:预备窗 [t0Prep, t0Prep+3000)。
    const t0Prep = Duration(milliseconds: 5000);
    const periodMs = 750.0;
    int? countAt(int msAfterPrep) => prepStateAt(
          now: t0Prep + Duration(milliseconds: msAfterPrep),
          t0Prep: t0Prep,
          periodMs: periodMs,
        )?.count;

    expect(countAt(0), 4, reason: '预备第 1 拍:倒数 4');
    expect(countAt(749), 4, reason: '仍在第 1 预备拍内');
    expect(countAt(750), 3, reason: '恰入第 2 预备拍:倒数 3');
    expect(countAt(1500), 2);
    expect(countAt(2250), 1, reason: '最后预备拍:倒数 1');
    expect(countAt(2999), 1);
    // 曲头(第 4 预备拍边界含富余窗):预备已结束。
    expect(countAt(3000), isNull);
    expect(countAt(3001), isNull);
    expect(
      prepStateAt(
        now: t0Prep - const Duration(milliseconds: 1),
        t0Prep: t0Prep,
        periodMs: periodMs,
      ),
      isNull,
      reason: '预备窗之前(产品不可达,纯函数自守)',
    );
  });

  test('prepStateAt 边界扫域(40..208 逐 1):预备期倒计恒在,曲头无缝交正曲', () {
    // 单点整除 BPM(80/120)测不出 round(4×period) 的取整误差——曾炸出
    // 208BPM 下 0 时刻被误判预备窗外→页面当曲末停机。全 BPM 扫描锁死
    // 这一整类,并断言与 practiceStateAt 的同刻交接(预备毕即入正曲)。
    for (var bpm = 40; bpm <= 208; bpm++) {
      final periodMs = 60000 / bpm;
      final t0Prep = const Duration(milliseconds: 977); // 非零锚防偶然对齐
      final roundPrepMs = (4 * periodMs).round();
      final songT0 = t0Prep + Duration(milliseconds: roundPrepMs);
      final samePeriod = compileTimeline(
        chart: parseChart(fiveBarChart),
        pattern: builtinStrumPatterns.first,
        bpm: bpm.toDouble(),
      );
      for (var us = 0; us < roundPrepMs * 1000; us += 37000) {
        expect(
          prepStateAt(
            now: t0Prep + Duration(microseconds: us),
            t0Prep: t0Prep,
            periodMs: periodMs,
          ),
          isNotNull,
          reason: 'bpm=$bpm us=$us:预备期内倒计不得缺席(缺席即页面误判曲末)',
        );
      }
      final lastPrep = t0Prep + Duration(microseconds: roundPrepMs * 1000 - 1);
      expect(
        prepStateAt(now: lastPrep, t0Prep: t0Prep, periodMs: periodMs)!.count,
        1,
        reason: 'bpm=$bpm:曲头前 1µs 仍在最后预备拍',
      );
      expect(
        prepStateAt(now: songT0, t0Prep: t0Prep, periodMs: periodMs),
        isNull,
        reason: 'bpm=$bpm:曲头起预备结束',
      );
      expect(
        practiceStateAt(timeline: samePeriod, t0: songT0, now: songT0),
        isNotNull,
        reason: 'bpm=$bpm:预备毕同刻即入正曲(无缝交接,双 null 才是误判曲末)',
      );
    }
  });

  test('prepStateAt:非整除拍周期(208BPM)边界不误判窗外', () {
    // 208BPM:周期 288.46ms,预备跨度 round(4×288.46) = 1154ms。
    // 锚在预备第 0 拍(网格原点)时 0 时刻恒倒数 4;若锚取整后的曲头
    // 反推,0 时刻剩余 4.0005 拍、ceil=5 会被误判窗外(曾炸出)。
    const t0Prep = Duration.zero;
    const periodMs = 60000 / 208;
    expect(
      prepStateAt(now: Duration.zero, t0Prep: t0Prep, periodMs: periodMs)!.count,
      4,
    );
    expect(
      prepStateAt(
        now: Duration(milliseconds: 1153),
        t0Prep: t0Prep,
        periodMs: periodMs,
      )!.count,
      1,
      reason: '曲头前 1ms 仍在最后预备拍',
    );
    expect(
      prepStateAt(
        now: Duration(milliseconds: 1154),
        t0Prep: t0Prep,
        periodMs: periodMs,
      ),
      isNull,
      reason: '取整曲头(round(4×period))起预备结束',
    );
  });

  test('prepStateAt 倒计与拍声同毫秒翻转:跨 BPM 扫域钉取整边界(审计30 #19)', () {
    // 拍声预定在 round(k×p)(beatTime 语义):倒计必须在同一毫秒翻页,
    // 不得按连续网格 floor 晚亚毫秒(61BPM 拍 2 声 1967ms vs floor 界
    // 1967.2ms)。
    for (var bpm = 40; bpm <= 208; bpm++) {
      final periodMs = 60000 / bpm;
      int? countAt(double ms) => prepStateAt(
            now: Duration(milliseconds: ms.round()),
            t0Prep: Duration.zero,
            periodMs: periodMs,
          )?.count;
      for (var k = 0; k < 4; k++) {
        final click = (k * periodMs).round();
        expect(
          countAt(click.toDouble()),
          4 - k,
          reason: 'bpm=$bpm 拍 $k:第 ${k + 1} 声响的同一毫秒显示 ${4 - k}',
        );
        if (k > 0) {
          expect(
            countAt((click - 1).toDouble()),
            4 - (k - 1),
            reason: 'bpm=$bpm 拍 $k:声响前一毫秒仍是上一拍倒计',
          );
        }
      }
      expect(
        countAt((4 * periodMs).round().toDouble()),
        isNull,
        reason: 'bpm=$bpm:取整曲头无缝交正曲',
      );
    }
  });

}