import 'package:ukeflow/features/library/cifraclub_driver.dart';

/// 工单 27 共用假驱动(cifraclub_import/cifraclub_search 两组测试)。
/// 脚本化:loadRequest 记录、currentUrl 逐个出队、JS 返回值逐个出队
/// (取尽后 null);onLoaded/onScript 是调用返回前的观察点(测试借它
/// 插并发操作)。全部真 async,延时由被测方的 timings 注入零值。
class FakeCifraDriver implements CifraClubDriver {
  List<Uri> loaded = [];
  List<String> scripts = [];
  List<Object?> jsResults = [];
  List<String?> urls = [];

  Future<void> Function(Uri url)? onLoaded;
  Future<void> Function(String script)? onScript;

  @override
  Future<void> loadRequest(Uri url) async {
    loaded.add(url);
    await onLoaded?.call(url);
  }

  @override
  Future<String?> currentUrl() async =>
      urls.isNotEmpty ? urls.removeAt(0) : null;

  @override
  Future<Object?> runJavaScriptReturningResult(String source) async {
    scripts.add(source);
    await onScript?.call(source);
    return jsResults.isNotEmpty ? jsResults.removeAt(0) : null;
  }
}

/// 桥抛异常的驱动(WebView 桥错误路径)。
class ThrowingCifraDriver implements CifraClubDriver {
  @override
  Future<void> loadRequest(Uri url) async => throw Exception('bridge dead');

  @override
  Future<String?> currentUrl() async => null;

  @override
  Future<Object?> runJavaScriptReturningResult(String source) async =>
      throw Exception('bridge dead');
}
