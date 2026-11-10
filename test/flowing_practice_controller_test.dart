import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/score/reference_score.dart';
import 'package:ukeflow/features/play/flowing/flowing_practice_controller.dart';

/// 流水谱跟练控制器:装载/播放/暂停/跳转/曲末的会话状态机,
/// 示范声与时间表同源(ADR-0005)。引擎一律 FakeAudioEngine;时间用
/// 真实短延迟驱动 40ms 轮询(引擎时钟手动推进,两者解耦)。
void main() {
  late FakeAudioEngine engine;
  late ProviderContainer container;

  /// 小合成谱:休止@0(0.5s)、单音@0.5(midi69)、和弦@1.0(69+73,
  /// 其中 73 为延音尾音→剔除)、纯延音@1.5(整组剔除,无攻击)、
  /// 双音和弦@2.0(69+73 均真弹)。曲长 6s。
  ReferenceScore score() {
    RefNote note(int id, int midi, {bool tie = false, int origin = -1}) =>
        RefNote(
          id: id,
          stringNo: 1,
          fret: 0,
          midi: midi,
          isTieDestination: tie,
          tieOriginNoteId: origin >= 0 ? origin : null,
          isNaturalHarmonic: false,
          hasSlideOut: false,
          sourceString: 4,
        );
    RefEvent event(int id, double start, double dur, List<RefNote> notes) =>
        RefEvent(
          id: id,
          measureIndex: 0,
          voiceIndex: 0,
          startSeconds: start,
          durationSeconds: dur,
          notes: notes,
          chord: null,
          brushType: 0,
          durationValue: 8,
          dots: 0,
          startTick: 0,
        );
    return ReferenceScore(
      title: '调度测试谱',
      artist: '',
      sourceTempo: 80,
      startingTempo: 80,
      keySignature: 0,
      tuning1to4: [69, 64, 60, 67],
      measures: [
        for (var i = 0; i < 2; i++)
          RefMeasure(
            index: i,
            startSeconds: i * 3,
            durationSeconds: 3,
            tempo: 80,
            numerator: 4,
            denominator: 4,
            section: null,
          ),
      ],
      events: [
        event(1, 0, 0.5, const []),
        event(2, 0.5, 0.5, [note(100, 69)]),
        event(3, 1.0, 0.5, [note(200, 69), note(201, 73, tie: true, origin: 100)]),
        event(4, 1.5, 0.5, [note(202, 69, tie: true, origin: 200)]),
        event(5, 2.0, 1.0, [note(300, 69), note(301, 73)]),
      ],
      durationSeconds: 6,
    );
  }

  setUp(() {
    engine = FakeAudioEngine();
    container = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(engine),
        flowingScoreLoaderProvider.overrideWithValue(() async => score()),
      ],
    );
    // listen 订阅钉活 provider:Riverpod 3 无监听即回收,断续 read 会被
    // 销毁重建,状态与调度全断。
    container.listen(flowingPracticeProvider, (_, _) {});
    addTearDown(container.dispose);
  });

  FlowingPracticeController controller() =>
      container.read(flowingPracticeProvider.notifier);

  FlowingPracticeState state() => container.read(flowingPracticeProvider);

  /// 等装载完成(转换 + KS 合成注入,毫秒级)。
  Future<void> pumpLoad() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  /// 等 n 轮 40ms 轮询。
  Future<void> pumpPolls({int rounds = 3}) =>
      Future<void>.delayed(Duration(milliseconds: 40 * rounds + 10));

  test('buildAttacks:休止无攻击、延音尾音剔除、纯延音事件整组消失', () {
    final attacks = FlowingPracticeController.buildAttacks(score());
    // 攻击 = 0.5s(单音)、1.0s(和弦剔尾音)、2.0s(双音);@1.5 纯延音消失。
    expect(attacks.length, 3);
    expect(attacks[0].time, const Duration(milliseconds: 500));
    expect(attacks[0].freqs, [closeTo(440, 1e-9)]);
    expect(attacks[1].time, const Duration(milliseconds: 1000));
    expect(attacks[1].freqs, [closeTo(440, 1e-9)], reason: '延音尾音 201 剔除');
    expect(attacks[2].time, const Duration(milliseconds: 2000));
    expect(attacks[2].freqs.length, 2);
  });

  test('buildAttacks:真谱攻击数 = 非纯延音事件数,首攻在首声 2.25s', () {
    final raw = File('assets/scores/sky-city-guistudy.json').readAsStringSync();
    final real = buildReferenceScore(jsonDecode(raw), pageTempoBpm: 80);
    final attacks = FlowingPracticeController.buildAttacks(real);
    final expected = real.events
        .where((e) => e.notes.any((n) => !n.isTieDestination))
        .length;
    expect(attacks.length, expected);
    expect(attacks.first.time.inMilliseconds, 2250);
    for (final attack in attacks) {
      expect(attack.freqs, isNotEmpty);
    }
  });

  test('装载:就绪后音源已预注入(全部攻击音高可同步查取)', () async {
    await pumpLoad();
    expect(state().status, FlowingStatus.ready);
    final pluck = container.read(pluckPlayerProvider);
    final freqs = FlowingPracticeController.buildAttacks(score())
        .expand((a) => a.freqs);
    for (final freq in freqs) {
      expect(pluck.loadedSound(freq), isNotNull, reason: 'freq=$freq 未注入');
    }
  });

  test('播放:攻击按 t0+时刻预定,延音不重拨,和弦同刻一组两声', () async {
    await pumpLoad();
    engine.now = const Duration(seconds: 1);
    await controller().play();
    // t0=1s:0.5s 攻击在 1.5s,首过窗 [0.96, 1.4) 未到。
    await pumpPolls();
    expect(
      engine.scheduleLog.where((c) => c.time == const Duration(milliseconds: 1500)),
      isEmpty,
    );
    engine.advance(const Duration(milliseconds: 200));
    await pumpPolls();
    // 攻击@0.5 → 1.5s 预定一声(midi69);窗 [1.16,1.6) 只含它,
    // 攻击@1.0(2.0s)须等 now 越过 1.6s 才进窗。
    final at1500 = engine.scheduleLog
        .where((c) => c.time == const Duration(milliseconds: 1500))
        .toList();
    expect(at1500.length, 1);
    expect(at1500.single.key, contains('440'));
    expect(
      engine.scheduleLog
          .where((c) => c.time == const Duration(milliseconds: 2000)),
      isEmpty,
      reason: '2.0s 攻击此刻未进窗',
    );
    engine.advance(const Duration(milliseconds: 600));
    await pumpPolls();
    // 攻击@1.0 → 2.0s:和弦剔延音后仅一声。
    final at2000 = engine.scheduleLog
        .where((c) => c.time == const Duration(milliseconds: 2000))
        .toList();
    expect(at2000.length, 1);
    // 攻击@1.5 纯延音:2.5s 绝无声。
    expect(
      engine.scheduleLog
          .where((c) => c.time == const Duration(milliseconds: 2500)),
      isEmpty,
    );
    engine.advance(const Duration(milliseconds: 900));
    await pumpPolls();
    // 攻击@2.0 → 3.0s:双音和弦同刻两声(音高键不同)。
    final at3000 = engine.scheduleLog
        .where((c) => c.time == const Duration(seconds: 3))
        .toList();
    expect(at3000.length, 2);
    expect(at3000.map((c) => c.key).toSet().length, 2);
  });

  test('暂停:立静(在途+已响尾音全停),位置冻结;恢复不重放已消费攻击', () async {
    await pumpLoad();
    engine.now = const Duration(seconds: 1);
    await controller().play();
    engine.advance(const Duration(milliseconds: 800));
    await pumpPolls();
    expect(state().status, FlowingStatus.playing);
    controller().pause();
    expect(state().status, FlowingStatus.paused);
    // 冻结位置 = 引擎时刻 1.8s − 锚 t0 1s = 0.8s。
    expect(state().positionSeconds, closeTo(0.8, 1e-6));
    // 立静:scheduleLog 全部 stop。
    for (final call in engine.scheduleLog) {
      expect(call.stopped, isTrue, reason: '暂停残留未停声 ${call.key}@${call.time}');
    }
    // 恢复:从 0.8s 续跑,t0 重锚 = 新引擎时刻 − 0.8s。攻击@0.5 的绝对
    // 时刻(锚+0.5s)已落在恢复窗前 → 不重放;@1.0/@2.0 未消费,照常预定。
    final before = engine.scheduleLog.length;
    engine.advance(const Duration(milliseconds: 300));
    await controller().play();
    await pumpPolls();
    expect(state().status, FlowingStatus.playing);
    // 核心性质:任何 (音源键, 时刻) 组合至多预定一次——已响攻击绝不
    // 因重锚重建而二次发声。
    final seen = <String, int>{};
    for (final call in engine.scheduleLog) {
      final tag = '${call.key}@${call.time}';
      seen[tag] = (seen[tag] ?? 0) + 1;
    }
    for (final entry in seen.entries) {
      expect(entry.value, 1, reason: '攻击重复预定:${entry.key}');
    }
    expect(engine.scheduleLog.length, greaterThan(before),
        reason: '恢复后未消费攻击照常预定');
  });

  test('跳转:停声清旧、保持暂停;再播从新位置起,旧攻击不回放', () async {
    await pumpLoad();
    controller().play();
    engine.advance(const Duration(seconds: 2));
    await pumpPolls();
    controller().seek(5.5);
    expect(state().status, FlowingStatus.paused);
    expect(state().positionSeconds, 5.5);
    controller().play();
    await pumpPolls();
    expect(state().status, FlowingStatus.playing);
    // 新 t0 = now − 5.5s;所有攻击(≤2.0s)都在锚前过窗 → 不预定新声。
    final callsAfterSeek = engine.scheduleLog
        .where((c) => c.time >= const Duration(seconds: 2))
        .length;
    controller().pause();
    controller().seek(0);
    expect(state().status, FlowingStatus.paused);
    expect(state().positionSeconds, 0);
    // 以上只为断言旧攻击不回放:全曲仅两处 3.0s 攻击来自播放段的预定。
    expect(callsAfterSeek, lessThanOrEqualTo(2));
  });

  test('曲末:到点触发 finished,终点保留,尾音不被截停', () async {
    await pumpLoad();
    await controller().play();
    engine.advance(const Duration(seconds: 7));
    await pumpPolls(rounds: 2);
    expect(state().status, FlowingStatus.finished);
    expect(state().positionSeconds, 6);
  });

  test('慢放:0.5 倍攻击时刻翻倍,音高键不变(KS 节距照旧)', () async {
    await pumpLoad();
    controller().setSpeed(0.5);
    expect(state().speed, 0.5);
    engine.now = const Duration(seconds: 1);
    await controller().play(); // t0 = 1s(从 0 起)。
    // 推进 0.7s → 窗 [1.26, 2.1):慢放时刻 2.0s 进窗;若速度被无视,
    // 原速时刻 1.5s 会同窗预定——其缺席即缩放生效之证。
    engine.advance(const Duration(milliseconds: 700));
    await pumpPolls();
    // 音乐 0.5s 的攻击 → 引擎 t0+1.0s = 2.0s 响。
    final at2000 = engine.scheduleLog
        .where((c) => c.time == const Duration(milliseconds: 2000))
        .toList();
    expect(at2000.length, 1);
    expect(at2000.single.key, contains('440'), reason: '音高键与原速完全一致');
    // 原速时刻(t0+0.5s=1.5s)绝无预定——时刻轴确实整体缩放。
    expect(
      engine.scheduleLog
          .where((c) => c.time == const Duration(milliseconds: 1500)),
      isEmpty,
    );
  });

  test('慢放:曲末按速度推迟到引擎 12s,finished 音乐位置仍是曲长', () async {
    await pumpLoad();
    controller().setSpeed(0.5);
    await controller().play();
    engine.advance(const Duration(seconds: 7));
    await pumpPolls();
    expect(state().status, FlowingStatus.playing, reason: '引擎 7s 音乐才 3.5s');
    expect(controller().currentSeconds(), closeTo(3.5, 1e-6));
    engine.advance(const Duration(seconds: 6));
    await pumpPolls(rounds: 2);
    expect(state().status, FlowingStatus.finished);
    expect(state().positionSeconds, 6);
  });

  test('变速即切:位置连续无突跳,推进斜率确为新速度', () async {
    await pumpLoad();
    engine.now = const Duration(seconds: 1);
    await controller().play(); // t0=1s 原速。
    engine.advance(const Duration(milliseconds: 800));
    await pumpPolls(); // 攻击@0.5(引擎 1.5s)已响。
    final musicBefore = controller().currentSeconds();
    controller().setSpeed(0.75);
    // 重锚后当前音乐秒逐微秒连续,positionSeconds 冻结在同一处。
    expect(controller().currentSeconds(), closeTo(musicBefore, 1e-6));
    expect(state().positionSeconds, closeTo(musicBefore, 1e-6));
    // 引擎推进 1s,音乐只走 0.75s。
    engine.advance(const Duration(seconds: 1));
    expect(controller().currentSeconds(), closeTo(musicBefore + 0.75, 1e-6));
  });

  test('变速即切:已响攻击不重放,任何 (音源,时刻) 至多预定一次', () async {
    await pumpLoad();
    engine.now = const Duration(seconds: 1);
    await controller().play();
    engine.advance(const Duration(milliseconds: 800));
    await pumpPolls();
    controller().setSpeed(0.75);
    engine.advance(const Duration(milliseconds: 400));
    await pumpPolls();
    final seen = <String, int>{};
    for (final call in engine.scheduleLog) {
      final tag = '${call.key}@${call.time}';
      seen[tag] = (seen[tag] ?? 0) + 1;
    }
    for (final entry in seen.entries) {
      expect(entry.value, 1, reason: '变速重放:${entry.key}');
    }
    // 新锚下未消费攻击照常预定:音乐 1.0s → 引擎 733333μs+1333333μs
    // = 2066666μs(0.75 缩放的精确舍入值)。
    expect(
      engine.scheduleLog
          .where((c) => c.time == const Duration(microseconds: 2066666)),
      isNotEmpty,
    );
  });

  test('静止切速只换倍率,再播按新速度锚定', () async {
    await pumpLoad();
    controller().seek(2.0);
    controller().setSpeed(0.75);
    expect(state().speed, 0.75);
    engine.now = const Duration(seconds: 5);
    await controller().play(); // t0 = 5 − 2/0.75。
    await pumpPolls();
    // 双音和弦@音乐 2.0s → 引擎 t0+2.6667 = 恰好 5.0s,首过即进窗。
    final at5000 = engine.scheduleLog
        .where((c) => c.time == const Duration(seconds: 5))
        .toList();
    expect(at5000.length, 2, reason: '和弦两声同刻');
  });

  test('速度白名单:非法值抛 ArgumentError,状态不变', () {
    expect(() => controller().setSpeed(0.9), throwsArgumentError);
    expect(state().speed, 1.0);
  });
}
