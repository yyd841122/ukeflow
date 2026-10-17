/// Cifra Club 页内取数的 WebView 驱动最小面(工单 27):真机由
/// WebViewController 适配,测试用 fake——让导入/搜索的**编排逻辑**
/// (导航令牌、ukulele 优先回退、就绪重试)可以离开真机做单测
/// (17/30 时代这些逻辑只靠真机验收覆盖)。
library;

import 'package:webview_flutter/webview_flutter.dart';

abstract interface class CifraClubDriver {
  /// 载入页面(等价 loadRequest;导航由页面的 NavigationDelegate 放行)。
  Future<void> loadRequest(Uri url);

  /// 当前页 URL(不可得时 null)。
  Future<String?> currentUrl();

  /// 在页面里执行 JS 并取返回值(Android 桥对字符串返回值可能再包一层
  /// JSON 引号,解码侧剥两层,见 core/chart/cifra_extract.dart)。
  Future<Object?> runJavaScriptReturningResult(String source);
}

/// [WebViewController] 适配(真机)。
class WebViewDriver implements CifraClubDriver {
  const WebViewDriver(this.controller);

  final WebViewController controller;

  @override
  Future<void> loadRequest(Uri url) => controller.loadRequest(url);

  @override
  Future<String?> currentUrl() => controller.currentUrl();

  @override
  Future<Object?> runJavaScriptReturningResult(String source) =>
      controller.runJavaScriptReturningResult(source);
}
