import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/features/rhythm/rhythm_trainer_page.dart';

/// 节奏型训练页:引擎一律注入 FakeAudioEngine;箭头推进用假时钟驱动。
void main() {
  late FakeAudioEngine engine;

  Future<void> pumpPage(WidgetTester tester) async {
    engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(engine)],
        child: const MaterialApp(home: RhythmTrainerPage()),
      ),
    );
    await tester.pumpAndSettle(); // warmup 微任务落定
  }

  Icon? slotIcon(WidgetTester tester, int i) {
    final cell = find.descendant(
      of: find.byKey(Key('arrow-slot-$i')),
      matching: find.byType(Icon),
    );
    return tester.widgetList<Icon>(cell).firstOrNull;
  }

  Color cellColor(WidgetTester tester, int i) =>
      (tester.widget<Container>(find.byKey(Key('arrow-slot-$i'))).decoration!
          as BoxDecoration)
          .color!;

  testWidgets('渲染:默认节奏型、8 槽箭头格、BPM 80、节拍声开、引擎就绪可启', (tester) async {
    await pumpPage(tester);
    expect(find.text('节奏型训练'), findsOneWidget);
    expect(find.byKey(const Key('pattern-all-down')), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(
        find.byKey(const Key('pattern-all-down')),
      ).selected,
      isTrue,
      reason: '默认选中第一个(最易)节奏型',
    );
    expect(find.text('80'), findsOneWidget);
    expect(find.text('引擎就绪'), findsOneWidget);
    expect(find.byKey(const Key('beat-number')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('beat-number'))).data,
      '·',
      reason: '空闲时拍号回闲',
    );

    for (var i = 0; i < 8; i++) {
      expect(find.byKey(Key('arrow-slot-$i')), findsOneWidget);
    }
    expect(slotIcon(tester, 0)!.icon, Icons.arrow_downward);
    expect(slotIcon(tester, 1), isNull, reason: '默认型的 1& 是空拍');
    expect(slotIcon(tester, 2)!.icon, Icons.arrow_downward);

    final toggle = find.byKey(const Key('rhythm-toggle'));
    expect(tester.widget<FilledButton>(toggle).onPressed, isNotNull);
    expect(find.text('开始'), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(const Key('click-switch'))).value,
        isTrue);
  });

  testWidgets('换节奏型:箭头格即时重排,选中态迁移', (tester) async {
    await pumpPage(tester);
    expect(slotIcon(tester, 3), isNull, reason: '默认型 2& 空拍');

    await tester.tap(find.byKey(const Key('pattern-island')));
    await tester.pump();

    expect(
      tester.widget<ChoiceChip>(
        find.byKey(const Key('pattern-island')),
      ).selected,
      isTrue,
    );
    expect(
      tester.widget<ChoiceChip>(
        find.byKey(const Key('pattern-all-down')),
      ).selected,
      isFalse,
    );
    expect(slotIcon(tester, 3)!.icon, Icons.arrow_upward, reason: '2& 上扫');
    expect(slotIcon(tester, 4), isNull, reason: '拍 3 空过');
    expect(slotIcon(tester, 5)!.icon, Icons.arrow_upward, reason: '3& 上扫');
  });

  testWidgets('开始后箭头随引擎时钟逐槽推进:当前槽点亮、拍号随动', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('rhythm-toggle')));
    await tester.pump();
    expect(engine.scheduleLog.single.key, 'tick_strong');

    // 推进 760ms(默认 80 BPM:一槽 375ms,槽 2@750ms;推进喂 40ms 调度
    // 定时器 + 16ms 视觉轮询):槽 2 应点亮,拍号显示 2。
    engine.advance(const Duration(milliseconds: 760));
    await tester.pump(const Duration(milliseconds: 45));
    final context = tester.element(find.byKey(const Key('arrow-slot-2')));
    final primary = Theme.of(context).colorScheme.primary;
    expect(cellColor(tester, 2), primary, reason: '当前槽 2 点亮(主色)');
    expect(cellColor(tester, 0), isNot(primary), reason: '已扫槽 0 淡出');
    expect(
      tester.widget<Text>(find.byKey(const Key('beat-number'))).data,
      '2',
      reason: '拍 2',
    );
  });

  testWidgets('节拍声开关:关后调度过窗不再出声,箭头训练不受扰', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('rhythm-toggle')));
    await tester.pump();
    expect(engine.scheduleLog, hasLength(1));

    await tester.tap(find.byKey(const Key('click-switch')));
    await tester.pump();
    expect(tester.widget<Switch>(find.byKey(const Key('click-switch'))).value,
        isFalse);

    // 推进过窗(拍 1@750ms 落入 400ms 窗)并喂调度定时器:不出声。
    engine.advance(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 45));
    expect(engine.scheduleLog, hasLength(1), reason: '静默期不预定发声');
    expect(find.text('停止'), findsOneWidget, reason: '训练仍在进行');
  });

  testWidgets('停止后回闲:拍号复位、不再调度', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('rhythm-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('rhythm-toggle')));
    await tester.pump();

    final countAfterStop = engine.scheduleLog.length;
    engine.advance(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 20));
    expect(engine.scheduleLog, hasLength(countAfterStop));
    expect(
      tester.widget<Text>(find.byKey(const Key('beat-number'))).data,
      '·',
      reason: '拍号回闲',
    );
  });

  testWidgets('引擎初始化失败:错误可见,开始按钮禁用', (tester) async {
    engine = FakeAudioEngine()..failInitialization = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(engine)],
        child: const MaterialApp(home: RhythmTrainerPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('引擎初始化失败'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('rhythm-toggle')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('手机宽度(360dp)下 8 槽一行均分,不溢出', (tester) async {
    // 默认测试面 800×600 抓不到窄屏溢出;按真机 OPPO 360dp 宽重设(工单 04 教训)。
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await pumpPage(tester);

    expect(tester.takeException(), isNull);
    final rects = [
      for (var i = 0; i < 8; i++) tester.getRect(find.byKey(Key('arrow-slot-$i'))),
    ];
    expect(rects.map((r) => r.top).toSet(), hasLength(1), reason: '8 槽同一行');
    expect(rects.map((r) => r.width).toSet(), hasLength(1), reason: '宽度均分');
  });
}
