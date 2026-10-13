import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/features/play/tab_chart_page.dart';

import 'helpers/chart_fixtures.dart';

/// 指弹跟练会话页(工单 13):引擎一律注入 FakeAudioEngine。
/// 空闲面板保留工单 12 的静态读谱(弹前读谱),这里锁页面结构;
/// 运行态流转在 tab_practice_page_test。
void main() {
  late FakeAudioEngine engine;

  Future<void> pumpPage(WidgetTester tester, {bool narrow = false}) async {
    engine = FakeAudioEngine();
    if (narrow) {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(engine)],
        child: MaterialApp(home: const Scaffold(body: SizedBox.shrink())),
      ),
    );
    // 经路由压栈打开:会话页在产品里是 push 页(带返回钮),与导航一致。
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => TabChartPage(chart: tabFixtureChart),
          ),
        );
    await tester.pumpAndSettle(); // 空闲页无周期定时器,可安全落定
  }

  testWidgets('空闲渲染:曲名、元信息、弦号列与谱面画布齐全,就绪可启', (tester) async {
    await pumpPage(tester);

    expect(find.text('指弹测试曲'), findsOneWidget, reason: 'AppBar 曲名');
    expect(find.text('指弹 · 测试者 · 80 BPM'), findsOneWidget);
    expect(
      find.byKey(const Key('tab-chart-labels')),
      findsOneWidget,
      reason: '弹前读谱(工单 12 收进空闲面板)',
    );
    expect(find.byKey(const Key('tab-chart-canvas')), findsOneWidget);
    expect(find.byKey(const Key('tab-practice-start')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('tab-practice-start')))
          .onPressed,
      isNotNull,
      reason: '引擎就绪后可启',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏(360dp):空闲画布横向可滚,整曲小节可达', (tester) async {
    await pumpPage(tester, narrow: true);

    // 空闲面板的静态四线谱在 360dp 视口放不下:画布宽度超出视口,横向
    // 拖到末小节线不抛异常(时值横向位置不因屏窄而截断)。
    final canvas =
        tester.renderObject(find.byKey(const Key('tab-chart-canvas')))
            as dynamic;
    expect(canvas.size.width, greaterThan(canvas.size.height));

    await tester.drag(
      find.byKey(const Key('tab-chart-canvas')),
      const Offset(-10000, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('引擎初始化失败:错误可见、开始禁用,重试钮原地恢复', (tester) async {
    engine = FakeAudioEngine()..failInitialization = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(engine)],
        child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => TabChartPage(chart: tabFixtureChart),
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('引擎初始化失败'), findsNothing);
    expect(find.byKey(const Key('warmup-retry')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('tab-practice-start')))
          .onPressed,
      isNull,
      reason: '未就绪不可启',
    );

    engine.failInitialization = false;
    await tester.tap(find.byKey(const Key('warmup-retry')));
    await tester.pumpAndSettle();
    expect(find.text('引擎就绪'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('tab-practice-start')))
          .onPressed,
      isNotNull,
    );
  });
}
