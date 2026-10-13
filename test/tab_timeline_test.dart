import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/beat_scheduling.dart' show BeatSchedule;
import 'package:ukeflow/core/model/tab_chart.dart';
import 'package:ukeflow/core/practice/tab_timeline.dart';

/// 工单 12 接缝:指弹谱+BPM(+变速)→ 逐音事件时间轴。
/// 期望值一律是手算字面量(独立真值),不由实现的公式复算而来;
/// 取整语义与工单 08 compileTimeline 同型(逐事件四舍五入,不累加)。
void main() {
  test('单音谱 @120BPM:事件时刻精确,曲末落整小节线', () {
    final timeline = compileTabTimeline(
      chart: const TabChart(
        title: '测试曲',
        tempo: 80,
        notes: [TabNote(string: 1, fret: 3, beat: 0)],
      ),
      bpm: 120,
    );

    // 120 BPM:一拍 500ms;单音在拍 0 → 0ms。
    expect(timeline.notes, hasLength(1));
    expect(timeline.notes.single.time, Duration.zero);
    expect(timeline.notes.single.string, 1);
    expect(timeline.notes.single.fret, 3);

    // 末音在拍 0、保有 1 拍,曲末上取整到整小节线:1 小节 = 4 拍。
    expect(timeline.periodMs, 500.0);
    expect(timeline.totalBeats, 4);
    expect(timeline.totalDuration, const Duration(milliseconds: 2000));
  });

  test('录入序乱序:编译按拍位升序;同拍保持录入序', () {
    final timeline = compileTabTimeline(
      chart: const TabChart(
        title: '测试曲',
        tempo: 80,
        notes: [
          TabNote(string: 2, fret: 0, beat: 1),
          TabNote(string: 1, fret: 0, beat: 0),
          TabNote(string: 4, fret: 0, beat: 1), // 与拍 1 的另一音同时拨响
          TabNote(string: 3, fret: 0, beat: 2),
        ],
      ),
      bpm: 120,
    );

    expect(timeline.notes.map((n) => n.time.inMilliseconds), [
      0,
      500,
      500,
      1000,
    ]);
    // 拍 1 的两音保持录入序(2 弦在前),整体按拍位升序。
    expect(timeline.notes.map((n) => (n.time.inMilliseconds, n.string)), [
      (0, 1),
      (500, 2),
      (500, 4),
      (1000, 3),
    ]);
  });

  test('奇 BPM 61:逐事件「拍位×拍长」四舍五入不累加', () {
    final timeline = compileTabTimeline(
      chart: const TabChart(
        title: '测试曲',
        tempo: 80,
        notes: [
          TabNote(string: 1, fret: 0, beat: 0),
          TabNote(string: 1, fret: 0, beat: 1),
          TabNote(string: 1, fret: 0, beat: 2),
          TabNote(string: 1, fret: 0, beat: 3),
        ],
      ),
      bpm: 61,
    );

    // periodMs = 60000/61 ≈ 983.607。手算:round(983.607)=984、
    // round(1967.213)=1967、round(2950.820)=2951(与工单 08 的 61 BPM
    // 字面量同一纪律:累加式会得别值)。
    expect(timeline.notes.map((n) => n.time.inMilliseconds), [
      0,
      984,
      1967,
      2951,
    ]);
  });

  test('变速 50%:全部事件时刻等比 ×2(整网格精确字面量)', () {
    final timeline = compileTabTimeline(
      chart: const TabChart(
        title: '测试曲',
        tempo: 80,
        notes: [
          TabNote(string: 1, fret: 0, beat: 0),
          TabNote(string: 1, fret: 1, beat: 1),
          TabNote(string: 2, fret: 0, beat: 2.5), // 附点半拍同样等比
          TabNote(string: 3, fret: 0, beat: 3),
        ],
      ),
      bpm: 120,
      speed: 0.5,
    );

    // periodMs = 500/0.5 = 1000;拍 2.5 → 2500。
    expect(timeline.notes.map((n) => n.time.inMilliseconds), [
      0,
      1000,
      2500,
      3000,
    ]);
    expect(timeline.periodMs, 1000.0);
    expect(timeline.totalDuration, const Duration(milliseconds: 4000));
  });

  test('曲末上取整:末音在拍 40(小节头)保有整拍并收进 11 小节;末音半拍位同理', () {
    // 末音拍 40:ceil(40)+1 = 41 → 上取整到 44(11 小节),非 40 收尾。
    expect(
      tabTotalBeats(
        const TabChart(
          title: 't',
          tempo: 80,
          notes: [TabNote(string: 1, fret: 0, beat: 40)],
        ),
      ),
      44,
    );
    // 末音在拍 40.5(半拍):ceil(40.5)+1 = 42 → 44。
    expect(
      tabTotalBeats(
        const TabChart(
          title: 't',
          tempo: 80,
          notes: [TabNote(string: 1, fret: 0, beat: 40.5)],
        ),
      ),
      44,
    );
  });

  test('空谱:空时间轴、拍数 0', () {
    final timeline = compileTabTimeline(
      chart: const TabChart(title: '空', tempo: 80, notes: []),
      bpm: 120,
    );
    expect(timeline.notes, isEmpty);
    expect(timeline.totalBeats, 0);
    expect(timeline.totalDuration, Duration.zero);
  });

  test('非法入参:非正/非有限 BPM 与变速比抛 ArgumentError(release 也生效)', () {
    const chart = TabChart(title: 't', tempo: 80, notes: []);
    for (final bpm in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => compileTabTimeline(chart: chart, bpm: bpm),
        throwsArgumentError,
        reason: 'bpm=$bpm',
      );
    }
    expect(
      () => compileTabTimeline(chart: chart, bpm: 120, speed: 0.0),
      throwsArgumentError,
    );
    expect(
      () => compileTabTimeline(chart: chart, bpm: 120, speed: -0.5),
      throwsArgumentError,
    );
  });

  test('同拍大量音(40 个,>32 走非稳定排序路径)仍保持录入序', () {
    // Dart List.sort 对 >32 元素不保证稳定:同拍序契约必须进排序键,
    // 此测试在非稳定路径上锁死(4 音小输入走插入排序测不出)。
    final notes = [
      for (var i = 0; i < 40; i++) TabNote(string: 1, fret: i, beat: 0),
    ];
    final timeline = compileTabTimeline(
      chart: TabChart(title: 't', tempo: 80, notes: notes),
      bpm: 120,
    );
    expect(
      [for (final e in timeline.notes) e.fret],
      [for (var i = 0; i < 40; i++) i],
    );
  });

  test('跨 BPM 扫域 40..208 逐 1(含两端)×变速 {1.0, 0.5, 0.73}:拍上音与'
      '节拍网格同刻、半拍音居间、时序单调、末音不越曲末', () {
    // CODING_STANDARDS·边界扫域:取整边界不在单点 BPM 上验证(整除点
    // 显不出 round(拍数×period) 的取整误差);跨产品域全扫,断言四条
    // 结构保证。曲末判定(工单 13)消费 totalDuration,「末音不越曲末」
    // 是它的正确性前提——结构保证,非数值巧合(工单 11 教训)。
    final notes = [
      for (var beat = 0; beat <= 16; beat++) ...[
        TabNote(string: 1, fret: 0, beat: beat.toDouble()),
        TabNote(string: 2, fret: 0, beat: beat + 0.5),
      ],
    ];
    final chart = TabChart(title: 't', tempo: 80, notes: notes);

    for (var bpm = 40; bpm <= 208; bpm++) {
      for (final speed in const [1.0, 0.5, 0.73]) {
        final timeline = compileTabTimeline(
          chart: chart,
          bpm: bpm.toDouble(),
          speed: speed,
        );
        final grid = BeatSchedule(
          t0: Duration.zero,
          nextBeat: 0,
          periodMs: timeline.periodMs,
        );
        final reason = 'bpm=$bpm speed=$speed';

        for (var k = 0; k <= 16; k++) {
          // 拍上音 == BeatSchedule.beatTime(独立换算路径):拍点音与
          // 节拍声同源同刻,任何变速下成立。
          expect(
            timeline.notes[2 * k].time,
            grid.beatTime(k),
            reason: '$reason 拍 $k',
          );
          // 半拍音严格居两拍之间:取整不越拍线。
          expect(
            timeline.notes[2 * k + 1].time,
            greaterThan(grid.beatTime(k)),
            reason: '$reason 拍 $k+0.5',
          );
          expect(
            timeline.notes[2 * k + 1].time,
            lessThan(grid.beatTime(k + 1)),
            reason: '$reason 拍 $k+0.5',
          );
        }

        // 时序单调:拍位升序的时刻严格递增(相邻拍位差 ≥ 0.5 拍,远大于
        // 1ms 取整窗,不得出现取整倒挂)。
        final times = [for (final e in timeline.notes) e.time.inMilliseconds];
        for (var i = 1; i < times.length; i++) {
          expect(times[i], greaterThan(times[i - 1]), reason: '$reason i=$i');
        }

        // 末音不越曲末:曲末判定不会吞掉最后一个音。
        expect(
          timeline.notes.last.time,
          lessThan(timeline.totalDuration),
          reason: reason,
        );
      }
    }
  });
}
