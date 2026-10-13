import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/features/play/tab_chart_page.dart';

/// 指弹谱页(工单 12「能看」):接缝是构造参数——谱面 → 四线谱视图。
/// 零引擎:直接注入内置小星星(渲染对照谱面数据的数据面在
/// builtin_tab_charts_test 已锁),这里锁页面结构与滚动可用性。
void main() {
  Future<void> pumpPage(WidgetTester tester, {bool narrow = false}) async {
    if (narrow) {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: TabChartPage(chart: loadBuiltinTabCharts().first.chart),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('渲染:曲名、元信息、弦号列与谱面画布齐全', (tester) async {
    await pumpPage(tester);

    expect(find.text('小星星'), findsOneWidget);
    expect(find.text('指弹 · 传统童谣 · 90 BPM'), findsOneWidget);
    expect(find.byKey(const Key('tab-chart-labels')), findsOneWidget);
    expect(find.byKey(const Key('tab-chart-canvas')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏(360dp):画布横向可滚,整曲小节可达', (tester) async {
    await pumpPage(tester, narrow: true);

    // 小星星 12 小节在 360dp 视口放不下:画布宽度超出视口,横向拖到
    // 末小节线不抛异常(时值横向位置不因屏窄而截断)。
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
}
