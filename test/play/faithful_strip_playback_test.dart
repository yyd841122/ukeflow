import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/features/play/faithful_score_view.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../helpers/fake_webview_platform.dart';

/// 票08:横带跟滚/染色的逐帧驱动真值测试。
///
/// 视图内置 ticker(vsync):拍位每帧按引擎时钟缝(clock 闭包)现算,
/// 滚动走原生 scrollTo(平台方法),染色按列变化率经 JS 桥单发幂等
/// 指令。测试用 fake 平台捕获两类调用,ticker 由 pump 驱动,无真实
/// 定时器/fakeAsync(避开 OEM/fake zone 已知坑)。
void main() {
  // 2 小节 × 200px(每拍 50px、每八分列 25px),♩=80 → 拍周期 750ms。
  const data = FaithfulStripData(
    css: '<style>@font-face{}</style>',
    stripSvg: '<svg xmlns="http://www.w3.org/2000/svg" width="400" '
        'height="148" viewBox="0 0 400 148"></svg>',
    metaJson: '{"width":400,"height":148,'
        '"bars":[{"bar":1,"x":0.0,"w":200.0},{"bar":2,"x":200.0,"w":200.0}]}',
    width: 400,
    height: 148,
    bars: [FaithfulStripBar(0, 200), FaithfulStripBar(200, 200)],
  );

  Future<void> pumpStrip(WidgetTester tester, FaithfulStripTimeline tl) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 150,
            child: FaithfulStripView(data: data, timeline: tl),
          ),
        ),
      ),
    );
    // postFrame 起装载(曲头余量要视口宽,推迟到布局帧);再一帧让
    // 装载 future/页完成回调落地(遮罩退场、染色补发挂上)。
    await tester.pump();
    await tester.pump();
  }

  testWidgets('装载:包装含曲头余量与列网格;遮罩退场', (tester) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    final tl = FaithfulStripTimeline()..clock = () => null;
    await pumpStrip(tester, tl);

    final platform = WebViewPlatform.instance as FakeWebViewPlatform;
    final html = platform.loadedHtml.single;
    expect(html, contains('padding-left:120.0px'), reason: '视口 360 → 宽/3');
    expect(html, contains('padding-right:240.0px'));
    expect(html.contains('innerWidth'), isFalse);
    expect(html, contains('cols:[0.0,25.0'));
    expect(find.byType(FaithfulStripView), findsOneWidget);
  });

  testWidgets('预备期:曲头 0 落线(钳 0)+ paint(-1) 全还原', (tester) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    Duration? now = const Duration(milliseconds: -2250); // 预备第 3 拍
    final tl = FaithfulStripTimeline()..clock = () => now;
    await pumpStrip(tester, tl);

    final platform = WebViewPlatform.instance as FakeWebViewPlatform;
    tl.anchor.value = (t0: Duration.zero, periodMs: 750);
    await tester.pump();

    expect(platform.scrollCalls, ['0,0'], reason: '负拍钳 0:曲头在线上等待');
    expect(platform.javaScriptRuns.last, 'UF.paint(-1)');
    expect(platform.scrollCalls.length, 1, reason: '预备期内同目标去重');

    // 预备走完,拍 0 未到:仍钳 0,无新指令。
    now = const Duration(milliseconds: -100);
    await tester.pump();
    expect(platform.scrollCalls.length, 1);
    expect(platform.javaScriptRuns.length, 1);
  });

  testWidgets('运行:滚动按拍线性逐帧推进,染色按列变化单发', (tester) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    Duration? now = Duration.zero;
    final tl = FaithfulStripTimeline()..clock = () => now;
    await pumpStrip(tester, tl);

    final platform = WebViewPlatform.instance as FakeWebViewPlatform;
    tl.anchor.value = (t0: Duration.zero, periodMs: 750);
    await tester.pump();

    // 拍 0.4:内容 x=20(每拍 50px),第 0 列染色首发。
    now = const Duration(milliseconds: 300);
    await tester.pump();
    expect(platform.scrollCalls, contains('20,0'));
    expect(platform.javaScriptRuns.last, 'UF.paint(0)');

    // 拍 0.6:x=30,推进到第 1 列。
    now = const Duration(milliseconds: 450);
    await tester.pump();
    expect(platform.scrollCalls.last, '30,0');
    expect(platform.javaScriptRuns.last, 'UF.paint(1)');

    // 拍 0.9:x=45 仍在第 1 列(0.75s 才换列):滚动照发,染色不发。
    final jsCount = platform.javaScriptRuns.length;
    now = const Duration(milliseconds: 675);
    await tester.pump();
    expect(platform.scrollCalls.last, '45,0');
    expect(platform.javaScriptRuns.length, jsCount, reason: '同列去重');

    // 暂停(时钟冻结):同拍位,零下发。
    now = const Duration(milliseconds: 675);
    await tester.pump();
    expect(platform.scrollCalls.length, 4);
    expect(platform.javaScriptRuns.length, jsCount);
  });

  testWidgets('回到开头:锚刷新负拍 → 滚回 0 + paint(-1);停止 → 还原自停',
      (tester) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    Duration? now = const Duration(seconds: 5);
    final tl = FaithfulStripTimeline()..clock = () => now;
    await pumpStrip(tester, tl);

    final platform = WebViewPlatform.instance as FakeWebViewPlatform;
    tl.anchor.value = (t0: Duration.zero, periodMs: 750);
    now = const Duration(seconds: 3); // 曲中:拍 4(第 2 小节头)
    await tester.pump();
    expect(platform.scrollCalls.last, '200,0');
    expect(platform.javaScriptRuns.last, 'UF.paint(8)');

    // 回到开头:锚重定(曲头负拍期)。
    tl.anchor.value = (
      t0: const Duration(seconds: 4),
      periodMs: 750,
    );
    now = const Duration(seconds: 3);
    await tester.pump();
    expect(platform.scrollCalls.last, '0,0', reason: '负拍钳 0 滚回曲头');
    expect(platform.javaScriptRuns.last, 'UF.paint(-1)');

    // 停止:锚与时钟同刻归 null → ticker 自停 + 当弹列还原。
    final jsCount = platform.javaScriptRuns.length;
    now = null;
    tl.anchor.value = null;
    await tester.pump();
    await tester.pump();
    expect(platform.javaScriptRuns.length, jsCount,
        reason: '最后状态已是 -1(还原过),停止不重发');
  });
}
