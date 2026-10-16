import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/features/rhythm/metronome_controller.dart';

/// 节拍器控制器:接缝在 MetronomeState 与公开方法;
/// 引擎一律注入 FakeAudioEngine(不碰真引擎)。
void main() {
  late FakeAudioEngine engine;
  late ProviderContainer container;

  MetronomeController controller() =>
      container.read(metronomeProvider.notifier);

  setUp(() {
    engine = FakeAudioEngine();
    container = ProviderContainer(
      overrides: [audioEngineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);
  });

  test('warmup:引擎就绪并注入强弱拍音源', () async {
    await controller().warmup();
    expect(container.read(metronomeProvider).engineReady, isTrue);
    expect(engine.loadedKeys, containsAll(['tick_strong', 'tick_weak']));
  });

  test('warmup 失败:错误可见、不就绪;start 不动作', () async {
    engine.failInitialization = true;
    await controller().warmup();
    final state = container.read(metronomeProvider);
    expect(state.engineReady, isFalse);
    expect(state.error, isNotNull);

    controller().toggle();
    expect(container.read(metronomeProvider).running, isFalse);
  });

  test('setBpm 钳制到 40–208;未运行时不碰引擎', () {
    final c = controller();
    c.setBpm(39);
    expect(container.read(metronomeProvider).bpm, 40);
    c.setBpm(209);
    expect(container.read(metronomeProvider).bpm, 208);
    c.setBpm(97);
    expect(container.read(metronomeProvider).bpm, 97);
    expect(engine.scheduleLog, isEmpty, reason: '未运行,无任何预定');
  });

  test('toggle 启停:start 后第 0 拍立即预定(强拍),stop 清进度', () async {
    final c = controller();
    await c.warmup();
    engine.advance(const Duration(milliseconds: 900));

    c.toggle();
    var state = container.read(metronomeProvider);
    expect(state.running, isTrue);
    expect(state.scheduledBeats, 1, reason: 'start 即时首过');
    expect(engine.scheduleLog.single.key, 'tick_strong');
    expect(engine.scheduleLog.single.time, const Duration(milliseconds: 900),
        reason: '锚定引擎当前时刻,不用挂钟');

    c.toggle();
    state = container.read(metronomeProvider);
    expect(state.running, isFalse);
    expect(state.scheduledBeats, 0);
  });

  test('运行中 setBpm:重锚定生效(视觉锚点周期即时更新)', () async {
    final c = controller();
    await c.warmup();
    c.toggle();

    c.setBpm(90);
    expect(container.read(metronomeProvider).bpm, 90);
    final anchor = c.visualAnchor;
    expect(anchor, isNotNull);
    expect(anchor!.periodMs, closeTo(60000 / 90, 1e-9));
    expect(c.visualAnchor!.t0, isNotNull);
  });

  test('引擎预定出错:onError 停机并进错误状态', () async {
    final c = controller();
    await c.warmup();
    c.toggle();
    expect(container.read(metronomeProvider).running, isTrue);

    // 运行中把引擎弄坏:换速触发重锚+过窗,窗内到期拍预定即抛(模拟真机引擎异常)。
    engine.failNow = true;
    engine.advance(const Duration(milliseconds: 400));
    c.setBpm(97); // 重锚后第 1 拍落在 524ms,恰在 now+400 窗内 → 触发预定
    final state = container.read(metronomeProvider);
    expect(state.running, isFalse, reason: '出错自停');
    expect(state.error, isNotNull);
  });

  group('审计30 同型三纪律(#43/#44/#45 与 #33 同型)', () {
    test('warmup 期间容器释放:不抛、不写状态', () async {
      final c = controller();
      final warming = c.warmup(); // 不 await:让 dispose 插进 await 间隙
      container.dispose(); // 同步释放:warmup 的续体落在已释放容器上
      await expectLater(warming, completes);
    });

    test('warmup 成功清旧错误:瞬态失败后重开不残留失败文案', () async {
      engine.failInitialization = true;
      await controller().warmup();
      expect(container.read(metronomeProvider).error, isNotNull);
      engine.failInitialization = false;
      await controller().warmup();
      final s = container.read(metronomeProvider);
      expect(s.engineReady, isTrue);
      expect(s.error, isNull);
    });

    test('首播失败:running 不覆盖为 true、错误可见;解除后可再开', () async {
      final c = controller();
      await c.warmup();
      engine.failNow = true;
      c.toggle();
      final s = container.read(metronomeProvider);
      expect(s.running, isFalse, reason: '首播失败不得宣布运行');
      expect(s.error, isNotNull);
      expect(engine.scheduleLog.where((e) => !e.stopped), isEmpty);
      engine.failNow = false;
      c.toggle();
      expect(container.read(metronomeProvider).running, isTrue);
    });

    test('运行时错误后 warmup 重试:引擎仍就绪时清陈错恢复可用', () async {
      final c = controller();
      await c.warmup();
      engine.failNow = true;
      c.toggle();
      expect(container.read(metronomeProvider).error, isNotNull);
      engine.failNow = false;
      await c.warmup();
      final s = container.read(metronomeProvider);
      expect(s.error, isNull, reason: '重试=清陈错,重跑走 start');
      expect(s.engineReady, isTrue);
    });
  });

}
