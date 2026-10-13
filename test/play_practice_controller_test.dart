import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';
import 'package:ukeflow/features/play/play_practice_controller.dart';

import 'helpers/chart_fixtures.dart';

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

  test('初始态:BPM 80、首个内置节奏型、未就绪未运行', () {
    final state = container.read(playPracticeProvider);
    expect(state.bpm, PlayPracticeController.defaultBpm);
    expect(state.pattern, same(builtinStrumPatterns.first));
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
      const Duration(milliseconds: 700),
      reason: '锚定引擎当前时刻,不用挂钟',
    );
    expect(anchor.periodMs, closeTo(60000 / 80, 1e-9));
    expect(engine.scheduleLog.single.key, 'tick_strong', reason: '第 0 拍立即预定强拍');
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
}
