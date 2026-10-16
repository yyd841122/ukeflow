import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';
import 'package:ukeflow/features/rhythm/rhythm_trainer_controller.dart';

/// 节奏型训练控制器:接缝在 RhythmTrainerState 与公开方法;
/// 引擎一律注入 FakeAudioEngine(不碰真引擎)。
void main() {
  late FakeAudioEngine engine;
  late ProviderContainer container;

  RhythmTrainerController controller() =>
      container.read(rhythmTrainerProvider.notifier);

  setUp(() {
    engine = FakeAudioEngine();
    container = ProviderContainer(
      overrides: [audioEngineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);
  });

  test('初始态:默认取第一个内置节奏型,BPM 80,节拍声开', () {
    final state = container.read(rhythmTrainerProvider);
    expect(state.pattern, same(builtinStrumPatterns.first));
    expect(state.bpm, RhythmTrainerController.defaultBpm);
    expect(state.clickOn, isTrue);
    expect(state.running, isFalse);
    expect(state.engineReady, isFalse);
  });

  test('warmup:引擎就绪并注入强弱拍音源', () async {
    await controller().warmup();
    final state = container.read(rhythmTrainerProvider);
    expect(state.engineReady, isTrue);
    expect(engine.loadedKeys, containsAll(['tick_strong', 'tick_weak']));
  });

  test('toggle 启停:start 锚定引擎时钟,第 0 拍立即预定强拍;stop 清干净', () async {
    final c = controller();
    await c.warmup();
    engine.advance(const Duration(milliseconds: 700));

    c.toggle();
    var state = container.read(rhythmTrainerProvider);
    expect(state.running, isTrue);
    expect(engine.scheduleLog.single.key, 'tick_strong');
    expect(engine.scheduleLog.single.time, const Duration(milliseconds: 700),
        reason: '锚定引擎当前时刻,不用挂钟');

    c.toggle();
    state = container.read(rhythmTrainerProvider);
    expect(state.running, isFalse);
    expect(engine.scheduleLog.single.stopped, isFalse, reason: '已响拍不 stop');
  });

  test('节拍声开关:关后新预定拍静默,重开后恢复', () async {
    final c = controller();
    await c.warmup();
    c.toggle();
    expect(engine.scheduleLog.single.key, 'tick_strong');

    // 关:拍 1(750ms)推进进窗后强制过窗(setBpm 同值也重锚+过窗),
    // 预定发生在它身上但不发声。推进须不足一拍,避免重锚丢弃过期拍
    // (该路径是无轮询的病态,单测里没有真定时器)。
    c.toggleClick();
    expect(container.read(rhythmTrainerProvider).clickOn, isFalse);
    engine.advance(const Duration(milliseconds: 400));
    c.setBpm(container.read(rhythmTrainerProvider).bpm);
    expect(engine.scheduleLog, hasLength(1), reason: '静默期不预定发声');

    // 开:恢复预定(拍 2 非强拍,走弱拍音源)。
    c.toggleClick();
    expect(container.read(rhythmTrainerProvider).clickOn, isTrue);
    engine.advance(const Duration(milliseconds: 700)); // now=1100,拍 2@1500 进窗
    c.setBpm(container.read(rhythmTrainerProvider).bpm);
    expect(engine.scheduleLog.length, greaterThan(1));
    expect(engine.scheduleLog.last.key, 'tick_weak');
  });

  test('setBpm 钳制 40–208;运行中重锚即时生效(慢练 40 可达)', () async {
    final c = controller();
    c.setBpm(39);
    expect(container.read(rhythmTrainerProvider).bpm, 40);
    c.setBpm(209);
    expect(container.read(rhythmTrainerProvider).bpm, 208);
    expect(engine.scheduleLog, isEmpty, reason: '未运行,不碰引擎');

    await c.warmup();
    c.toggle();
    c.setBpm(40);
    final anchor = c.visualAnchor;
    expect(anchor, isNotNull);
    expect(anchor!.periodMs, closeTo(60000 / 40, 1e-9));
  });

  test('setPattern 运行中即时换型:状态更新,调度不受扰', () async {
    final c = controller();
    await c.warmup();
    c.toggle();
    final scheduledBefore = engine.scheduleLog.length;

    final island = builtinStrumPatterns.last;
    c.setPattern(island);
    expect(container.read(rhythmTrainerProvider).pattern, same(island));
    expect(c.visualAnchor, isNotNull, reason: '调度时间轴不重置');
    // 强制过窗(推进不足一拍防重锚丢拍):节拍声照常预定,节奏型不影响它。
    engine.advance(const Duration(milliseconds: 400));
    c.setBpm(80);
    expect(engine.scheduleLog.length, greaterThan(scheduledBefore));
  });

  test('引擎预定出错:onError 停机并进错误状态', () async {
    final c = controller();
    await c.warmup();
    c.toggle();
    expect(container.read(rhythmTrainerProvider).running, isTrue);

    engine.failNow = true;
    engine.advance(const Duration(milliseconds: 400));
    c.setBpm(97); // 触发重锚+过窗,窗内预定即抛(模拟真机引擎异常)
    final state = container.read(rhythmTrainerProvider);
    expect(state.running, isFalse, reason: '出错自停');
    expect(state.error, isNotNull);
  });

  group('审计30 同型三纪律(#48/#49/#50)', () {
    test('warmup 期间容器释放:不抛、不写状态', () async {
      final c = controller();
      final warming = c.warmup();
      container.dispose(); // 同步释放:warmup 的续体落在已释放容器上
      await expectLater(warming, completes);
    });

    test('warmup 成功清旧错误:瞬态失败后重开不残留失败文案', () async {
      engine.failInitialization = true;
      await controller().warmup();
      expect(container.read(rhythmTrainerProvider).error, isNotNull);
      engine.failInitialization = false;
      await controller().warmup();
      final s = container.read(rhythmTrainerProvider);
      expect(s.engineReady, isTrue);
      expect(s.error, isNull);
    });

    test('首播失败:running 不覆盖为 true、错误可见;解除后可再开', () async {
      final c = controller();
      await c.warmup();
      engine.failNow = true;
      c.toggle();
      final s = container.read(rhythmTrainerProvider);
      expect(s.running, isFalse, reason: '首播失败不得宣布运行');
      expect(s.error, isNotNull);
      engine.failNow = false;
      c.toggle();
      expect(container.read(rhythmTrainerProvider).running, isTrue);
    });
  });

}
