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
    // 旧用例默认关数拍(票03 专测自行开启):起播预备会延迟翻播放状态。
    container
        .read(flowingPracticeProvider.notifier)
        .setCountOptions(countInEnabled: false);
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

  /// 循环测试脚手架:窗 [0, 2.2](全窗含攻击 0.5/1.0/2.0),静止态用
  /// seek 定位标记(标记读静态位),播放锚 t0=0。
  Future<void> pumpLoopWindow() async {
    await pumpLoad();
    controller().seek(0);
    controller().markLoopStart();
    controller().seek(2.2);
    controller().markLoopEnd();
    expect(state().activeLoop!.start, 0);
    expect(state().activeLoop!.end, closeTo(2.2, 1e-9));
    controller().seek(0);
    engine.now = Duration.zero;
    await controller().play();
  }

  /// 步进推进:每步 350ms(< lookahead 400ms,相邻窗重叠),攻击绝不
  /// 被迟到容差跳过。
  Future<void> pumpSteps(int steps) async {
    for (var i = 0; i < steps; i++) {
      engine.advance(const Duration(milliseconds: 350));
      await pumpPolls(rounds: 1);
    }
  }

  test('循环:越 B 无缝回 A——下轮攻击跨缝预定,旧轮尾音在回跳点截停', () async {
    await pumpLoopWindow();
    await pumpSteps(7); // now=2.45s:越 wrap 2.2,第二轮 0.5@2.7 已进窗。
    // 第一轮:0.5/1.0/2.0 各一声;第二轮 0.5 → 2.2+0.5 = 2.7 跨缝预定。
    final at2700 = engine.scheduleLog
        .where((c) => c.time == const Duration(milliseconds: 2700))
        .toList();
    expect(at2700.length, 1, reason: '第二轮首攻跨缝预定');
    // 旧轮 2.0s 的声在回跳点截停(不叠上一轮余音);第二轮 2.7s 声保留。
    final playedAt2000 =
        engine.scheduleLog.where((c) => c.time == const Duration(seconds: 2));
    expect(playedAt2000, isNotEmpty);
    expect(playedAt2000.every((c) => c.stopped), isTrue, reason: '旧轮尾音截停');
    expect(at2700.single.stopped, isFalse, reason: '新轮 A 点声保留');
    // 第二轮 1.0 → 3.2 未进窗,不预定。
    expect(
      engine.scheduleLog
          .where((c) => c.time == const Duration(milliseconds: 3200)),
      isEmpty,
    );
    // 视图红线模回跳:raw=2.45 → 2.45 % 2.2 = 0.25。
    expect(controller().currentSeconds(), closeTo(0.25, 1e-6));
  });

  test('循环:三轮推进无漏无重,窗内攻击每轮恰预定一次', () async {
    await pumpLoopWindow();
    await pumpSteps(16); // now=5.6s:近三整轮。
    // 攻击 m∈{0.5,1.0,2.0} 第 k 轮绝对时刻 = 2.2k + m;≤ now+lookahead
    // (6.0) 的都该预定且恰一次。
    final expected = <int>[];
    for (final m in const [500, 1000, 2000]) {
      for (var k = 0; k < 3; k++) {
        final t = 2200 * k + m;
        if (t <= 6000) expected.add(t);
      }
    }
    // 期望 = (绝对时刻 → 声数):2.0s 攻击是双音和弦,一轮两声。
    final expectedVoices = <int, int>{};
    for (final m in const [500, 1000, 2000]) {
      final voices = m == 2000 ? 2 : 1;
      for (var k = 0; k < 3; k++) {
        final t = 2200 * k + m;
        if (t <= 6000) expectedVoices[t] = voices;
      }
    }
    expect(expectedVoices.length, 8);
    final counts = <int, int>{};
    for (final call in engine.scheduleLog) {
      counts[call.time.inMilliseconds] =
          (counts[call.time.inMilliseconds] ?? 0) + 1;
    }
    expect(engine.scheduleLog.length, 10,
        reason: '循环模式窗外(曲末段)攻击绝不预定');
    for (final entry in expectedVoices.entries) {
      expect(counts[entry.key] ?? 0, entry.value,
          reason: '攻击@${entry.key} 应恰 ${entry.value} 声,实际 ${counts[entry.key] ?? 0}');
    }
  });

  test('循环中暂停恢复:位置冻结窗内,恢复不重放已消费攻击', () async {
    await pumpLoopWindow();
    engine.advance(const Duration(milliseconds: 700));
    await pumpPolls(); // 1.0 攻击进窗预定;0.5 已越容差跳过。
    controller().pause();
    expect(state().positionSeconds, closeTo(0.7, 1e-6));
    expect(state().status, FlowingStatus.paused);
    engine.advance(const Duration(milliseconds: 300));
    await controller().play(); // 从 0.7 续,重锚 t0 = now − 0.7。
    await pumpPolls();
    final seen = <String, int>{};
    for (final call in engine.scheduleLog) {
      final tag = '${call.key}@${call.time}';
      seen[tag] = (seen[tag] ?? 0) + 1;
    }
    for (final entry in seen.entries) {
      expect(entry.value, 1, reason: '循环恢复重放:${entry.key}');
    }
  });

  test('播放中挂循环:位置恰在 B 上按模回跳进窗,重锚无跳变', () async {
    await pumpLoad();
    await controller().play(); // t0=0 原速。
    engine.advance(const Duration(seconds: 3));
    await pumpPolls();
    controller().markLoopStart(); // A=3.0(当前位)。
    engine.advance(const Duration(milliseconds: 500));
    await pumpPolls();
    controller().markLoopEnd(); // B=3.5,当前位恰在 B → 回跳 A=3.0。
    expect(state().activeLoop!.start, closeTo(3.0, 1e-9));
    expect(state().activeLoop!.end, closeTo(3.5, 1e-9));
    // 重锚后可听位 = 3.0 + (3.5−3.0)%0.5 = 3.0,位置连续无跳变。
    expect(controller().currentSeconds(), closeTo(3.0, 1e-6));
    engine.advance(const Duration(milliseconds: 400));
    await pumpPolls();
    // 窗 [3.0,3.5] 内无攻击:无声预定、无重复、曲末不触发。
    expect(state().status, FlowingStatus.playing);
    final seen = <String, int>{};
    for (final call in engine.scheduleLog) {
      final tag = '${call.key}@${call.time}';
      seen[tag] = (seen[tag] ?? 0) + 1;
    }
    for (final entry in seen.entries) {
      expect(entry.value, 1, reason: '挂循环重放:${entry.key}');
    }
  });

  test('清循环:从可听位继续线性推进无跳变;再播窗外起点不吸附', () async {
    await pumpLoopWindow();
    await pumpSteps(8); // now=2.8,已回跳:可听位 = 2.8 % 2.2 = 0.6。
    expect(controller().currentSeconds(), closeTo(0.6, 1e-6));
    controller().clearLoop();
    expect(state().activeLoop, isNull);
    expect(controller().currentSeconds(), closeTo(0.6, 1e-6),
        reason: '清除重锚,可听位连续');
    controller().pause();
    controller().seek(4.0);
    await controller().play();
    engine.advance(const Duration(milliseconds: 200));
    await pumpPolls();
    expect(controller().currentSeconds(), closeTo(4.2, 1e-6),
        reason: '无循环时窗外起点不吸附');
  });

  test('数四下:起播先预备,曲谱位置冻结不推进,数完自动起播', () async {
    await pumpLoad();
    controller().setCountOptions(countInEnabled: true);
    engine.now = const Duration(seconds: 1);
    await controller().play();
    expect(state().status, FlowingStatus.counting);
    expect(state().positionSeconds, 0);
    expect(controller().currentSeconds(), 0, reason: '预备期红线冻结');
    // 4 记预备 tick:首拍 1.12s(now+120ms lead),拍长 750ms(80bpm)。
    expect(
      engine.scheduleLog
          .where((c) => c.key.contains('tick'))
          .map((c) => c.time)
          .toList(),
      [
        const Duration(milliseconds: 1120),
        const Duration(milliseconds: 1870),
        const Duration(milliseconds: 2620),
        const Duration(milliseconds: 3370),
      ],
    );
    // 倒计数:预备第 0.9s 处应在第 2 拍。
    engine.advance(const Duration(milliseconds: 900));
    expect(controller().countBeatNow(), 2);
    // 预备期位置不动(不推进红线、不计入时长)。
    await pumpPolls();
    expect(state().status, FlowingStatus.counting);
    expect(controller().currentSeconds(), 0);
    // 数完(引擎钟过 countEnd=4.12s)自动起播,t0 锚在起点。
    engine.advance(const Duration(seconds: 4));
    await pumpPolls();
    expect(state().status, FlowingStatus.playing);
    expect(state().t0, isNotNull);
    expect(controller().currentSeconds(), closeTo(0, 1e-6));
    expect(controller().countBeatNow(), isNull);
  });

  test('数四下:拍长随慢放缩放(0.5 倍 tick 间距翻倍)', () async {
    await pumpLoad();
    controller().setCountOptions(countInEnabled: true);
    controller().setSpeed(0.5);
    engine.now = const Duration(seconds: 1);
    await controller().play();
    expect(
      engine.scheduleLog
          .where((c) => c.key.contains('tick'))
          .map((c) => c.time.inMilliseconds)
          .toList(),
      [1120, 2620, 4120, 5620],
      reason: '拍长 750ms/0.5 = 1500ms',
    );
    expect(state().status, FlowingStatus.counting);
  });

  test('暂停续播不重数;seek 换段与曲末重开重数', () async {
    await pumpLoad();
    controller().setCountOptions(countInEnabled: true);
    engine.now = Duration.zero;
    await controller().play();
    engine.advance(const Duration(seconds: 5));
    await pumpPolls();
    expect(state().status, FlowingStatus.playing);
    controller().pause();
    final ticksBefore =
        engine.scheduleLog.where((c) => c.key.contains('tick')).length;
    await controller().play(); // 暂停续播:不重数(codex 同款)。
    expect(state().status, FlowingStatus.playing);
    expect(engine.scheduleLog.where((c) => c.key.contains('tick')).length,
        ticksBefore);
    controller().pause();
    controller().seek(1.0);
    await controller().play(); // 换段:重数。
    expect(state().status, FlowingStatus.counting);
    engine.advance(const Duration(seconds: 4));
    await pumpPolls();
    expect(state().status, FlowingStatus.playing);
  });

  test('数拍开关关掉:直接起播无预备 tick', () async {
    await pumpLoad(); // setUp 默认关数拍。
    await controller().play();
    expect(state().status, FlowingStatus.playing);
    expect(engine.scheduleLog.where((c) => c.key.contains('tick')), isEmpty);
  });

  test('循环每轮数四下:回跳 4 记 tick,下一轮后移 gap,红线 gap 段定在 A', () async {
    await pumpLoopWindow(); // 窗 [0, 2.2]。
    controller().setCountOptions(countPerLoop: true);
    await controller().play(); // countIn 关,直接播。
    await pumpSteps(7); // now=2.45,过 wrap 2.2(wrap 在 2.1 轮询提前触发)。
    // 4 记轮间 tick @ wrap 2.2 + j×750ms。
    expect(
      engine.scheduleLog
          .where((c) => c.key.contains('tick'))
          .map((c) => c.time.inMilliseconds)
          .toList(),
      [2200, 2950, 3700, 4450],
    );
    // 视图:gap 段(曲谱时间不动)红线定在 A=0;倒计数第 1 拍。
    expect(controller().currentSeconds(), closeTo(0, 1e-6));
    expect(controller().countBeatNow(), 1);
    // 继续推进过 gap:下一轮 0.5 → 2.2 + 3.0(gap=4拍) + 0.5 = 5.7s,
    // now=5.6 进 lookahead 窗预定;红线重新起走(A + 0.4)。
    await pumpSteps(9); // now=5.6。
    expect(
      engine.scheduleLog.where((c) =>
          c.time == const Duration(milliseconds: 5700) &&
          !c.key.contains('tick')),
      isNotEmpty,
    );
    expect(controller().currentSeconds(), closeTo(0.4, 1e-6));
    expect(controller().countBeatNow(), isNull, reason: 'gap 段已过,回到正曲段');
  });

  // —— 票04 声音分路 ——
  // 测试谱节拍表:两小节各 3s@80bpm → 拍点 0/750/1500/2250 + 3000/3750/
  // 4500/5250,小节头(0/3000)重拍 strong。

  test('buildBeats:小节拍速均分四分拍,小节头重拍', () {
    final beats = FlowingPracticeController.buildBeats(score());
    expect(beats.map((b) => b.time.inMilliseconds).toList(),
        [0, 750, 1500, 2250, 3000, 3750, 4500, 5250]);
    expect(
      beats.where((b) => b.accent).map((b) => b.time.inMilliseconds).toList(),
      [0, 3000],
    );
  });

  test('节拍器默认关:零 tick 预定,琴声照常', () async {
    await pumpLoad();
    await controller().play();
    await pumpSteps(8); // now=2.8s。
    expect(engine.scheduleLog.where((c) => c.key.startsWith('tick')), isEmpty);
    expect(engine.scheduleLog, isNotEmpty, reason: '琴声照常预定');
  });

  test('节拍器开:拍点按拍速预定、强弱分音色、默认音量 0.5;琴声尽后 tick 独走到曲末', () async {
    await pumpLoad();
    controller().setAudioOptions(metroEnabled: true);
    await controller().play();
    await pumpSteps(8); // now=2.8s,limit=3.2s:末拍 3000 恰进窗(攻击 2000 已尽)。
    final ticks =
        engine.scheduleLog.where((c) => c.key.startsWith('tick')).toList();
    expect(ticks.map((c) => c.time.inMilliseconds).toList(),
        [0, 750, 1500, 2250, 3000]);
    expect(ticks.map((c) => c.key).toList(), [
      'tick_strong',
      'tick_weak',
      'tick_weak',
      'tick_weak',
      'tick_strong',
    ]);
    expect(ticks.every((c) => c.volume == 0.5), isTrue, reason: '默认节拍音量 0.5');
    final notes = engine.scheduleLog.where((c) => !c.key.startsWith('tick'));
    expect(notes.every((c) => c.volume == 1.0), isTrue);
  });

  test('示范静音:零琴声零 tick 也照推到曲末(静音的是出声不是时间)', () async {
    await pumpLoad();
    controller().setAudioOptions(demoEnabled: false);
    await controller().play();
    await pumpSteps(8); // now=2.8s。
    expect(
        engine.scheduleLog.where((c) => !c.key.startsWith('tick')), isEmpty);
    expect(controller().currentSeconds(), closeTo(2.8, 0.05), reason: '红线照推');
    await pumpSteps(10); // now=6.3s ≥ 曲长 6s。
    await pumpPolls();
    expect(state().status, FlowingStatus.finished, reason: '全静音不拖住曲末判定');
  });

  test('播放中静音琴声:在途立停、已响尾音不切、恢复不回放', () async {
    await pumpLoad();
    await controller().play();
    await pumpSteps(5); // now=1.75s:500/1000 已响,@2000 两声在途。
    expect(
      engine.scheduleLog
          .where((c) => !c.key.startsWith('tick'))
          .where((c) => c.time.inMilliseconds == 2000)
          .length,
      2,
      reason: '和弦两声都在途',
    );
    controller().setAudioOptions(demoEnabled: false);
    final plucks =
        engine.scheduleLog.where((c) => !c.key.startsWith('tick')).toList();
    expect(plucks.length, 4);
    for (final c in plucks) {
      if (c.time.inMilliseconds == 2000) {
        expect(c.stopped, isTrue, reason: '在途 ${c.time} 立停');
      } else {
        expect(c.stopped, isFalse, reason: '已响 ${c.time} 尾音不切');
      }
    }
    await pumpSteps(6); // now=3.85s:跳过段无新琴声。
    expect(engine.scheduleLog.where((c) => !c.key.startsWith('tick')).length, 4);
    controller().setAudioOptions(demoEnabled: true);
    await pumpSteps(6); // now=5.95s:恢复后已过攻击不回放。
    final after =
        engine.scheduleLog.where((c) => !c.key.startsWith('tick')).toList();
    expect(after.length, 4, reason: '跳过段不回放');
    final counts = <String, int>{};
    for (final c in after) {
      final tag = '${c.key}@${c.time}';
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
    expect(counts.values.every((v) => v == 1), isTrue, reason: '无任何重复预定');
  });

  test('播放中静音节拍:在途 tick 立停、已响不切;恢复后已过拍点不补响', () async {
    await pumpLoad();
    controller().setAudioOptions(metroEnabled: true);
    await controller().play();
    await pumpSteps(4); // now=1.4s:tick 0/750 已响,1500 在途。
    controller().setAudioOptions(metroEnabled: false);
    final ticks =
        engine.scheduleLog.where((c) => c.key.startsWith('tick')).toList();
    expect(ticks.map((c) => c.time.inMilliseconds).toList(), [0, 750, 1500]);
    expect(ticks[2].stopped, isTrue, reason: '在途 1500 立停');
    expect(ticks[0].stopped, isFalse, reason: '已响 0 尾音不切');
    expect(ticks[1].stopped, isFalse, reason: '已响 750 尾音不切');
    await pumpSteps(3); // now=2.45s:静音段无新 tick(拍点游标照走不补)。
    expect(engine.scheduleLog.where((c) => c.key.startsWith('tick')).length, 3);
    controller().setAudioOptions(metroEnabled: true);
    await pumpSteps(6); // now=4.55s:静音段游标已消费 2250,恢复从 3000 续。
    expect(
      engine.scheduleLog
          .where((c) => c.key.startsWith('tick'))
          .map((c) => c.time.inMilliseconds)
          .toList(),
      [0, 750, 1500, 3000, 3750, 4500],
      reason: '已过拍点不补响',
    );
  });

  test('循环+节拍器:拍点跨缝回跳无缝,B 独占不越界', () async {
    await pumpLoad();
    controller().setAudioOptions(metroEnabled: true);
    await pumpLoopWindow(); // 窗 [0, 2.2],t0=0。
    await pumpSteps(7); // now=2.45s,过 wrap 2.2。
    List<int> tickTimes() => engine.scheduleLog
        .where((c) => c.key.startsWith('tick') && c.key != 'tick_count')
        .map((c) => c.time.inMilliseconds)
        .toList();
    // 第一轮 0/750/1500(2250 ≥ B 排除),回跳后 2200(=A,重拍)跨缝续。
    expect(tickTimes(), [0, 750, 1500, 2200]);
    await pumpSteps(9); // now=5.6s,limit=6.0s。
    // 第二轮 2950/3700(4450 ≥ B′ 4400 排除),第三轮 4400 续,5150/5900 进窗。
    expect(tickTimes(), [0, 750, 1500, 2200, 2950, 3700, 4400, 5150, 5900]);
  });

  test('循环每轮数+节拍器:gap 段只有数拍 tick,节拍不进 gap', () async {
    await pumpLoad();
    controller().setAudioOptions(metroEnabled: true);
    await pumpLoopWindow(); // 窗 [0, 2.2],t0=0。
    controller().setCountOptions(countPerLoop: true); // 播放中换挡重锚(t0 不变)。
    await pumpSteps(7); // now=2.45s,gap 段。
    final counts = engine.scheduleLog
        .where((c) => c.key == 'tick_count')
        .map((c) => c.time.inMilliseconds)
        .toList();
    expect(counts, [2200, 2950, 3700, 4450], reason: '数拍 tick 独占 gap');
    final metro = engine.scheduleLog
        .where((c) => c.key.startsWith('tick') && c.key != 'tick_count')
        .map((c) => c.time.inMilliseconds)
        .toList();
    expect(metro, [0, 750, 1500], reason: '节拍只在正曲段,gap 不重叠');
    expect(controller().countBeatNow(), 1);
    expect(controller().currentSeconds(), closeTo(0, 1e-6), reason: '红线定在 A');
    // gap 走完:节拍在新轮起点续上(2200+3000=5200 重拍),数拍 tick 不再加。
    await pumpSteps(9); // now=5.6s。
    final metro2 = engine.scheduleLog
        .where((c) => c.key.startsWith('tick') && c.key != 'tick_count')
        .map((c) => c.time.inMilliseconds)
        .toList();
    expect(metro2, [0, 750, 1500, 5200, 5950]);
    expect(controller().countBeatNow(), isNull, reason: '回正曲段');
  });

  test('音量穿透:琴声/节拍音量进预定;数拍 tick 骑节拍音量;播放中改音量即时生效', () async {
    await pumpLoad();
    controller()
      ..setAudioOptions(demoVolume: 0.3, metroVolume: 0.4)
      ..setCountOptions(countInEnabled: true);
    engine.now = const Duration(seconds: 1);
    await controller().play();
    expect(
      engine.scheduleLog
          .where((c) => c.key == 'tick_count')
          .every((c) => c.volume == 0.4),
      isTrue,
      reason: '预备 tick 音量骑节拍音量(codex 同款)',
    );
    engine.advance(const Duration(seconds: 4)); // 数完(now=5s)自动起播,t0=5s。
    await pumpPolls();
    expect(state().status, FlowingStatus.playing);
    controller().setAudioOptions(metroEnabled: true); // 播放中即切,不重建。
    engine.advance(const Duration(milliseconds: 350)); // now=5.35s。
    await pumpPolls();
    expect(
      engine.scheduleLog
          .where((c) => !c.key.startsWith('tick'))
          .where((c) => c.time.inMilliseconds == 5500)
          .every((c) => c.volume == 0.3),
      isTrue,
      reason: '琴声音量穿透',
    );
    expect(
      engine.scheduleLog
          .where((c) => c.key.startsWith('tick') && c.key != 'tick_count')
          .every((c) => c.volume == 0.4),
      isTrue,
    );
    controller().setAudioOptions(metroVolume: 0.8);
    engine.advance(const Duration(milliseconds: 700)); // now=6.05s。
    await pumpPolls();
    engine.advance(const Duration(milliseconds: 200)); // now=6.25s:6500 进窗。
    await pumpPolls();
    expect(
      engine.scheduleLog
          .where((c) => c.key.startsWith('tick') && c.key != 'tick_count')
          .where((c) => c.time.inMilliseconds == 6500)
          .single
          .volume,
      0.8,
      reason: '改音量只影响之后的预定',
    );
  });

  test('音量钳制:越界值收敛到 0..1', () {
    controller()
      ..setAudioOptions(demoVolume: 5)
      ..setAudioOptions(metroVolume: -1);
    expect(state().demoVolume, 1.0);
    expect(state().metroVolume, 0.0);
  });
}
