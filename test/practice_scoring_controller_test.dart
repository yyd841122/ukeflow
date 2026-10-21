import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';
import 'package:ukeflow/core/model/chord.dart';
import 'package:ukeflow/core/practice/play_timeline.dart';
import 'package:ukeflow/core/scoring/strum_scorer.dart';
import 'package:ukeflow/features/play/scoring/practice_scoring_controller.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/scoring_fixtures.dart';

/// 跟练评分控制器(工单 33):假录音器+假引擎+假会话柄的会话生命周期、
/// 校准、挂起、循环清零、变速拍守恒、「错」判定、重听与弃评。
void main() {
  late FakeAudioEngine engine;
  late FakeRecorder recorder;
  late FakeSessionHandle handle;
  late ProviderContainer container;

  PracticeScoringController controller() =>
      container.read(practiceScoringProvider.notifier);

  setUp(() {
    final parts = scoringTestContainer();
    engine = parts.engine;
    recorder = parts.recorder;
    handle = parts.handle;
    container = parts.container;
    addTearDown(container.dispose);
  });

  /// 测试用和弦实例:音高来自 midi(fingering 的 midi 字段,主指法唯一)。
  Chord chordWithMidi(List<int> midi) => Chord(
    root: midi[0] % 12 == 9 ? 'A' : 'C',
    suffix: midi.contains(64) && !midi.contains(62) ? 'minor' : 'major',
    fingerings: [
      ChordFingering(
        frets: const [0, 0, 0, 0],
        fingers: const [0, 0, 0, 0],
        baseFret: 1,
        barres: const [],
        midi: midi,
      ),
    ],
  );

  /// 会话柄就位:编译时间轴(80BPM,4 小节 16 点)、锚点 0、周期 750ms、
  /// Am/C 和弦表(「错」判定的封闭集)。
  void armHandle({double periodMs = 750}) {
    handle.timeline = compileTimeline(
      chart: practiceFixtureChart,
      pattern: builtinStrumPatterns.first,
      bpm: 80,
    );
    handle.periodMs = periodMs;
    handle.chords = {
      'Am': chordWithMidi(const [57, 60, 64, 69]),
      'C': chordWithMidi(const [60, 64, 67, 72]),
    };
  }

  /// 把一段信号按 chunk 灌进假麦,引擎钟同步推进(到达即打引擎钟戳)。
  /// 引擎钟取 feed 起点的绝对时刻 + 切片内偏移——引擎钟单调前进,与
  /// 真实链路一致(切片从信号中段取时不得把钟拨回去)。
  Future<void> feedSignal(
    FakeAudioEngine targetEngine,
    FakeRecorder targetRecorder,
    Float64List signal, {
    int chunkMs = 50,
  }) async {
    const sr = scoringTestSampleRate;
    final step = sr * chunkMs ~/ 1000;
    final baseUs = targetEngine.engineTime().inMicroseconds;
    for (var pos = 0; pos < signal.length; pos += step) {
      final end = math.min(pos + step, signal.length);
      targetEngine.now = Duration(
        microseconds: baseUs + (end / sr * 1e6).round(),
      );
      targetRecorder.push(
        pcm16Bytes(Float64List.sublistView(signal, pos, end)),
      );
      await pumpEventQueue();
    }
  }

  Future<void> feed(Float64List signal, {int chunkMs = 50}) =>
      feedSignal(engine, recorder, signal, chunkMs: chunkMs);

  /// 一遍的标准弹奏:预备四下(拍 0..3)与正曲 16 点(拍 4..19)全部携带
  /// +80ms 链路延迟(物理事实:麦听到的每个声都晚一个链路延迟,校准
  /// 应把它整段吸收)。[missIndexes] 不弹;[wrongAt] 弹 G 和弦。
  Float64List standardPass({
    Set<int> missIndexes = const {},
    Set<int> wrongAt = const {},
    double periodMs = 750,
    double chainDelaySec = 0.08,
  }) {
    final signal = Float64List(scoringTestSampleRate * 30);
    void mix(Float64List src, double atSec) {
      final start = (atSec * scoringTestSampleRate).round();
      for (var i = 0; i < src.length && start + i < signal.length; i++) {
        signal[start + i] += src[i];
      }
    }

    for (var k = 0; k < 4; k++) {
      mix(
        strumBurst(atSec: 0, totalSamples: scoringTestSampleRate),
        k * periodMs / 1000 + chainDelaySec,
      );
    }
    final timeline = handle.timeline!;
    for (var i = 0; i < timeline.strums.length; i++) {
      if (missIndexes.contains(i)) continue;
      final strum = timeline.strums[i];
      final atSec =
          (4 + strum.barIndex * 4 + strum.slotInBar / 2) * periodMs / 1000 +
          chainDelaySec;
      mix(
        wrongAt.contains(i)
            ? chordBurst(
                const [55, 62, 67, 71],
                atSec: 0,
                totalSamples: scoringTestSampleRate,
              )
            : chordBurst(
                strum.chord == 'C'
                    ? const [60, 64, 67, 72]
                    : const [57, 60, 64, 69],
                atSec: 0,
                totalSamples: scoringTestSampleRate,
              ),
        atSec,
      );
    }
    return signal;
  }

  test('权限拒:startSession false + 错误文案,不接评分嘀声', () async {
    recorder.granted = false;
    final ok = await controller().startSession();
    expect(ok, isFalse);
    expect(container.read(practiceScoringProvider).error, isNotNull);
    expect(handle.scoringTicksCalls, isEmpty);
  });

  test('开麦失败:startSession false + 错误文案', () async {
    recorder.startOk = false;
    final ok = await controller().startSession();
    expect(ok, isFalse);
    expect(container.read(practiceScoringProvider).error, isNotNull);
  });

  test('完整会话:预备校准吸收 +80ms 偏移,全曲判准,接线拆净', () async {
    armHandle();
    expect(await controller().startSession(), isTrue);
    expect(handle.scoringTicksCalls, [true]);
    expect(
      container.read(practiceScoringProvider).status,
      ScoringStatus.listening,
    );

    controller().onPassStart();
    await feed(standardPass());

    // 曲末:跟练控制器先停(时间轴清空),评分再收尾(与页面同序)。
    handle.closeSession();
    controller().finishSession();

    final state = container.read(practiceScoringProvider);
    expect(state.status, ScoringStatus.finished);
    expect(state.error, isNull);
    expect(handle.scoringTicksCalls, [true, false]);

    final report = state.report!;
    expect(report.result.total, 16);
    expect(report.result.matched, 16, reason: '+80ms 偏移被预备校准吸收');
    expect(report.result.onTime, 16);
    expect(report.result.accuracy, 1.0);
    expect(report.spots, hasLength(16), reason: '时间轴缓存自取,报告轨道完整');
  });

  test('校准采不到:退回持久化值(override 130ms)', () async {
    final parts = scoringTestContainer(latencyMs: 130);
    addTearDown(parts.container.dispose);
    final c2 = parts.container.read(practiceScoringProvider.notifier);
    parts.handle.timeline = compileTimeline(
      chart: practiceFixtureChart,
      pattern: builtinStrumPatterns.first,
      bpm: 80,
    );
    expect(await c2.startSession(), isTrue);

    // 预备期静默(校准采不到);正曲噪声扫弦 +130ms 偏移(恰为持久化值)。
    c2.onPassStart();
    final signal = Float64List(scoringTestSampleRate * 30);
    final burst = strumBurst(atSec: 0, totalSamples: scoringTestSampleRate);
    for (var i = 0; i < 16; i++) {
      final start = ((4.0 + i) * 0.75 + 0.13) * scoringTestSampleRate ~/ 1;
      for (var j = 0; j < burst.length; j++) {
        signal[start + j] += burst[j];
      }
    }
    await feedSignal(parts.engine, parts.recorder, signal);
    parts.handle.closeSession();
    c2.finishSession();

    final report = parts.container.read(practiceScoringProvider).report!;
    expect(report.result.matched, 16, reason: '持久化 130ms 补掉偏移');
    expect(report.result.onTime, 16);
  });

  test('暂停挂起:挂起期弹的不收(判漏),恢复后照常判', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();

    // 预备 + 前 8 点(拍 4..11,信号 0..9s)。
    await feed(slice(standardPass(), 0, 12 * 0.75));

    controller().onPause();
    expect(container.read(practiceScoringProvider).suspended, isTrue);

    // 挂起期弹的(拍 12..14):不进 onset。
    await feed(slice(standardPass(), 12 * 0.75, 15 * 0.75));

    controller().onResume();
    expect(container.read(practiceScoringProvider).suspended, isFalse);
    await feed(slice(standardPass(), 15 * 0.75, 21 * 0.75));

    handle.closeSession();
    controller().finishSession();

    final report = container.read(practiceScoringProvider).report!;
    expect(report.result.total, 16);
    expect(report.result.missed, 3, reason: '挂起期弹的 3 点判漏');
    expect(report.result.matched, 13);
  });

  test('循环清零:第二遍只弹一半,报告只反映第二遍', () async {
    armHandle();
    await controller().startSession();

    controller().onPassStart();
    await feed(standardPass());

    // 循环重启:真实流里跟练控制器 stop→start 重锚 t0=当前引擎时刻,
    // 假柄同步挪锚(音频继续从新遍的拍 0 弹起)。
    handle.anchor = engine.engineTime();
    controller().onPassStart(); // 清零重校准
    await feed(standardPass(missIndexes: {8, 9, 10, 11, 12, 13, 14, 15}));

    handle.closeSession();
    controller().finishSession();

    final report = container.read(practiceScoringProvider).report!;
    expect(report.result.total, 16, reason: '只反映最后一遍,不叠加');
    expect(report.result.matched, 8);
    expect(report.result.missed, 8);
  });

  test('变速 50%:后半拍周期翻倍,按各自检出周期折秒照样判准', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();

    // 前半原速(拍 4..11);中段变速(会话柄 periodMs 翻倍)。
    await feed(slice(standardPass(), 0, 12 * 0.75));

    handle.periodMs = 1500; // 页面 setSpeed(0.5) 的等效现场
    await feed(slice(standardPass(periodMs: 1500), 12 * 0.75, 32 * 1.5));

    handle.closeSession();
    controller().finishSession();

    final report = container.read(practiceScoringProvider).report!;
    expect(report.result.matched, 16, reason: '拍域守恒:变速段按新周期折秒');
    expect(report.result.onTime, 16);
  });

  test('「错」:弹了别的和弦 → wrong;滑块重算不丢', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();
    await feed(standardPass(wrongAt: {5}));
    handle.closeSession();
    controller().finishSession();

    final report = container.read(practiceScoringProvider).report!;
    expect(report.result.wrong, 1, reason: '点 5 弹了 G,目标是 C');
    expect(report.spots[5].judgment, StrumJudgment.wrong);
    expect(report.result.matched, 16, reason: '错也算听到');

    controller().setReportLatencySec(0.0);
    final recomputed = container.read(practiceScoringProvider).report!;
    expect(recomputed.result.wrong, 1, reason: '重算走色度缓存,判定不丢');
  });

  test('重听:命中点装载一次性音源,再听卸掉上一条;漏点听期望位', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();
    await feed(standardPass(missIndexes: {3}));
    handle.closeSession();
    controller().finishSession();

    await controller().replay(0);
    expect(
      engine.loadedKeys.where((k) => k.startsWith('scoring-replay')),
      hasLength(1),
    );
    expect(engine.scheduleLog, hasLength(1), reason: 'loadMem 后预定播放');

    await controller().replay(3); // 漏点:期望位置取窗
    expect(engine.unloadedKeys, hasLength(1), reason: '新听旧卸');
    expect(
      engine.loadedKeys.where((k) => k.startsWith('scoring-replay')),
      hasLength(2),
    );
    expect(engine.scheduleLog, hasLength(2));
  });

  test('abort:弃评回 idle、拆接线、无报告、麦停过', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();
    await feed(slice(standardPass(), 0, 3 * 0.75));

    controller().abort();
    await pumpEventQueue(); // 停麦 fire-and-forget,让善后微任务跑完。
    final state = container.read(practiceScoringProvider);
    expect(state.status, ScoringStatus.idle);
    expect(state.report, isNull);
    expect(state.liveVerdicts, isNull, reason: '弃评无残留:实时判定一并清');
    expect(handle.scoringTicksCalls, [true, false]);
    expect(recorder.stopCount, 1);
  });

  test('一开播就停(无 onset):不弹报告直接回 idle', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();

    // 只喂半秒静默(预备第一声还没弹就停了):无任何 onset。
    await feed(Float64List(scoringTestSampleRate ~/ 2));
    handle.closeSession();
    controller().finishSession();

    final state = container.read(practiceScoringProvider);
    expect(state.status, ScoringStatus.idle, reason: '无可评数据不弹报告');
    expect(state.report, isNull);
  });

  test('closeReport:看完即弃回 idle,开关保留', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();
    await feed(standardPass());
    handle.closeSession();
    controller().finishSession();
    expect(
      container.read(practiceScoringProvider).status,
      ScoringStatus.finished,
    );

    controller().closeReport();
    final state = container.read(practiceScoringProvider);
    expect(state.status, ScoringStatus.idle);
    expect(state.report, isNull);
    expect(state.liveVerdicts, isNull, reason: '看完即弃:实时判定一并清');
  });

  // ── 实时判定反馈(工单 36)────────────────────────────────────

  test('实时判定:onset 到达即着色,弹到的判准、未到的不着色', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();
    final atStart = container.read(practiceScoringProvider).liveVerdicts!;
    expect(atStart, everyElement(isNull), reason: '开跑清零:全部未定');

    // 弹预备 4 下 + 正曲点 0..3(信号 0..6.0s;点 4 在 6.08s 未入窗)。
    await feed(slice(standardPass(), 0, 6.0));

    final live = container.read(practiceScoringProvider).liveVerdicts!;
    expect(live, hasLength(16), reason: '谱序,与报告 verdicts 同序');
    expect(
      live.take(4),
      everyElement(StrumJudgment.onTime),
      reason: '弹到的点当场着色',
    );
    expect(live.sublist(4), everyElement(isNull), reason: '未弹到的点不着色');
  });

  test('漏拍:弹奏中的空点随下次 onset 补判漏;末点靠轮询查询路径', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();

    // 点 1 不弹,弹到点 3(信号 0..6.0):点 2 的 onset 到达时点 1 的
    // 容差窗早已关,重跑顺带补判漏。
    await feed(slice(standardPass(missIndexes: {1}), 0, 6.0));
    var live = container.read(practiceScoringProvider).liveVerdicts!;
    expect(live[0], StrumJudgment.onTime);
    expect(live[1], StrumJudgment.missed, reason: '窗关未见 onset → 灰');
    expect(live[2], StrumJudgment.onTime);

    // 末点 15 不弹且之后再无 onset:没有任何到达触发,漏判挂轮询。
    await feed(slice(standardPass(missIndexes: {1, 15}), 6.0, 15.0));
    live = container.read(practiceScoringProvider).liveVerdicts!;
    expect(live[15], isNull, reason: '最后一次重跑时末窗未关');

    controller().pollLive();
    live = container.read(practiceScoringProvider).liveVerdicts!;
    expect(live[15], StrumJudgment.missed, reason: '轮询查询路径:窗关判漏');
    expect(live.take(15), everyElement(isNotNull), reason: '其余点判定不受影响');
  });

  test('「错」滞后:时机色先亮,色度窗收满翻红;实时与报告逐点一致', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();

    // 点 5 弹 G(目标是 C)。喂到点 5 检出、色度窗未收满(窗尾 ~7.13s)。
    await feed(slice(standardPass(wrongAt: {5}), 0, 7.0));
    var live = container.read(practiceScoringProvider).liveVerdicts!;
    expect(live[5], StrumJudgment.onTime, reason: '时机判定先行:色度未收满不判错');

    // 引擎钟推过色度窗尾,轮询查询路径触发升格重跑。
    engine.now = const Duration(milliseconds: 7300);
    controller().pollLive();
    live = container.read(practiceScoringProvider).liveVerdicts!;
    expect(live[5], StrumJudgment.wrong, reason: '色度窗收满:错的点翻红');

    // 弹完后收尾:实时判定与曲末报告逐点一致(同算法同源,不翻案)。
    await feed(slice(standardPass(wrongAt: {5}), 7.3, 21.0));
    handle.closeSession();
    controller().finishSession();
    final report = container.read(practiceScoringProvider).report!;
    live = container.read(practiceScoringProvider).liveVerdicts!;
    expect(report.spots[5].judgment, StrumJudgment.wrong);
    for (var i = 0; i < report.spots.length; i++) {
      expect(live[i], report.spots[i].judgment, reason: '点 $i 实时与报告一致');
    }
  });

  test('暂停冻结:挂起期轮询不推进判定(窗已关也不翻灰)', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();

    // 点 5 不弹:窗尾 6.75+0.08+0.23 ≈ 7.06s。喂到 6.9 暂停——窗还没关。
    await feed(slice(standardPass(missIndexes: {5}), 0, 6.9));
    final frozen = container.read(practiceScoringProvider).liveVerdicts!;
    expect(frozen[5], isNull, reason: '暂停前窗未关,未判');

    controller().onPause();
    engine.now = const Duration(seconds: 8);
    controller().pollLive(); // 轮询照跑,但挂起期不推进判定
    expect(
      container.read(practiceScoringProvider).liveVerdicts,
      same(frozen),
      reason: '挂起期冻结:窗已过也不翻灰',
    );
  });

  test('恢复后照常推进:色度升格与着色续跑,与报告一致', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();

    await feed(slice(standardPass(wrongAt: {5}), 0, 7.0));
    controller().onPause();
    final frozen = container.read(practiceScoringProvider).liveVerdicts!;
    expect(frozen[5], StrumJudgment.onTime, reason: '时机色已亮,色度未收满');

    controller().onResume();
    await feed(slice(standardPass(wrongAt: {5}), 7.0, 21.0));
    controller().pollLive();
    final live = container.read(practiceScoringProvider).liveVerdicts!;
    expect(live[5], StrumJudgment.wrong, reason: '恢复后色度窗已过,升格照常');
    expect(
      [...live.take(5), ...live.sublist(6)],
      everyElement(StrumJudgment.onTime),
    );

    handle.closeSession();
    controller().finishSession();
    final report = container.read(practiceScoringProvider).report!;
    for (var i = 0; i < report.spots.length; i++) {
      expect(live[i], report.spots[i].judgment, reason: '点 $i 恢复后仍与报告一致');
    }
  });

  test('循环清零:onPassStart 判定列表清空重计', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();
    await feed(slice(standardPass(), 0, 6.0));
    expect(
      container.read(practiceScoringProvider).liveVerdicts!,
      anyElement(isNotNull),
    );

    handle.anchor = engine.engineTime();
    controller().onPassStart();
    final live = container.read(practiceScoringProvider).liveVerdicts!;
    expect(live, hasLength(16));
    expect(live, everyElement(isNull), reason: '循环重开清零');
  });

  test('变速 50% 中途:实时判定照常着色(拍域折秒,零改动)', () async {
    armHandle();
    await controller().startSession();
    controller().onPassStart();

    await feed(slice(standardPass(), 0, 12 * 0.75));
    handle.periodMs = 1500; // 页面 setSpeed(0.5) 的等效现场
    await feed(slice(standardPass(periodMs: 1500), 12 * 0.75, 32 * 1.5));
    controller().pollLive();

    final live = container.read(practiceScoringProvider).liveVerdicts!;
    expect(live, everyElement(StrumJudgment.onTime), reason: '变速段按新周期折秒,照常判准');
  });
}
