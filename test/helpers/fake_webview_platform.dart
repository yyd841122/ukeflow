import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// webview_flutter 测试桩(票06):平台视图在 widget 测试不可渲染——
/// fake 平台让 FaithfulStripView/原样视图可 pump,并捕获 loadHtmlString
/// 的入参供断言(横带页/整页包装是否正确组装)。JS 调用记录为列表。
class FakeWebViewPlatform extends WebViewPlatform {
  /// 各实例按创建序收到的 loadHtmlString 入参(测试断言用)。
  final List<String> loadedHtml = [];

  /// 按创建序的控制器实例(JS 调用/原生滚动记录在实例上,取 last)。
  final List<FakeWebViewController> controllers = [];

  /// 最新实例的 JS 调用记录(单实例场景即全部;票08 染色断言用)。
  List<String> get javaScriptRuns => controllers.last.javaScriptRuns;

  /// 最新实例的原生 scrollTo 记录(单实例场景即全部;票08 滚动断言用)。
  List<String> get scrollCalls => controllers.last.scrollCalls;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakeWebViewController(params);
    loadedHtml.clear();
    controller.onLoadHtmlString = loadedHtml.add;
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _FakeWidget(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return _FakeNavigationDelegate(params);
  }
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  final List<String> navigationRequests = [];

  /// 装载完成回调(真平台装载即发;fake 在 loadHtmlString 后触发,
  /// 让依赖 onPageFinished 的状态(如装载遮罩退场)可 pumpAndSettle)。
  void Function(String url)? _pageFinished;

  void firePageFinished() => _pageFinished?.call('about:blank');

  @override
  Future<void> setOnNavigationRequest(
    void Function(NavigationRequest request) onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageStarted(void Function(String url) onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(void Function(String url) onPageFinished) async {
    _pageFinished = onPageFinished;
  }

  @override
  Future<void> setOnUrlChange(void Function(UrlChange change) onUrlChange) async {}

  @override
  Future<void> setOnProgress(void Function(int progress) onProgress) async {}
}

/// 控制器桩:记录 runJavaScript 与 scrollTo 入参供断言。
class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  late final void Function(String html) onLoadHtmlString;

  final List<String> javaScriptRuns = [];

  /// 原生 scrollTo 调用记录("x,y"),票08 滚动驱动断言用。
  final List<String> scrollCalls = [];

  _FakeNavigationDelegate? _delegate;

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate delegate,
  ) async {
    _delegate = delegate as _FakeNavigationDelegate?;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    onLoadHtmlString(html);
    // 真平台装载完成即回 onPageFinished(微任务级,测试可 settle)。
    final delegate = _delegate;
    if (delegate != null) scheduleMicrotask(delegate.firePageFinished);
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    javaScriptRuns.add(javaScript);
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  // 基类经由 setPlatformNavigationDelegate 派发;此成员非继承面。
  Future<void> setNavigationDelegate(
    PlatformNavigationDelegate delegate,
  ) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {}

  @override
  Future<void> removeJavaScriptChannel(String name) async {}

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {}

  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage consoleMessage) onConsoleMessage,
  ) async {}

  @override
  Future<void> setOnScrollPositionChange(
    void Function(ScrollPositionChange scrollPositionChange)?
        onScrollPositionChange,
  ) async {}

  @override
  Future<void> setOnJavaScriptAlertDialog(
    Future<void> Function(JavaScriptAlertDialogRequest request)
        onJavaScriptAlertDialog,
  ) async {}

  @override
  Future<void> setOnJavaScriptConfirmDialog(
    Future<bool> Function(JavaScriptConfirmDialogRequest request)
        onJavaScriptConfirmDialog,
  ) async {}

  @override
  Future<String?> currentUrl() async => null;

  @override
  Future<void> scrollTo(int x, int y) async {
    scrollCalls.add('$x,$y');
  }

  @override
  Future<void> scrollBy(int x, int y) async {}
}

/// JSON 便利:断言 wrapper 含横带内容(横带元信息脚本+SVG)。
bool containsStripContent(String html) =>
    html.contains('var M=') && html.contains('<svg');

class _FakeWidget extends PlatformWebViewWidget {
  _FakeWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
