import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/beat_scheduling.dart';

/// 调度窗口决策纯函数:全部用假时钟(手动给的 now)驱动,期望值为手工真值
/// (120BPM = 500ms/拍;97BPM 周期 618.5567ms 逐拍四舍五入)。
/// 过窗一律用默认 lookahead(400ms,spike B 验证值)。
void main() {
  BeatSchedule sched120({Duration t0 = Duration.zero, int? totalBeats}) =>
      BeatSchedule(t0: t0, nextBeat: 0, periodMs: 500, totalBeats: totalBeats);

  test('t0 首次过窗:只有第 0 拍入窗(下一拍 500ms 在窗外)', () {
    final (next, due) = sched120().scheduleDue(now: Duration.zero);
    expect(due, [(0, Duration.zero)]);
    expect(next.nextBeat, 1);
  });

  test('边界语义:t == now + lookahead 恰好入窗(spike B 同语义)', () {
    // now=100ms → 窗口右沿 500ms,第 1 拍恰在沿上。
    final (next, due) = sched120().scheduleDue(now: const Duration(milliseconds: 100));
    expect(due, [(0, Duration.zero), (1, const Duration(milliseconds: 500))]);
    expect(next.nextBeat, 2);
  });

  test('时钟跳跃一次补齐窗内多拍,已预定拍绝不重复', () {
    var s = sched120();
    (s, _) = s.scheduleDue(now: Duration.zero); // 拍0
    final (next, due) = s.scheduleDue(now: const Duration(seconds: 1));
    expect(due.map((b) => b.$1), [1, 2], reason: '拍1(500ms)、拍2(1000ms)入窗,拍3(1500ms)未到');
    s = next;
    // 同一时刻反复过窗:无新增。
    final (same, due2) = s.scheduleDue(now: const Duration(seconds: 1));
    expect(due2, isEmpty);
    expect(same.nextBeat, s.nextBeat);
  });

  test('连续模式(totalBeats=null)无上限;totalBeats 封顶后不再预定', () {
    var continuous = sched120();
    var now = Duration.zero;
    for (var i = 0; i < 20; i++) {
      (continuous, _) = continuous.scheduleDue(now: now);
      now += const Duration(seconds: 1);
    }
    // 末次过窗 now=19s → 窗右沿 19.4s:拍 i ≤ 38(500i ≤ 19400)→ 共 39 拍。
    expect(continuous.nextBeat, 39);

    var capped = sched120(totalBeats: 5);
    now = Duration.zero;
    for (var i = 0; i < 20; i++) {
      (capped, _) = capped.scheduleDue(now: now);
      now += const Duration(seconds: 1);
    }
    expect(capped.nextBeat, 5);
  });

  test('非整周期 BPM=97:拍时刻 = round(i × 60000/97)ms(手工真值)', () {
    var s = BeatSchedule(t0: Duration.zero, nextBeat: 0, periodMs: 60000 / 97);
    final (next, due) = s.scheduleDue(
      now: Duration.zero,
      lookahead: const Duration(seconds: 3),
    );
    expect(
      due.map((b) => b.$2.inMilliseconds),
      [0, 619, 1237, 1856, 2474],
      reason: 'i×618.5567 四舍五入:0/619/1237/1856/2474',
    );
    expect(next.nextBeat, 5);
  });

  test('5 分钟回归 @120BPM:600 拍全部按序预定,时刻精确无缺口(验收1纯函数版)', () {
    var s = sched120(totalBeats: 600);
    var now = Duration.zero;
    final beatTimes = <int, Duration>{};
    while (s.nextBeat < 600) {
      final (next, due) = s.scheduleDue(now: now);
      for (final (beat, time) in due) {
        expect(beatTimes.containsKey(beat), isFalse, reason: '拍 $beat 重复预定');
        beatTimes[beat] = time;
      }
      s = next;
      now += const Duration(milliseconds: 40); // 40ms 轮询,假时钟推进
    }
    expect(beatTimes, hasLength(600));
    expect(s.nextBeat, 600);
    for (var i = 0; i < 600; i++) {
      expect(beatTimes[i], Duration(milliseconds: i * 500), reason: '拍 $i 时刻');
    }
  });

  group('reanchored:运行中换 BPM 即时生效,保持拍内相位', () {
    test('整拍位换速:下一未预定拍恰在一个新周期后', () {
      // @120 跑到 now=1s:拍0/1/2 已预定(nextBeat=3),恰好整拍位(elapsed=2.0)。
      var s = sched120();
      (s, _) = s.scheduleDue(now: Duration.zero);
      (s, _) = s.scheduleDue(now: const Duration(milliseconds: 1000));
      expect(s.nextBeat, 3);

      final re = s.reanchored(const Duration(milliseconds: 1000), 60000 / 90);
      expect(re.nextBeat, 3, reason: '已预定拍不重排');
      expect(
        re.beatTime(3),
        const Duration(milliseconds: 1667),
        reason: 'now + 666.67ms(一个新周期),四舍五入 1667',
      );
    });

    test('拍中间换速:相位保持——剩余相位按新周期折算', () {
      // @120 跑到 now=1250ms(elapsed=2.5 拍,相位 0.5),拍 0/1/2 已预定;
      // 换 90BPM 后首个新拍(第 3 拍)应在 now + 0.5×666.67 ≈ 1583ms。
      var s = sched120();
      (s, _) = s.scheduleDue(now: Duration.zero);
      (s, _) = s.scheduleDue(now: const Duration(milliseconds: 1000));
      final re = s.reanchored(const Duration(milliseconds: 1250), 60000 / 90);
      expect(re.nextBeat, 3);
      expect(re.beatTime(3), const Duration(milliseconds: 1583));
    });

    test('尚无拍预定(nextBeat=0)时保持 0,不跳拍', () {
      final s = sched120();
      final re = s.reanchored(const Duration(milliseconds: 300), 60000 / 90);
      expect(re.nextBeat, 0);
      // 300ms = 0.6 个新周期 → 第 0 拍落在过去 0.6×666.67 ≈ 400ms 处,
      // 下次过窗作为"过去时刻"立即补响,拍 0 不丢。
      expect(re.beatTime(0), const Duration(milliseconds: -100));
    });
  });

  group('beatAt:引擎时刻 → 视觉拍(纯函数,UI 轮询用)', () {
    test('t0 之前(预备期)无拍', () {
      expect(
        beatAt(
          now: const Duration(milliseconds: -1),
          t0: Duration.zero,
          periodMs: 500,
        ),
        isNull,
      );
    });

    test('整点与拍中:拍序号 = floor(elapsed/period)', () {
      expect(beatAt(now: Duration.zero, t0: Duration.zero, periodMs: 500), (0, 0, true));
      expect(
        beatAt(now: const Duration(milliseconds: 500), t0: Duration.zero, periodMs: 500),
        (1, 1, false),
      );
      expect(
        beatAt(now: const Duration(microseconds: 1999900), t0: Duration.zero, periodMs: 500),
        (3, 3, false),
      );
      expect(
        beatAt(now: const Duration(seconds: 2), t0: Duration.zero, periodMs: 500),
        (4, 0, true),
        reason: '4/4 循环:第 5 拍回到强拍',
      );
    });
  });
}
