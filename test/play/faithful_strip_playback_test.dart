import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/features/play/faithful_score_view.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../helpers/fake_webview_platform.dart';

/// 票08:横带跟滚/染色的驱动真值测试。
///
/// 视图内置 ticker 采样引擎时钟:跟滚/染色按列变化率单发 `UF.seek`
/// (页内 rAF 逐帧 transform 平滑——OEM WebView 的原生 scrollTo 连续
/// 目标下被限速,机检实测弃用);暂停检出后单发 `UF.hold()`;停止单发
/// `UF.follow(0)`。测试用 fake 平台捕获 JS 指令,ticker 由 pump 驱动,
/// 无真实定时器/fakeAsync(避开 OEM/fake zone 已知坑)。
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
    // 装载 future/页完成回调落地(遮罩退场、seek 补发挂上)。
    await tester.pump();
    await tester.pump();
  }

  testWidgets('装载:包装含曲头余量/列网格/rAF 跟滚脚本;遮罩退场',
      (tester) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    final tl = FaithfulStripTimeline()..clock = () => null;
    await pumpStrip(tester, tl);

    final platform = WebViewPlatform.instance as FakeWebViewPlatform;
    final html = platform.loadedHtml.single;
    expect(html, contains('padding-left:120.0px'), reason: '视口 360 → 宽/3');
    expect(html, contains('padding-right:240.0px'));
    expect(html.contains('innerWidth'), isFalse);
    expect(html, contains('cols:[0.0,25.0'));
    expect(html, contains('will-change:transform'), reason: 'rAF transform 跟滚');
    expect(html, contains('UF.seek'));
    expect(html, contains('requestAnimationFrame'));
    expect(find.byType(FaithfulStripView), findsOneWidget);
  });

  testWidgets('预备期:负拍 seek(-x) 染色还原;曲头内容 0 由页面钳到线上',
      (tester) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    Duration? now = const Duration(milliseconds: -2250); // 预备第 3 拍
    final tl = FaithfulStripTimeline()..clock = () => now;
    await pumpStrip(tester, tl);

    final platform = WebViewPlatform.instance as FakeWebViewPlatform;
    tl.anchor.value = (t0: Duration.zero, periodMs: 750);
    await tester.pump();

    expect(platform.javaScriptRuns.single, 'UF.seek(-3.0000,750)',
        reason: '负拍 seek:页内钳 0(曲头 0 在线上等待)+ 染色全还原');
    expect(platform.javaScriptRuns.length, 1, reason: '预备期内同列去重');

    // 预备走完前时钟仍在走(未暂停):无 hold。
    now = const Duration(milliseconds: -100);
    await tester.pump();
    expect(platform.javaScriptRuns.length, 1);
  });

  testWidgets('运行:seek 按列变化单发;暂停检出冻结页内死推', (tester) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    Duration? now = Duration.zero;
    final tl = FaithfulStripTimeline()..clock = () => now;
    await pumpStrip(tester, tl);

    final platform = WebViewPlatform.instance as FakeWebViewPlatform;
    tl.anchor.value = (t0: Duration.zero, periodMs: 750);
    await tester.pump();

    // 拍 0:第 0 列首发 seek。
    expect(platform.javaScriptRuns.single, 'UF.seek(0.0000,750)');

    // 拍 0.4(300ms):仍在第 0 列,不重发。
    now = const Duration(milliseconds: 300);
    await tester.pump();
    expect(platform.javaScriptRuns.length, 1, reason: '同列去重');

    // 拍 0.6(450ms):推进到第 1 列,seek 携带精确拍位。
    now = const Duration(milliseconds: 450);
    await tester.pump();
    expect(platform.javaScriptRuns.last, 'UF.seek(0.6000,750)');

    // 拍 0.9(675ms):仍在第 1 列,不发。
    now = const Duration(milliseconds: 675);
    await tester.pump();
    expect(platform.javaScriptRuns.length, 2);

    // 暂停(时钟冻结):连续 8 帧检出 → hold 单发一次,此后零下发。
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    expect(platform.javaScriptRuns.last, 'UF.hold()');
    expect(
      platform.javaScriptRuns.where((s) => s == 'UF.hold()').length,
      1,
      reason: '持续暂停不重复 hold',
    );
  });

  testWidgets('回到开头:锚刷新重置驱动,负拍 seek 归零;停止 follow(0) 复位',
      (tester) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    Duration? now = const Duration(seconds: 5);
    final tl = FaithfulStripTimeline()..clock = () => now;
    await pumpStrip(tester, tl);

    final platform = WebViewPlatform.instance as FakeWebViewPlatform;
    tl.anchor.value = (t0: Duration.zero, periodMs: 750);
    now = const Duration(seconds: 3); // 曲中:拍 4(第 2 小节头)
    await tester.pump();
    expect(platform.javaScriptRuns.last, 'UF.seek(4.0000,750)');

    // 回到开头:锚重定(曲头负拍期)→ 驱动重置 → 立即重发负拍 seek。
    tl.anchor.value = (t0: const Duration(seconds: 4), periodMs: 750);
    now = const Duration(seconds: 3);
    await tester.pump();
    expect(platform.javaScriptRuns.last, 'UF.seek(-1.3333,750)');

    // 停止:锚与时钟同刻归 null → ticker 自停 + follow(0) 全复位。
    final jsCount = platform.javaScriptRuns.length;
    now = null;
    tl.anchor.value = null;
    await tester.pump();
    expect(platform.javaScriptRuns.length, jsCount + 1);
    expect(platform.javaScriptRuns.last, 'UF.follow(0)');
  });
}
