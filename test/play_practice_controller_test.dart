import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/pluck_player.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';
import 'package:ukeflow/core/practice/practice_state.dart';
import 'package:ukeflow/data/chord_library.dart' show Chord;
import 'package:ukeflow/features/play/play_practice_controller.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';

/// 跟练控制器:接缝在 PlayPracticeState 与公开方法;
/// 引擎一律注入 FakeAudioEngine(不碰真引擎)。
void main() {
  late FakeAudioEngine engine;
  late ProviderContainer container;

  PlayPracticeController controller() =>
      container.read(playPracticeProvider.notifier);

  setUp(() {
    engine = FakeAudioEngine();
    container = ProviderContainer(
      overrides: [audioEngineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);
  });

  test('初始态:BPM 80、首个内置节奏型、原速、节拍参考音、未就绪未运行', () {
    final state = container.read(playPracticeProvider);
    expect(state.bpm, PlayPracticeController.defaultBpm);
    expect(state.pattern, same(builtinStrumPatterns.first));
    expect(state.speed, 1.0);
    expect(state.reference, ReferenceSound.beat);
    expect(state.paused, isFalse);
    expect(state.engineReady, isFalse);
    expect(state.running, isFalse);
    expect(state.error, isNull);
  });

  test('prepareFor:进谱即取谱面 tempo 为当前 BPM,越界钳制;运行中不动', () {
    final c = controller();
    c.prepareFor(practiceFixtureChart);
    expect(container.read(playPracticeProvider).bpm, 80, reason: '谱面 tempo');

    c.setBpm(95);
    c.prepareFor(practiceFixtureChart);
    expect(
      container.read(playPracticeProvider).bpm,
      80,
      reason: '再次进谱回谱面速度(页内重启不受影响,prepareFor 只在进页时调)',
    );

    c.prepareFor(parseChart('{title: 快}\n{tempo: 999}\n[C]词\n'));
    expect(container.read(playPracticeProvider).bpm, 208, reason: '钳制上限');
  });

  test('warmup:引擎就绪并注入强弱拍音源', () async {
    await controller().warmup();
    final state = container.read(playPracticeProvider);
    expect(state.engineReady, isTrue);
    expect(state.error, isNull);
    expect(engine.loadedKeys, containsAll(['tick_strong', 'tick_weak']));
  });

  test('并发 warmup 共享同一次在途初始化:音源不重复注入', () async {
    await Future.wait([controller().warmup(), controller().warmup()]);
    expect(engine.loadedKeys.where((k) => k == 'tick_strong'), hasLength(1));
    expect(engine.loadedKeys.where((k) => k == 'tick_weak'), hasLength(1));
  });

  test('初始化失败→重试成功:错误文案清除,不再残留', () async {
    final c = controller();
    engine.failInitialization = true;
    await c.warmup();
    expect(container.read(playPracticeProvider).error, isNotNull);

    engine.failInitialization = false;
    await c.warmup();
    final state = container.read(playPracticeProvider);
    expect(state.engineReady, isTrue);
    expect(state.error, isNull, reason: '旧错误不残留到成功之后');
  });

  test('未就绪不可启;就绪后 start:编译时间轴并锚定引擎时钟', () async {
    final c = controller();
    c.prepareFor(practiceFixtureChart);
    c.start(chart: practiceFixtureChart);
    expect(
      container.read(playPracticeProvider).running,
      isFalse,
      reason: '引擎未就绪拒绝启动',
    );
    expect(engine.scheduleLog, isEmpty);

    await c.warmup();
    engine.advance(const Duration(milliseconds: 700));
    c.start(chart: practiceFixtureChart);

    final state = container.read(playPracticeProvider);
    expect(state.running, isTrue);
    final timeline = c.timeline;
    expect(timeline, isNotNull);
    expect(timeline!.periodMs, closeTo(60000 / 80, 1e-9));
    expect(timeline.totalBeats, 16, reason: '4 小节 × 4 拍');
    final anchor = c.visualAnchor;
    expect(anchor, isNotNull);
    expect(
      anchor!.t0,
      const Duration(milliseconds: 700 + 4 * 750),
      reason: '视觉锚点=曲头,在预备 4 拍之后;锚定引擎当前时刻,不用挂钟',
    );
    expect(anchor.periodMs, closeTo(60000 / 80, 1e-9));
    expect(engine.scheduleLog.single.key, 'tick_count', reason: '启动即数预备拍(专用音源)');
    expect(engine.scheduleLog.single.time, const Duration(milliseconds: 700));
  });

  test('运行中重复 start 被拒;stop 回闲:未响拍停止、时间轴清空', () async {
    final c = controller();
    await c.warmup();
    // BPM 208(拍周期 288ms):启动首过窗(400ms)即含拍 0、拍 1,可验停机停"未响拍"。
    c.setBpm(208);
    c.start(chart: practiceFixtureChart);
    expect(engine.scheduleLog, hasLength(2), reason: '拍 0@0 与拍 1@288 都在启动窗内');

    c.start(chart: practiceFixtureChart);
    expect(engine.scheduleLog, hasLength(2), reason: '运行中不重启');

    // now=100ms:拍 0 已响,拍 1 未响。
    engine.advance(const Duration(milliseconds: 100));
    c.stop();
    final state = container.read(playPracticeProvider);
    expect(state.running, isFalse);
    expect(c.timeline, isNull, reason: '时间轴清空,视觉锚点随之失效');
    expect(c.visualAnchor, isNull);
    expect(
      engine.scheduleLog.where((call) => call.stopped),
      hasLength(1),
      reason: '只有尚未发声的拍 1 被 stop(拍 0 已响不动)',
    );
  });

  test('空闲调参:BPM 钳制 40–208、换节奏型即时生效', () async {
    final c = controller();
    c.setBpm(39);
    expect(container.read(playPracticeProvider).bpm, 40);
    c.setBpm(209);
    expect(container.read(playPracticeProvider).bpm, 208);

    final island = builtinStrumPatterns.last;
    c.setPattern(island);
    expect(container.read(playPracticeProvider).pattern, same(island));
    expect(engine.scheduleLog, isEmpty, reason: '空闲不碰引擎');

    await c.warmup();
    c.start(chart: practiceFixtureChart);
    c.setBpm(120);
    expect(
      container.read(playPracticeProvider).bpm,
      208,
      reason: '运行中固定速度(v1),调参被忽略',
    );
    c.setPattern(builtinStrumPatterns.first);
    expect(
      container.read(playPracticeProvider).pattern,
      same(island),
      reason: '运行中节奏型是编译参数,不可换',
    );
  });

  test('引擎预定出错:自停并进错误状态', () async {
    final c = controller();
    await c.warmup();
    engine.failNow = true;
    c.start(chart: practiceFixtureChart);
    final state = container.read(playPracticeProvider);
    expect(state.running, isFalse, reason: '首过即抛,出错自停');
    expect(state.error, isNotNull);
  });

/// 工单 10:预备数拍、暂停/继续/回到开头、变速、参考音(示范扫弦)。
/// 场景断言靠各调度器的同步首过(不驱轮询定时器);参考音切换测试用
/// fakeAsync 驱过窗。
group('工单 10:预备数拍', () {
  test('warmup 注入预备拍音源', () async {
    final c = controller();
    await c.warmup();
    expect(engine.loadedKeys, contains('tick_count'));
  });

  test('启动即数预备拍;预备期练习状态查询给出倒计(与页面同式)', () async {
    final c = controller();
    await c.warmup();
    engine.advance(const Duration(milliseconds: 700));
    c.start(chart: practiceFixtureChart);

    // 80BPM:750ms/拍,预备窗 [700, 3700)。启动瞬间在预备第 1 拍。
    final anchor = c.visualAnchor!;
    expect(anchor.t0, const Duration(milliseconds: 3700));
    final prep = c.prepStateNow();
    expect(prep!.count, 4);
    // 正曲练习状态在预备期不可得(页面据此切倒计面板)。
    expect(
      practiceStateAt(timeline: c.timeline!, t0: anchor.t0, now: c.visualNow()!),
      isNull,
    );
  });

  test('运行中重复 start 被拒的纪律同样约束预备期', () async {
    final c = controller();
    await c.warmup();
    engine.advance(const Duration(milliseconds: 700));
    c.start(chart: practiceFixtureChart);
    final firstLog = engine.scheduleLog.length;

    c.start(chart: practiceFixtureChart);
    expect(
      engine.scheduleLog,
      hasLength(firstLog),
      reason: '预备期重复 start 不重启、不重铺预备拍',
    );
  });
});

group('工单 10:暂停/继续/回到开头', () {
  test('pause:引擎侧停声、视觉时钟冻结;会话与时间轴保留', () async {
    final c = controller();
    await c.warmup();
    engine.advance(const Duration(milliseconds: 100));
    c.start(chart: practiceFixtureChart);
    final scheduledAtStart = engine.scheduleLog.length;

    engine.advance(const Duration(milliseconds: 4370)); // 正曲第 1 拍中段
    c.pause();
    expect(container.read(playPracticeProvider).paused, isTrue);
    expect(container.read(playPracticeProvider).running, isTrue, reason: '暂停仍在会话内');
    expect(c.timeline, isNotNull, reason: '时间轴保留');
    expect(c.visualAnchor, isNotNull, reason: '锚点保留,恢复与冻结查询都要用');

    final frozen = c.visualNow()!;
    engine.advance(const Duration(seconds: 5));
    expect(c.visualNow()!, frozen, reason: '视觉时钟冻结,不随引擎走');
    expect(
      engine.scheduleLog,
      hasLength(scheduledAtStart),
      reason: '暂停期间不预定任何新声',
    );
  });

  test('resume:重锚续跑,已响拍不重放,拍位无错位', () async {
    final c = controller();
    await c.warmup();
    engine.advance(const Duration(milliseconds: 100));
    c.start(chart: practiceFixtureChart);
    // 推进到曲内 1370ms(正曲第 1 拍中段),引擎时刻 4470。
    engine.advance(const Duration(milliseconds: 4370));
    final anchorBefore = c.visualAnchor!;
    final beatBefore = practiceStateAt(
      timeline: c.timeline!,
      t0: anchorBefore.t0,
      now: c.visualNow()!,
    )!
        .beat;
    expect(beatBefore, 1, reason: '曲内第 1 拍(practiceStateAt 以曲头为锚)');

    c.pause();
    engine.advance(const Duration(seconds: 3));
    c.resume();
    expect(container.read(playPracticeProvider).paused, isFalse);

    // 恢复瞬间拍位不变(音画无错位):重锚 t0' = now' − 冻结逝时。
    final anchorAfter = c.visualAnchor!;
    final beatAfter = practiceStateAt(
      timeline: c.timeline!,
      t0: anchorAfter.t0,
      now: c.visualNow()!,
    )!
        .beat;
    expect(beatAfter, beatBefore, reason: '恢复即回到暂停时的拍,网格连续');
    // 引擎侧:恢复后的新预定全部落在恢复锚点之后(已响拍不重放),
    // 下一正曲拍 6@t0'+4500 = 7600ms 入窗。
    final resumed = engine.scheduleLog.where((e) => e.time >= anchorAfter.t0);
    expect(resumed.map((e) => e.time), [
      const Duration(milliseconds: 7600),
    ], reason: '恢复窗内恰排下一拍(拍 6,弱拍)');
    expect(engine.scheduleLog.last.key, 'tick_weak');
  });

  test('预备期 pause/resume:倒计冻结,恢复后继续数', () async {
    final c = controller();
    await c.warmup();
    engine.advance(const Duration(milliseconds: 700));
    c.start(chart: practiceFixtureChart);
    engine.advance(const Duration(milliseconds: 1000)); // 预备第 2 拍内

    c.pause();
    expect(c.prepStateNow()!.count, 3,
        reason: 'elapsed 1000ms ∈ [750, 1500) → 倒数 3,且已冻结');

    engine.advance(const Duration(seconds: 4));
    c.resume();
    expect(c.prepStateNow()!.count, 3,
        reason: '恢复后从同一预备拍继续,不跳拍不重数');
  });

  test('restart:运行中回到开头,旧预定停净、重新预备数拍', () async {
    final c = controller();
    await c.warmup();
    // 208BPM(周期 288ms):启动首过窗含预备拍 0、1,重启时有在途未响拍。
    c.setBpm(208);
    engine.advance(const Duration(milliseconds: 100));
    c.start(chart: practiceFixtureChart);
    expect(engine.scheduleLog, hasLength(2));

    c.restart();
    final state = container.read(playPracticeProvider);
    expect(state.running, isTrue);
    expect(state.paused, isFalse, reason: '干净复位,不带着暂停态重开');
    // 旧会话在途未响的预备拍 1 停掉;已响的预备拍 0 不动。
    expect(engine.scheduleLog.first.stopped, isFalse);
    expect(engine.scheduleLog[1].stopped, isTrue);
    // 重启首过按 208 网格重铺预备拍(在途的旧预备拍 1 已停,由新预定接管)。
    final live = engine.scheduleLog.where((e) => !e.stopped).toList();
    expect(live.last.key, 'tick_count');
    expect(live.last.time, const Duration(milliseconds: 388));
    expect(c.visualAnchor!.t0, const Duration(milliseconds: 100 + 1154));
  });

  test('空闲 restart 是空操作', () async {
    final c = controller();
    await c.warmup();
    c.restart();
    expect(container.read(playPracticeProvider).running, isFalse);
    expect(engine.scheduleLog, isEmpty);
  });
});

group('工单 10:变速', () {
  test('空闲 setSpeed 记参并钳制 0.5–1.0;start 后时间轴按变速编译', () async {
    final c = controller();
    c.setSpeed(0.3);
    expect(container.read(playPracticeProvider).speed, 0.5, reason: '钳制下限');
    c.setSpeed(1.5);
    expect(container.read(playPracticeProvider).speed, 1.0, reason: '钳制上限');
    c.setSpeed(0.7);
    expect(container.read(playPracticeProvider).speed, 0.7);

    await c.warmup();
    c.start(chart: practiceFixtureChart);
    expect(c.timeline!.periodMs, closeTo(60000 / 80 / 0.7, 1e-9));
    // 调度器网格与时间轴同一周期(同式换算,声画无双公式分叉)。
    expect(c.visualAnchor!.periodMs, closeTo(60000 / 80 / 0.7, 1e-9));
    // 预备 4 拍按变速后的网格走:曲头 = t0 + 4×857.14ms ≈ t0+3429。
    expect(
      c.visualAnchor!.t0.inMilliseconds - engine.engineTime().inMilliseconds,
      closeTo((4 * 60000 / 80 / 0.7).round(), 1),
    );
  });

  test('运行中 setSpeed:重编译+相位保持重锚,拍位连续、新网格即刻生效', () async {
    final c = controller();
    await c.warmup();
    engine.advance(const Duration(milliseconds: 100));
    c.start(chart: practiceFixtureChart);
    engine.advance(const Duration(milliseconds: 4370)); // 曲内第 1 拍中段
    final beatBefore = practiceStateAt(
      timeline: c.timeline!,
      t0: c.visualAnchor!.t0,
      now: c.visualNow()!,
    )!
        .beat;

    c.setSpeed(0.5);
    expect(container.read(playPracticeProvider).speed, 0.5);
    expect(c.timeline!.periodMs, closeTo(1500, 1e-9), reason: '60000/80/0.5');
    expect(c.visualAnchor!.periodMs, closeTo(1500, 1e-9), reason: '调度器同周期');

    final beatAfter = practiceStateAt(
      timeline: c.timeline!,
      t0: c.visualAnchor!.t0,
      now: c.visualNow()!,
    )!
        .beat;
    expect(beatBefore, 1);
    expect(beatAfter, beatBefore, reason: '拍位连续:变速不打断练习位置');
    // 新网格即刻入窗:曲内拍 6(变速后 t0'+round(6×1500) = −4270+9000 = 4730)。
    expect(engine.scheduleLog.last.time, const Duration(milliseconds: 4730));
    expect(engine.scheduleLog.last.key, 'tick_weak');
  });

  test('暂停中 setSpeed:拍位守恒,恢复按新周期重锚', () async {
    final c = controller();
    await c.warmup();
    engine.advance(const Duration(milliseconds: 100));
    c.start(chart: practiceFixtureChart);
    engine.advance(const Duration(milliseconds: 4370));
    c.pause();

    c.setSpeed(0.5);
    final anchor = c.visualAnchor!;
    final beat = practiceStateAt(
      timeline: c.timeline!,
      t0: anchor.t0,
      now: c.visualNow()!,
    )!
        .beat;
    expect(beat, 1, reason: '冻结画面按拍数守恒换算,拍位不变');

    c.resume();
    // 恢复重锚按新周期:t0' = 4470 − round(5.8267×1500) = −4270,
    // 下一拍 6@−4270+9000 = 4730 即刻入窗。
    expect(engine.scheduleLog.last.time, const Duration(milliseconds: 4730));
    final beatAfter = practiceStateAt(
      timeline: c.timeline!,
      t0: c.visualAnchor!.t0,
      now: c.visualNow()!,
    )!
        .beat;
    expect(beatAfter, 1, reason: '恢复拍位无错位');
  });
});

group('工单 10:参考音(节拍声/示范扫弦声)', () {
  Map<String, Chord> fixtureChords() => {
        for (final chord in uiFixtureLibrary.chords) chord.label: chord,
      };

  test('运行中切扫弦:窗内扫弦事件预定拨弦、正曲 tick 静默;切回恢复', () async {
    // fakeAsync 体必须同步(await 会让体停摆、断言空转——曾放过锚定 bug):
    // warmup 在真实 zone 先行完成,调度器定时器在 fake zone 内被 elapse 驱动。
    final c = controller();
    c.prepareFor(practiceFixtureChart, chords: fixtureChords());
    await c.warmup(); // 预备拍+扫弦音源一并就绪
    final amKey =
        'pluck_${fixtureChords()['Am']!.primaryFingering.stringFrequencies.whereType<double>().first}_1500';
    fakeAsync((async) {
      engine.advance(const Duration(milliseconds: 100));
      c.start(chart: practiceFixtureChart, chords: fixtureChords());
      engine.advance(const Duration(milliseconds: 4400)); // now=4500
      final logBefore = engine.scheduleLog.length;

      c.setReference(ReferenceSound.strum);
      // 扫弦调度器同步首过(曲头锚 3100):曲内 1500ms 的扫弦事件
      // (绝对 4600)入窗,更早的已过期越过。
      final plucks = engine.scheduleLog
          .sublist(logBefore)
          .where((e) => e.key.startsWith('pluck_'))
          .toList();
      expect(plucks, isNotEmpty, reason: '切扫弦即有声音可期');
      expect(plucks.first.time, const Duration(milliseconds: 4600));
      expect(
        plucks.first.key,
        amKey,
        reason: '4600ms = 曲内 1500ms(第 1 小节 Am):锚定错成预备拍 0 时,'
            '同刻拨的是曲内 4500ms(第 2 小节 C)——和弦身份钉死曲头锚',
      );
      expect(
        plucks.last.time.inMilliseconds - plucks.first.time.inMilliseconds,
        lessThanOrEqualTo(3 * PluckPlayer.strumGap.inMilliseconds),
        reason: '一次扫弦 = 弦间错峰一组拨弦',
      );

      async.elapse(const Duration(milliseconds: 40)); // 节拍调度器过窗
      expect(
        engine.scheduleLog.where(
          (e) => e.key.startsWith('tick_') && e.time.inMilliseconds >= 4500,
        ),
        isEmpty,
        reason: '参考音=扫弦时正曲拍静默',
      );

      c.setReference(ReferenceSound.beat);
      engine.advance(const Duration(milliseconds: 800)); // now=5300
      async.elapse(const Duration(milliseconds: 40));
      expect(
        engine.scheduleLog.any(
          (e) => e.key == 'tick_weak' && e.time == const Duration(milliseconds: 5350),
        ),
        isTrue,
        reason: '切回节拍后下一拍恢复 tick',
      );
    });
  });

  test('空闲预选示范扫弦:开始即生效——预备期静默,曲头起按和弦拨响', () async {
    final c = controller();
    c.prepareFor(practiceFixtureChart, chords: fixtureChords());
    await c.warmup();
    c.setReference(ReferenceSound.strum); // 空闲预选(此时无扫弦调度器)
    final amKey =
        'pluck_${fixtureChords()['Am']!.primaryFingering.stringFrequencies.whereType<double>().first}_1500';
    fakeAsync((async) {
      engine.advance(const Duration(milliseconds: 100));
      c.start(chart: practiceFixtureChart, chords: fixtureChords());
      async.elapse(const Duration(milliseconds: 40)); // 会话首过窗
      expect(
        engine.scheduleLog.where((e) => e.key.startsWith('pluck_')),
        isEmpty,
        reason: '预备数拍期无扫弦声(扫弦事件锚曲头,不锚预备拍 0)',
      );

      // 预备 3 秒后进曲:曲头第一扫(Am)入窗。
      engine.advance(const Duration(milliseconds: 3030)); // now=3130
      async.elapse(const Duration(milliseconds: 40));
      final plucks = engine.scheduleLog
          .where((e) => e.key.startsWith('pluck_'))
          .toList();
      expect(plucks, isNotEmpty, reason: '空闲预选不丢参考音:开始即建扫弦调度器');
      expect(plucks.first.time, const Duration(milliseconds: 3100), reason: '曲头首扫');
      expect(plucks.first.key, amKey, reason: '曲内第 1 小节 Am');
    });
  });

  test('restart 保留参考音:回到开头后扫弦声按新曲头重铺', () async {
    final c = controller();
    c.prepareFor(practiceFixtureChart, chords: fixtureChords());
    await c.warmup();
    fakeAsync((async) {
      engine.advance(const Duration(milliseconds: 100));
      c.start(chart: practiceFixtureChart, chords: fixtureChords());
      engine.advance(const Duration(milliseconds: 4400)); // now=4500
      c.setReference(ReferenceSound.strum);
      expect(
        engine.scheduleLog.any((e) => e.key.startsWith('pluck_')),
        isTrue,
        reason: '切换即有声(同步首过)',
      );

      c.restart(); // 新会话 t0=4500,新曲头 = 4500+3000 = 7500
      engine.advance(const Duration(milliseconds: 2960)); // now=7460
      async.elapse(const Duration(milliseconds: 40));
      final afterRestart = engine.scheduleLog
          .where((e) => e.key.startsWith('pluck_') && !e.stopped)
          .where((e) => e.time.inMilliseconds >= 7500)
          .toList();
      expect(
        afterRestart,
        isNotEmpty,
        reason: 'restart 重建扫弦调度器,新会话参考声不丢',
      );
      expect(
        afterRestart.first.time,
        const Duration(milliseconds: 7500),
        reason: '新曲头首扫',
      );
    });
  });

  test('切扫弦时和弦缺位:静默降级不炸', () async {
    final c = controller();
    await c.warmup();
    fakeAsync((async) {
      engine.advance(const Duration(milliseconds: 100));
      c.start(chart: practiceFixtureChart);
      engine.advance(const Duration(milliseconds: 4400));
      c.setReference(ReferenceSound.strum);
      async.elapse(const Duration(milliseconds: 40));
      expect(
        engine.scheduleLog.where((e) => e.key.startsWith('pluck_')),
        isEmpty,
        reason: '无和弦表 → 无声,但不抛错',
      );
      expect(container.read(playPracticeProvider).running, isTrue);
    });
  });

  test('暂停:在途扫弦预定停止;恢复按重锚重建', () async {
    final c = controller();
    c.prepareFor(practiceFixtureChart, chords: fixtureChords());
    await c.warmup(); // 和弦表先行登记,预注入随之就绪
    engine.advance(const Duration(milliseconds: 100));
    c.start(chart: practiceFixtureChart, chords: fixtureChords());
    engine.advance(const Duration(milliseconds: 4400));
    c.setReference(ReferenceSound.strum);
    final plucksBefore = engine.scheduleLog
        .where((e) => e.key.startsWith('pluck_'))
        .toList();
    expect(plucksBefore, isNotEmpty);

    c.pause();
    expect(
      plucksBefore.every((e) => e.stopped),
      isTrue,
      reason: '暂停把在途拨弦全部停掉',
    );

    engine.advance(const Duration(seconds: 2));
    c.resume();
    final resumedPlucks = engine.scheduleLog
        .where((e) => e.key.startsWith('pluck_') && e.time.inMilliseconds >= 6500)
        .toList();
    expect(resumedPlucks, isNotEmpty, reason: '恢复后扫弦声按重锚重建');
    expect(resumedPlucks.length, lessThanOrEqualTo(4), reason: '有界:只排窗内事件');
  });
});

  group('审计30(#33/#34/#35)', () {
    Map<String, Chord> fixtureChords() => {
          for (final chord in uiFixtureLibrary.chords) chord.label: chord,
        };

    test('运行时错误后 warmup 重试:引擎仍就绪时清陈错恢复可用(#33)', () async {
      final c = controller();
      c.prepareFor(practiceFixtureChart);
      await c.warmup();
      engine.failNow = true;
      fakeAsync((async) {
        c.start(chart: practiceFixtureChart);
      });
      var s = container.read(playPracticeProvider);
      expect(s.running, isFalse, reason: '首播失败不宣布运行');
      expect(s.error, isNotNull);
      engine.failNow = false;
      await c.warmup();
      s = container.read(playPracticeProvider);
      expect(s.error, isNull, reason: '重试=清陈错,重跑走 start');
      expect(s.engineReady, isTrue);
    });

    test('运行中变速首过即抛:错误落地,不再回读锚点空断言崩(#34)', () async {
      final c = controller();
      c.prepareFor(practiceFixtureChart);
      await c.warmup();
      fakeAsync((async) {
        c.start(chart: practiceFixtureChart);
        // now=740:变 0.5 速重锚后首拍 960 落在窗内,changePeriod 尾过窗
        // 必调 playClocked(在 100 变速则首拍 1400 在窗外,错误不触发)。
        engine.advance(const Duration(milliseconds: 640));
        engine.failNow = true;
        expect(
          () => c.setSpeed(0.5),
          returnsNormally,
          reason: 'changePeriod 尾过窗报错后不得回读已清空的调度器',
        );
        final s = container.read(playPracticeProvider);
        expect(s.running, isFalse, reason: '错误路径自停');
        expect(s.error, isNotNull);
      });
    });

    test('运行中切参考音:旧模式排队取消、不重排叠加、切回自下一拍(#35)', () async {
      final c = controller();
      c.prepareFor(practiceFixtureChart, chords: fixtureChords());
      await c.warmup();
      fakeAsync((async) {
        engine.advance(const Duration(milliseconds: 100));
        c.start(chart: practiceFixtureChart, chords: fixtureChords());
        // 曲头 3100(预备 4×750):推进到 3700(曲内第 1 拍后),喂窗让
        // 曲内拍 5(3850)排队。
        engine.advance(const Duration(milliseconds: 3600));
        async.elapse(const Duration(milliseconds: 40));
        final queued = engine.scheduleLog
            .where((e) =>
                !e.stopped &&
                e.key != 'tick_count' &&
                e.time.inMilliseconds >= 3700)
            .toList();
        expect(queued, isNotEmpty, reason: '参考音=节拍:曲内拍已排队');

        c.setReference(ReferenceSound.strum);
        for (final e in queued) {
          expect(e.stopped, isTrue, reason: '切扫弦:旧节拍排队取消 ${e.time}');
        }
        async.elapse(const Duration(milliseconds: 40)); // 新节拍调度器过窗
        expect(
          engine.scheduleLog.where((e) =>
              e.key.startsWith('tick_') &&
              !e.stopped &&
              e.time.inMilliseconds >= 3700),
          isEmpty,
          reason: '正曲 tick 静默且不重排(无叠加)',
        );

        c.setReference(ReferenceSound.beat);
        engine.advance(const Duration(milliseconds: 100)); // now=3800
        async.elapse(const Duration(milliseconds: 40));
        expect(
          engine.scheduleLog
              .where((e) => e.key == 'tick_weak' && !e.stopped)
              .map((e) => e.time),
          contains(const Duration(milliseconds: 3850)),
          reason: '切回节拍:下一拍恢复 tick',
        );
        expect(
          engine.scheduleLog.where((e) =>
              e.key.startsWith('tick_') &&
              !e.stopped &&
              e.time.inMilliseconds > 3100 &&
              e.time.inMilliseconds < 3850),
          isEmpty,
          reason: '切换前已消费的拍不回放',
        );
      });
    });
  });

}
