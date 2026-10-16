import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/beat_scheduling.dart';

/// 调度窗口决策纯函数:全部用假时钟(手动给的 now)驱动,期望值为手工真值
/// (120BPM = 500ms/拍;97BPM 周期 618.5567ms 逐拍四舍五入)。
/// 过窗一律用默认 lookahead(400ms,spike B 验证值)。
void main() {
  BeatSchedule sched120({Duration t0 = Duration.zero, int? totalBeats}) =>
      BeatSchedule(t0: t0, nextBeat: 0, periodMs: 500, totalBeats: totalBeats);

  test('periodMs 非有限或非正:ArgumentError(公共缝校验,不靠 assert)', () {
    for (final bad in [0.0, -500.0, double.nan, double.infinity, double.negativeInfinity]) {
      expect(
        () => BeatSchedule(t0: Duration.zero, nextBeat: 0, periodMs: bad),
        throwsArgumentError,
        reason: 'periodMs=$bad',
      );
    }
  });

  test('拍周期下限 1ms:低于拒以 ArgumentError,单窗拍数无界防线(审计30 #4)', () {
    expect(
      () => BeatSchedule(t0: Duration.zero, nextBeat: 0, periodMs: 0.9),
      throwsArgumentError,
    );
    expect(
      () => BeatSchedule(t0: Duration.zero, nextBeat: 0, periodMs: 1.0),
      returnsNormally,
      reason: '恰在下限可用(60000 BPM,产品域外但缝自洽)',
    );
  });

  test('时钟大步前跳:过期拍算术快进,窗内拍从首个未过期拍起不错不漏(审计30 #4)', () {
    final s = BeatSchedule(t0: Duration.zero, nextBeat: 0, periodMs: 1.0);
    final (next, due) = s.scheduleDue(
      now: const Duration(seconds: 100),
      lookahead: const Duration(milliseconds: 400),
      maxLate: const Duration(milliseconds: 40),
    );
    // 窗 [99960, 100400]ms:拍 99960..100400 共 441 拍,时刻逐拍精确。
    expect(due, hasLength(441));
    expect(due.first.$1, 99960);
    expect(due.first.$2, const Duration(milliseconds: 99960));
    expect(due.last.$1, 100400);
    expect(next.nextBeat, 100401);
  });

  test('快进不越过曲末:totalBeats 全部过期时 nextBeat 停在曲末(审计30 #4)', () {
    final capped = BeatSchedule(
      t0: Duration.zero,
      nextBeat: 0,
      periodMs: 1.0,
      totalBeats: 10,
    );
    final (next, due) = capped.scheduleDue(
      now: const Duration(seconds: 100),
      lookahead: const Duration(milliseconds: 400),
      maxLate: const Duration(milliseconds: 40),
    );
    expect(due, isEmpty);
    expect(next.nextBeat, 10, reason: '曲末状态不被快进越过');
  });

  test('t0 首次过窗:只有第 0 拍入窗(下一拍 500ms 在窗外)', () {
    final (next, due) = sched120().scheduleDue(now: Duration.zero);
    expect(due, [(0, Duration.zero)]);
    expect(next.nextBeat, 1);
  });

  test('边界语义:t == now + lookahead 恰好入窗(spike B 同语义)', () {
    // start 首过预定拍 0;now=100ms → 窗口右沿 500ms,第 1 拍恰在沿上。
    var s = sched120();
    (s, _) = s.scheduleDue(now: Duration.zero);
    final (next, due) = s.scheduleDue(now: const Duration(milliseconds: 100));
    expect(due, [(1, const Duration(milliseconds: 500))]);
    expect(next.nextBeat, 2);
  });

  test('时钟跳跃:超容差的过期拍跳过不回放,窗内拍照常预定', () {
    var s = sched120();
    (s, _) = s.scheduleDue(now: Duration.zero); // 拍0
    final (next, due) = s.scheduleDue(now: const Duration(seconds: 1));
    expect(due, [(2, const Duration(milliseconds: 1000))],
        reason: '拍1(500ms)已过期 500ms > 容差,跳过不补响;拍2(1000ms)在窗内');
    expect(next.nextBeat, 3, reason: '过期拍直接越过,nextBeat 不回头');
    s = next;
    // 同一时刻反复过窗:无新增。
    final (same, due2) = s.scheduleDue(now: const Duration(seconds: 1));
    expect(due2, isEmpty);
    expect(same.nextBeat, s.nextBeat);
  });

  test('迟到拍有界:恰迟一个容差仍照响,再迟 1ms 即放弃', () {
    // @120 起跑过一次窗后,迟滞跳到 now=2.54s:拍 1..4(500..2000ms)远过期
    // 跳过;拍 5(2500ms)恰迟 40ms(容差边界)→ 照响。
    var s = sched120();
    (s, _) = s.scheduleDue(now: Duration.zero);
    final (next, due) = s.scheduleDue(now: const Duration(milliseconds: 2540));
    expect(due, [(5, const Duration(milliseconds: 2500))],
        reason: '恰在 40ms 容差边界内(2500 ≥ 2540−40)');
    expect(next.nextBeat, 6);

    // 再迟 1ms(2500 < 2541−40)→ 放弃;拍 6(3000ms)未入窗,窗空。
    final (next2, due2) = s.scheduleDue(
      now: const Duration(milliseconds: 2541),
    );
    expect(due2, isEmpty, reason: '超容差的过期拍不产生机关枪补响');
    expect(next2.nextBeat, 6);
  });

  test('maxLate 可收紧:0 容差下过期拍一律不回放(恰在 now 的仍算窗内)', () {
    var s = sched120();
    (s, _) = s.scheduleDue(now: Duration.zero);
    final (next, due) = s.scheduleDue(
      now: const Duration(milliseconds: 501),
      maxLate: Duration.zero,
    );
    expect(due, isEmpty, reason: '拍1(500ms)迟 1ms,0 容差即弃');
    expect(next.nextBeat, 2);
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
    test('新周期非有限或非正:ArgumentError(t0 表达式先于构造器求值,须入口校验)', () {
      final s = sched120();
      for (final bad in [0.0, -500.0, double.nan, double.infinity]) {
        expect(
          () => s.reanchored(Duration.zero, bad),
          throwsArgumentError,
          reason: 'newPeriodMs=$bad',
        );
      }
    });

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
      // 300ms = 0.6 个新周期 → 第 0 拍落在过去 0.6×666.67 ≈ 400ms 处
      // (−100ms,已过期 400ms > 40ms 容差):下次过窗跳过不回放(有界迟到
      // 策略),拍 1(−100+667=567ms)在窗内照常。
      final (after, due) = re.scheduleDue(now: const Duration(milliseconds: 300));
      expect(due, [(1, const Duration(milliseconds: 567))]);
      expect(after.nextBeat, 2, reason: '拍 0 跳过,拍 1 已预定');
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

    test('分数周期:视觉拍在 beatTime 的取整毫秒边界翻转(与拍声同刻)', () {
      // 97BPM:period 618.5567ms,拍 2 声预定在 round(2×618.5567)=1237ms;
      // 视觉必须在同一毫秒翻转(按未取整网格会到 1237.11ms 才翻,声先于视)。
      const period = 60000 / 97;
      expect(
        beatAt(now: const Duration(milliseconds: 1236), t0: Duration.zero, periodMs: period),
        (1, 1, false),
      );
      expect(
        beatAt(now: const Duration(milliseconds: 1237), t0: Duration.zero, periodMs: period),
        (2, 2, false),
        reason: '拍 2 的 beatTime 恰在 1237ms,视觉同一毫秒翻转',
      );
    });

    test('61BPM 拍 4 在 3934ms 翻转(round(4×983.606)),亚毫秒富余不提前', () {
      const period = 60000 / 61;
      expect(
        beatAt(
          now: const Duration(milliseconds: 3933, microseconds: 999),
          t0: Duration.zero,
          periodMs: period,
        )!.$1,
        3,
      );
      expect(
        beatAt(now: const Duration(milliseconds: 3934), t0: Duration.zero, periodMs: period)!.$1,
        4,
        reason: '拍点网格 3934.43ms 取整为 3934ms,与拍点扫弦/翻页同界',
      );
    });

    test('periodMs 非有限或非正:ArgumentError', () {
      for (final bad in [0.0, -500.0, double.nan, double.infinity]) {
        expect(
          () => beatAt(now: Duration.zero, t0: Duration.zero, periodMs: bad),
          throwsArgumentError,
          reason: 'periodMs=$bad',
        );
      }
    });
  });

  test('快进扫域:全周期域上窗内拍集与逐拍 brute-force 逐项一致(边界扫域)', () {
    // 独立参考实现:从拍 0 逐拍推进,收 [now−40, now+400] 窗内的拍;
    // nextBeat = 首个超窗拍的序号(越过全部已过窗拍,含被 maxLate 跳过的)。
    (List<int>, int) bruteForce(double periodMs, Duration now) {
      const from = Duration(milliseconds: 40);
      const limit = Duration(milliseconds: 400);
      final expected = <int>[];
      var b = 0;
      for (;; b++) {
        final t = Duration(milliseconds: (b * periodMs).round());
        if (t > now + limit) break;
        if (t >= now - from) expected.add(b);
      }
      return (expected, b);
    }

    void checkOne(double periodMs, Duration now) {
      final s = BeatSchedule(t0: Duration.zero, nextBeat: 0, periodMs: periodMs);
      final (next, due) = s.scheduleDue(
        now: now,
        lookahead: const Duration(milliseconds: 400),
        maxLate: const Duration(milliseconds: 40),
      );
      final (expected, expectedNextBeat) = bruteForce(periodMs, now);
      expect(
        due.map((e) => e.$1).toList(),
        expected,
        reason: 'periodMs=$periodMs now=$now:窗内拍集不错不漏',
      );
      expect(
        next.nextBeat,
        expectedNextBeat,
        reason: 'periodMs=$periodMs now=$now:nextBeat 收在首个超窗拍',
      );
    }

    // 非整除周期域(小数周期,取整边界误差最丰富):
    for (var i = 0; i < 160; i++) {
      checkOne(1.0 + i * 0.37, const Duration(milliseconds: 2000));
    }
    // 产品 BPM 域 40..208 逐 1(跨 BPM 扫域,单点整除不作数):
    for (var bpm = 40; bpm <= 208; bpm++) {
      checkOne(60000 / bpm, const Duration(milliseconds: 5000));
    }
  });

}