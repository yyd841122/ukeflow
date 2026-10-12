import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/beat_scheduling.dart'
    show BeatSchedule, beatsPerBar;
import 'package:ukeflow/core/chart/builtin_charts.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';
import 'package:ukeflow/core/model/strum_pattern.dart';
import 'package:ukeflow/core/practice/play_timeline.dart';
import 'package:ukeflow/data/chord_library.dart';

import 'helpers/chart_fixtures.dart';

/// 工单 08 接缝一：谱文本+节奏型+BPM（+变速）→ 动作事件时间轴。
/// 期望值一律是手算字面量（独立真值），不由实现的公式复算而来。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('单和弦单行谱 @120BPM 全下扫：事件时刻逐一精确', () {
    final timeline = compileTimeline(
      chart: parseChart('{start_of_verse}\n[C]啦\n{end_of_verse}\n'),
      pattern: builtinStrumPatterns.first, // 下 下 下 下
      bpm: 120,
    );

    // 120 BPM：一拍 500ms；全下扫槽 0/2/4/6 → 0/500/1000/1500ms。
    expect(
      timeline.strums.map((e) => e.time.inMilliseconds),
      [0, 500, 1000, 1500],
    );
    expect(
      timeline.strums.map((e) => e.direction),
      everyElement(StrumDirection.down),
    );
    expect(timeline.strums.map((e) => e.chord), everyElement('C'));
    expect(timeline.strums.map((e) => e.slotInBar), [0, 2, 4, 6]);
    expect(timeline.strums.map((e) => e.barIndex), everyElement(0));

    // 歌词行与段落同在 0 时刻开场；同一时刻按 section→lyric→strum 定序。
    expect(timeline.lyrics.single.time, Duration.zero);
    expect(timeline.sections.single.time, Duration.zero);
    expect(
      timeline.events.map((e) => e.time.inMilliseconds),
      [0, 0, 0, 500, 1000, 1500],
    );

    expect(timeline.totalBeats, 4);
    expect(timeline.totalDuration, const Duration(milliseconds: 2000));
  });
  test('一行两个和弦记号：每记号一小节，扫弦携带本小节的和弦', () {
    final timeline = compileTimeline(
      chart: parseChart('{start_of_verse}\n[C]啦啦 [G]啦啦\n{end_of_verse}\n'),
      pattern: builtinStrumPatterns.first,
      bpm: 120,
    );

    // 2 小节 × 4 下扫 = 8 个扫弦；小节 0 全 C、小节 1 全 G。
    expect(timeline.strums, hasLength(8));
    expect(
      timeline.strums.map((e) => e.time.inMilliseconds),
      [0, 500, 1000, 1500, 2000, 2500, 3000, 3500],
    );
    expect(timeline.strums.map((e) => e.chord),
        ['C', 'C', 'C', 'C', 'G', 'G', 'G', 'G']);
    expect(timeline.strums.where((e) => e.barIndex == 1).map((e) => e.chord),
        everyElement('G'));
    expect(timeline.lyrics, hasLength(1));
    expect(timeline.totalBeats, 8);
    expect(timeline.totalDuration, const Duration(milliseconds: 4000));
  });

  test('无和弦行占一小节延续当前和弦；曲首无和弦则 chord 为 null', () {
    final timeline = compileTimeline(
      chart: parseChart(
        '{start_of_verse}\n[C]啦\n啦啦\n[Am]啦\n{end_of_verse}\n',
      ),
      pattern: builtinStrumPatterns.first,
      bpm: 120,
    );

    // 行 1(1 和弦=1 小节 C)、行 2(无和弦=1 小节延续 C)、行 3(Am)。
    expect(timeline.strums.map((e) => e.chord),
        ['C', 'C', 'C', 'C', 'C', 'C', 'C', 'C', 'Am', 'Am', 'Am', 'Am']);
    expect(timeline.strums.where((e) => e.barIndex == 1),
        everyElement(isA<PlayStrumEvent>()
            .having((e) => e.chord, 'chord', 'C')));
    expect(timeline.lyrics.map((e) => e.time.inMilliseconds), [0, 2000, 4000]);
    expect(timeline.totalBeats, 12);

    // 曲首无和弦：第一小节扫弦没有可依的和弦。
    final leading = compileTimeline(
      chart: parseChart('{start_of_verse}\n啦啦\n[C]啦\n{end_of_verse}\n'),
      pattern: builtinStrumPatterns.first,
      bpm: 120,
    );
    expect(leading.strums.take(4).map((e) => e.chord), everyElement(isNull));
    expect(leading.strums.elementAt(4).chord, 'C');
  });

  test('多段落谱：section 事件落在段落首小节，行序跨段落连续推进', () {
    final timeline = compileTimeline(
      chart: parseChart(
        '{start_of_verse}\n[C]啦\n{end_of_verse}\n'
        '{start_of_chorus: 副歌}\n[Am]啦\n[F]啦\n[G]啦\n{end_of_chorus}\n',
      ),
      pattern: builtinStrumPatterns.first,
      bpm: 120,
    );

    expect(timeline.sections.map((e) => e.sectionIndex), [0, 1]);
    expect(timeline.sections.map((e) => e.time.inMilliseconds), [0, 2000]);
    expect(timeline.sections.last.section.label, '副歌');
    expect(timeline.lyrics.map((e) => e.time.inMilliseconds),
        [0, 2000, 4000, 6000]);
    expect(timeline.lyrics.map((e) => e.sectionIndex), [0, 1, 1, 1]);
    expect(timeline.lyrics.map((e) => e.lineIndex), [0, 0, 1, 2]);
    expect(timeline.totalBeats, 16);
    expect(timeline.totalDuration, const Duration(milliseconds: 8000));
  });

  test('岛国节奏型：槽位(0,2,3,5,6,7)映射到精确时刻', () {
    final timeline = compileTimeline(
      chart: parseChart('{start_of_verse}\n[C]啦\n{end_of_verse}\n'),
      pattern: builtinStrumPatterns.last, // 下 下上 上下上（槽 4 空过）
      bpm: 120,
    );

    // 槽×250ms：0→0、2→500、3→750、5→1250、6→1500、7→1750；槽 4 空过。
    expect(timeline.strums.map((e) => e.slotInBar), [0, 2, 3, 5, 6, 7]);
    expect(timeline.strums.map((e) => e.time.inMilliseconds),
        [0, 500, 750, 1250, 1500, 1750]);
    expect(timeline.strums.map((e) => e.direction),
        [StrumDirection.down, StrumDirection.down, StrumDirection.up,
         StrumDirection.up, StrumDirection.down, StrumDirection.up]);
  });

  test('奇 BPM 61：逐事件四舍五入不累加，小节首与节拍网格同刻', () {
    const twoChords = '{start_of_verse}\n[C]啦 [G]啦\n{end_of_verse}\n';
    final timeline = compileTimeline(
      chart: parseChart(twoChords),
      pattern: builtinStrumPatterns.first,
      bpm: 61,
    );

    // slotMs = 30000/61 ≈ 491.803。手算：全局槽 8→3934、10→4918、
    // 12→5902、14→6885；若按槽累加会得 3936/4920/5904/6888——此断言锁死不累加。
    expect(
      timeline.strums.map((e) => e.time.inMilliseconds),
      [0, 984, 1967, 2951, 3934, 4918, 5902, 6885],
    );
    expect(timeline.totalBeats, 8);
    expect(timeline.totalDuration, const Duration(milliseconds: 7869));

    // 同步不变量：小节首扫弦时刻 == 同序号拍的 beatTime（core/audio
    // 已验证实现为真值来源）——扫弦声与节拍声同源同刻的结构保证。
    for (final period in [60000 / 61, 500.0]) {
      final t = compileTimeline(
        chart: parseChart(twoChords),
        pattern: builtinStrumPatterns.first,
        bpm: 60000 / period,
      );
      final schedule = BeatSchedule(
        t0: Duration.zero,
        nextBeat: 0,
        periodMs: period,
      );
      for (final strum in t.strums) {
        if (strum.slotInBar.isOdd) continue; // 半拍槽不落拍点,无拍时刻可言
        expect(
          strum.time,
          schedule.beatTime(
            strum.barIndex * beatsPerBar + strum.slotInBar ~/ 2,
          ),
          reason:
              '拍点扫弦(小节 ${strum.barIndex} 槽 ${strum.slotInBar})应与'
              '拍 ${strum.barIndex * 4 + strum.slotInBar ~/ 2} 同刻',
        );
      }
    }
  });

  test('变速 50%：全部事件时刻与原速严格等比（×2）', () {
    final half = compileTimeline(
      chart: parseChart('{start_of_verse}\n[C]啦 [G]啦\n{end_of_verse}\n'),
      pattern: builtinStrumPatterns.first,
      bpm: 120,
      speed: 0.5,
    );

    // 原速字面量 [0,500,1000,1500,2000,2500,3000,3500] 的 ×2（独立真值）。
    expect(half.periodMs, 1000.0);
    expect(
      half.strums.map((e) => e.time.inMilliseconds),
      [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000],
    );
    expect(half.totalBeats, 8);
    expect(half.totalDuration, const Duration(milliseconds: 8000));
    // 事件相对次序与和弦归属不因变速改变。
    expect(half.strums.map((e) => e.chord),
        ['C', 'C', 'C', 'C', 'G', 'G', 'G', 'G']);
  });

  test('变速 75%：非整网格下逐事件四舍五入出精确时刻', () {
    final threeQuarters = compileTimeline(
      chart: parseChart('{start_of_verse}\n[C]啦\n{end_of_verse}\n'),
      pattern: builtinStrumPatterns.first,
      bpm: 120,
      speed: 0.75,
    );

    // periodMs = 500/0.75 = 666.67ms；槽 0/2/4/6 → 0/667/1333/2000ms。
    expect(threeQuarters.periodMs, closeTo(2000 / 3, 0.001));
    expect(
      threeQuarters.strums.map((e) => e.time.inMilliseconds),
      [0, 667, 1333, 2000],
    );
    expect(threeQuarters.totalDuration, const Duration(milliseconds: 2667));
  });

  test('缺省 speed 与显式 1.0 编译结果一致', () {
    const source = '{start_of_verse}\n[C]啦 [G]啦\n{end_of_verse}\n';
    final implicit = compileTimeline(
      chart: parseChart(source),
      pattern: builtinStrumPatterns.first,
      bpm: 120,
    );
    final explicit = compileTimeline(
      chart: parseChart(source),
      pattern: builtinStrumPatterns.first,
      bpm: 120,
      speed: 1.0,
    );
    expect(implicit.strums.map((e) => e.time), explicit.strums.map((e) => e.time));
    expect(implicit.periodMs, explicit.periodMs);
  });

  test('变速 50% @奇 BPM 61：网格等比、拍点扫弦仍与拍声同刻', () {
    final half = compileTimeline(
      chart: parseChart('{start_of_verse}\n[C]啦 [G]啦\n{end_of_verse}\n'),
      pattern: builtinStrumPatterns.first,
      bpm: 61,
      speed: 0.5,
    );

    // slotMs = 60000/61 ≈ 983.606。手算：0/1967/3934/5902/7869/9836/11803/13770。
    // 逐事件对**最终网格**四舍五入，与「原速时刻×2 再取整」可差 1ms
    //（如槽 2：1967 vs 2×984=1968）——这是定型语义而非误差；换来的是
    // 拍点扫弦与拍声 beatTime 在任何变速下仍同刻（下方断言）。
    expect(half.periodMs, closeTo(120000 / 61, 0.001));
    expect(
      half.strums.map((e) => e.time.inMilliseconds),
      [0, 1967, 3934, 5902, 7869, 9836, 11803, 13770],
    );
    expect(half.totalDuration, const Duration(milliseconds: 15738));

    final schedule = BeatSchedule(
      t0: Duration.zero,
      nextBeat: 0,
      periodMs: half.periodMs,
    );
    for (final strum in half.strums) {
      if (strum.slotInBar.isOdd) continue;
      expect(
        strum.time,
        schedule.beatTime(
          strum.barIndex * beatsPerBar + strum.slotInBar ~/ 2,
        ),
      );
    }
  });

  test('空谱（无段落）编译出空时间轴，不抛错', () {
    final timeline = compileTimeline(
      chart: parseChart('{title: 空谱}\n'),
      pattern: builtinStrumPatterns.first,
      bpm: 120,
    );
    expect(timeline.events, isEmpty);
    expect(timeline.strums, isEmpty);
    expect(timeline.lyrics, isEmpty);
    expect(timeline.sections, isEmpty);
    expect(timeline.totalBeats, 0);
    expect(timeline.totalDuration, Duration.zero);
  });

  group('5 首目标曲冒烟（spec：能解析、能编译成时间轴、和弦全在白名单内）', () {
    late List<BuiltInChart> charts;
    late Set<String> libraryLabels;

    setUpAll(() async {
      final lib = ChordLibrary.parse(
        await rootBundle.loadString('assets/chords/ukulele.json'),
      );
      libraryLabels = lib.labels;
      charts = await BuiltInCharts.load(
        readAsset: rootBundle.loadString,
        allowedChords: lib.labels,
      );
    });

    test('每首都能以谱面 tempo 编译出非空时间轴，扫弦和弦全部可查', () {
      for (final built in charts) {
        final timeline = compileTimeline(
          chart: built.chart,
          pattern: builtinStrumPatterns.last, // 岛国型（练哪型就用哪型，冒烟取一）
          bpm: built.chart.tempo!.toDouble(),
        );
        expect(timeline.strums, isNotEmpty, reason: '${built.id} 应有扫弦事件');
        expect(timeline.lyrics, isNotEmpty, reason: '${built.id} 应有歌词行');
        expect(timeline.totalBeats, greaterThan(0));
        // 全曲事件按时刻升序（同刻 section→lyric→strum）。
        final times = timeline.events.map((e) => e.time.inMilliseconds).toList();
        expect(times, orderedEquals(times.toList()..sort()));
        // 有和弦记号的谱不应出现 null 和弦扫弦（每首曲谱首行都带记号）。
        expect(
          timeline.strums.map((e) => e.chord),
          everyElement(isNotNull),
          reason: '${built.id} 的谱首行应带和弦记号',
        );
        // 扫弦携带的和弦名全部在和弦库白名单内（能查指法与示范音）。
        final chords = timeline.strums.map((e) => e.chord!).toSet();
        expect(chords.intersection(libraryLabels), chords,
            reason: '${built.id} 出现白名单外和弦');
      }
    });
  });

}
