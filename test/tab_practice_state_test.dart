import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/tab_chart.dart';
import 'package:ukeflow/core/practice/tab_practice_state.dart';
import 'package:ukeflow/core/practice/tab_timeline.dart';

/// 工单 13 接缝:(逐音事件时间轴, 曲头锚, 引擎时刻) → 逐音练习状态。
/// 期望值一律手算字面量;当前音的翻转边界认事件时刻(示范声预定在
/// round(拍位×拍长),高亮须同刻翻转——票面「示范声与高亮同刻」的
/// 纯函数层锁定);跨 BPM 扫域见文末(CODING_STANDARDS)。
void main() {
  // 120 BPM(500ms/拍):事件时刻 0 / 500 / 1250 / 1500ms,
  // 全曲 4 拍(1 小节) = 2000ms。拍 2.5 的半拍音钉住非整除边界。
  final chart = const TabChart(
    title: '测试曲',
    tempo: 80,
    notes: [
      TabNote(string: 1, fret: 3, beat: 0),
      TabNote(string: 1, fret: 0, beat: 1),
      TabNote(string: 2, fret: 3, beat: 2.5),
      TabNote(string: 3, fret: 2, beat: 3),
    ],
  );
  final timeline = compileTabTimeline(chart: chart, bpm: 120);

  test('曲头即翻第 0 音:当前音 0,拍 0 强拍,预告整窗', () {
    final state = tabPracticeStateAt(
      timeline: timeline,
      t0: Duration.zero,
      now: Duration.zero,
    );
    expect(state, isNotNull);
    expect(state!.currentNoteIndex, 0);
    expect(state.beat, 0);
    expect(state.beatInBar, 0);
    expect(state.isStrongBeat, isTrue);
    expect(state.upcomingNoteIndexes, [1, 2, 3], reason: '(0, 2000] 窗内全部后音');
  });

  test('当前音恰在事件时刻翻转:500ms 处第 1 音已是当前(与示范声同刻)', () {
    final before = tabPracticeStateAt(
      timeline: timeline,
      t0: Duration.zero,
      now: const Duration(milliseconds: 499),
    );
    expect(before!.currentNoteIndex, 0, reason: '事件时刻前 1ms 仍是上一音');
    final at = tabPracticeStateAt(
      timeline: timeline,
      t0: Duration.zero,
      now: const Duration(milliseconds: 500),
    );
    expect(at!.currentNoteIndex, 1, reason: '时刻 ≤ now 即翻转——示范声预定在 500ms,高亮同刻');
    expect(at.upcomingNoteIndexes, [2, 3], reason: '(500, 2500] 窗内 1250/1500');
  });

  test('长音持稳:半拍音过后当前音停在末音,不闪断', () {
    final state = tabPracticeStateAt(
      timeline: timeline,
      t0: Duration.zero,
      now: const Duration(milliseconds: 1600),
    );
    expect(state!.currentNoteIndex, 3, reason: '末音 1500ms 起,持稳到曲末');
    expect(state.upcomingNoteIndexes, isEmpty);
    expect(state.beat, 3);
    expect(state.isStrongBeat, isFalse);
  });

  test('预备期(now 早于曲头锚)返回 null;曲末认节拍网格,恰在名义曲长翻 null', () {
    final t0 = const Duration(milliseconds: 3700); // 模拟预备 4 拍后的曲头
    expect(
      tabPracticeStateAt(
        timeline: timeline,
        t0: t0,
        now: const Duration(milliseconds: 3699),
      ),
      isNull,
      reason: '预备期无正曲状态(页面据此切倒计面板)',
    );
    // 名义曲长 2000ms:绝对 5699ms 仍在末拍富余窗内,5700ms 网格走出。
    final last = tabPracticeStateAt(
      timeline: timeline,
      t0: t0,
      now: const Duration(milliseconds: 3700 + 1999),
    );
    expect(last, isNotNull);
    expect(
      tabPracticeStateAt(
        timeline: timeline,
        t0: t0,
        now: const Duration(milliseconds: 3700 + 2000),
      ),
      isNull,
      reason: 'beat ≥ totalBeats 即曲末,翻 null 的时刻 = 名义曲长(与弹唱同界)',
    );
  });

  test('跨 BPM 扫域:翻转边界/预告窗/曲末在全产品域成立(CODING_STANDARDS)', () {
    // 半拍音 + 同拍双音(和弦)钉住非整除与并列边界;期望值由**线性扫描**
    // 事件时刻得出(独立机制:实现是二分查找,oracle 是逐个比较)。
    final sweepChart = const TabChart(
      title: '扫域曲',
      tempo: 80,
      notes: [
        TabNote(string: 1, fret: 0, beat: 0),
        TabNote(string: 2, fret: 3, beat: 1),
        TabNote(string: 2, fret: 1, beat: 2.5),
        TabNote(string: 3, fret: 2, beat: 3),
        TabNote(string: 1, fret: 3, beat: 4.5),
        TabNote(string: 3, fret: 0, beat: 5),
        TabNote(string: 4, fret: 2, beat: 5), // 同拍双音,保持录入序
        TabNote(string: 1, fret: 0, beat: 6),
      ],
    );
    const window = Duration(seconds: 2);
    final micro = const Duration(microseconds: 1);

    for (var bpm = 40; bpm <= 208; bpm++) {
      for (final speed in const [0.5, 0.75, 1.0]) {
        final tl = compileTabTimeline(
          chart: sweepChart,
          bpm: bpm.toDouble(),
          speed: speed,
        );
        final times = tl.notes.map((n) => n.time).toList();

        // 期望当前音:最后一个 time ≤ elapsed 的下标(线性扫描 oracle)。
        int expectedCurrent(Duration elapsed) {
          var idx = -1;
          for (var i = 0; i < times.length; i++) {
            if (times[i] <= elapsed) idx = i;
          }
          return idx;
        }

        // 期望预告:(elapsed, elapsed+窗] 内的下标集合。
        List<int> expectedUpcoming(Duration elapsed) => [
          for (var i = 0; i < times.length; i++)
            if (times[i] > elapsed && times[i] <= elapsed + window) i,
        ];

        void checkAt(Duration elapsed) {
          if (elapsed < Duration.zero) return; // beat 0 前 1µs 探针在曲头之前
          final state = tabPracticeStateAt(
            timeline: tl,
            t0: Duration.zero,
            now: elapsed,
            previewWindow: window,
          )!;
          expect(
            state.currentNoteIndex,
            expectedCurrent(elapsed),
            reason:
                'bpm=$bpm(speed $speed) elapsed=${elapsed.inMilliseconds}ms 当前音',
          );
          expect(
            state.upcomingNoteIndexes,
            expectedUpcoming(elapsed),
            reason:
                'bpm=$bpm(speed $speed) elapsed=${elapsed.inMilliseconds}ms 预告窗',
          );
          // 当前音绝不在预告窗回流;预告升序连续。
          if (state.upcomingNoteIndexes.isNotEmpty) {
            expect(
              state.upcomingNoteIndexes.first,
              greaterThan(state.currentNoteIndex),
            );
            expect(
              state.upcomingNoteIndexes.last - state.upcomingNoteIndexes.first,
              state.upcomingNoteIndexes.length - 1,
            );
          }
        }

        // 探针:每个事件时刻前 1µs / 恰在其上 / 之后半程,加 0 与曲末两端。
        for (final t in times) {
          checkAt(t - micro);
          checkAt(t);
          checkAt(t + const Duration(milliseconds: 50));
        }
        checkAt(Duration.zero);

        // 曲末边界:名义曲长翻 null,前 1µs 仍非 null。
        expect(
          tabPracticeStateAt(
            timeline: tl,
            t0: Duration.zero,
            now: tl.totalDuration - micro,
            previewWindow: window,
          ),
          isNotNull,
          reason: 'bpm=$bpm speed=$speed 曲末前 1µs 仍有状态',
        );
        expect(
          tabPracticeStateAt(
            timeline: tl,
            t0: Duration.zero,
            now: tl.totalDuration,
            previewWindow: window,
          ),
          isNull,
          reason: 'bpm=$bpm speed=$speed 名义曲长即曲末',
        );
      }
    }
  });
}
