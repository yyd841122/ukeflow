import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/features/rhythm/metronome_page.dart';

/// 节拍器页:引擎一律注入 FakeAudioEngine;视觉拍推进用假时钟驱动。
void main() {
  late FakeAudioEngine engine;

  Future<void> pumpPage(WidgetTester tester) async {
    engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(engine)],
        child: const MaterialApp(home: MetronomePage()),
      ),
    );
    await tester.pumpAndSettle(); // warmup 微任务落定
  }

  testWidgets('渲染:BPM 默认 120,四个拍点,引擎就绪后可启停', (tester) async {
    await pumpPage(tester);
    expect(find.text('节拍器'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('BPM'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(Key('beat-dot-$i')), findsOneWidget);
    }
    expect(find.text('引擎就绪'), findsOneWidget);

    final toggle = find.byKey(const Key('metronome-toggle'));
    expect(tester.widget<FilledButton>(toggle).onPressed, isNotNull);
    expect(find.text('开始'), findsOneWidget);
  });

  testWidgets('初始化失败:错误可见,开始按钮禁用', (tester) async {
    engine = FakeAudioEngine()..failInitialization = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(engine)],
        child: const MaterialApp(home: MetronomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('引擎初始化失败'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('metronome-toggle')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('开始后拍点随引擎时钟推进,停后回闲且不再调度', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('metronome-toggle')));
    await tester.pump(); // start 即时首过
    expect(engine.scheduleLog.single.key, 'tick_strong');
    expect(find.text('已预定 1 拍'), findsOneWidget);

    // 推进引擎时钟,并给驱动器定时器喂 45ms(40ms 周期触发一次过窗):
    // 第 1 拍(500ms,弱拍)被预定并点亮。
    engine.advance(const Duration(milliseconds: 510));
    await tester.pump(const Duration(milliseconds: 45));
    final context = tester.element(find.byKey(const Key('beat-dot-1')));
    expect(
      dotColor(tester, 1),
      Theme.of(context).colorScheme.primary,
      reason: '拍 1 当前应点亮(主色)',
    );
    expect(dotColor(tester, 0), isNot(Theme.of(context).colorScheme.primary));
    expect(find.text('2'), findsOneWidget, reason: '小节内第 2 拍');

    // 停止后钟表继续走也不再预定,拍号回闲。
    await tester.tap(find.byKey(const Key('metronome-toggle')));
    await tester.pump();
    final countAfterStop = engine.scheduleLog.length;
    engine.advance(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 20));
    expect(engine.scheduleLog, hasLength(countAfterStop));
    expect(find.text('·'), findsOneWidget, reason: '停后拍号回闲');
  });

  testWidgets('停止时窗内未响拍被 stop(已响拍不动)', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('metronome-toggle')));
    await tester.pump();

    // 引擎钟推到 260ms(拍 1@500ms 尚未响),喂驱动器 45ms 让它把拍 1 预定上。
    engine.advance(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 45));
    expect(engine.scheduleLog.map((c) => c.key), ['tick_strong', 'tick_weak']);

    await tester.tap(find.byKey(const Key('metronome-toggle')));
    await tester.pump();
    final stopped = engine.scheduleLog.where((c) => c.stopped).toList();
    expect(stopped.map((c) => c.key), ['tick_weak'],
        reason: '只有未响的拍 1(弱拍)被 stop');
    expect(engine.scheduleLog.first.stopped, isFalse, reason: '拍 0 已响不 stop');
  });

  testWidgets('BPM ± 按钮即时生效并驱动重锚(不中断运行)', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('metronome-toggle')));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('121'), findsOneWidget);
    // 重锚后时间轴仍在:视觉锚点存在、运行中。
    expect(find.byIcon(Icons.stop), findsOneWidget);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(find.text('120'), findsOneWidget);
  });
}

/// 第 [i] 个拍点当前的颜色。
Color dotColor(WidgetTester tester, int i) =>
    (tester.widget<Container>(find.byKey(Key('beat-dot-$i'))).decoration!
        as BoxDecoration)
        .color!;
