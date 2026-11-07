import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 原谱视图(票05,ADR-0011 阅读路线):WebView 加载矢量谱页的自包含
/// 原样 HTML(alphaTab 官方 CSS + 内嵌 Bravura 字体 + 原 div 原文),
/// 像素级复刻谱站原渲染。只读——缩放/滚动走 WebView 原生手势;跟练/
/// 播放/评分仍由 ScoreIR 自绘谱面视图承载(ADR-0003 双模型不动)。
///
/// 只读姿态:JavaScript 关(纯静态 SVG,无脚本依赖——alphaTab 的字体
/// 走 @font-face,不需要 JS);导航委托全拦(内容自足,外链一律不放行)。
class FaithfulScoreViewPage extends StatelessWidget {
  const FaithfulScoreViewPage({super.key, required this.title, required this.html});

  /// 曲名(应用内命名,AppBar 用)。
  final String title;

  /// 自包含原样 HTML(识谱源 sourceHtml 列原文)。
  final String html;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
      ),
      body: FaithfulScoreBody(html: html),
    );
  }
}

/// 原样渲染体(可嵌页):WebView 控制器 initState 建一次,换 html 不重建
/// (同一页面实例只服务一份谱)。
class FaithfulScoreBody extends StatefulWidget {
  const FaithfulScoreBody({super.key, required this.html});

  final String html;

  @override
  State<FaithfulScoreBody> createState() => _FaithfulScoreBodyState();
}

class _FaithfulScoreBodyState extends State<FaithfulScoreBody> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => NavigationDecision.prevent,
        ),
      )
      ..loadHtmlString(widget.html);
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

/// 原谱 HTML 结构自检(轻量,入页前调):矢量谱页包装必有的三要素。
/// 防御面——旧数据/手改数据坏了给可读错误,不进 WebView 白屏。
String? faithfulHtmlProblem(String html) {
  if (!html.contains('class="at-surface"')) {
    return '原谱缺少渲染面(at-surface)';
  }
  if (!html.contains('@font-face')) {
    return '原谱缺少乐谱字体声明';
  }
  // HTML 以 UTF-8 声明,base64 字体必然 ASCII 安全;utf8 编码不可编码
  // 即数据坏损(理论不可达,Utf8Encoder 不抛——此处恒 false,留作哨兵)。
  try {
    utf8.encode(html);
  } on Object {
    return '原谱文本编码异常';
  }
  return null;
}


// ── 原样流水横带(票06):单行小节序拼接,练习播放头跟拍 ─────────────

/// 从整页原样 HTML 提取的流水横带数据(工作台植入的固定标记节点)。
class FaithfulStripData {
  const FaithfulStripData({
    required this.css,
    required this.stripSvg,
    required this.metaJson,
    required this.width,
    required this.height,
  });

  /// 原样页的 style 块(含 Bravura @font-face 与 .at 规则),横带复用。
  final String css;

  /// 单行横带 SVG(小节按曲序拼接)。
  final String stripSvg;

  /// 横带元信息 JSON(宽高 + 逐小节 x/w)。
  final String metaJson;

  final int width;
  final int height;
}

/// 提取横带(票06 固定标记:div#ukeflow-strip + script#ukeflow-strip-meta)。
/// 无标记 = 源不带流水横带,返回 null(调用方回退自绘横带)。
FaithfulStripData? extractFaithfulStrip(String pageHtml) {
  const nodeMark = '<div id="ukeflow-strip"';
  const metaMark = '<script type="application/json" id="ukeflow-strip-meta">';
  final nodeStart = pageHtml.indexOf(nodeMark);
  final metaStart = pageHtml.indexOf(metaMark);
  if (nodeStart < 0 || metaStart < 0) return null;
  final svgStart = pageHtml.indexOf('>', nodeStart) + 1;
  final svgEnd = pageHtml.indexOf('</div>', svgStart);
  final metaEnd = pageHtml.indexOf('</script>', metaStart);
  if (svgEnd < 0 || metaEnd < 0) return null;
  final stripSvg = pageHtml.substring(svgStart, svgEnd);
  final metaRaw = pageHtml.substring(metaStart + metaMark.length, metaEnd);
  final styleStart = pageHtml.indexOf('<style>');
  final styleEnd = pageHtml.indexOf('</style>');
  final css =
      (styleStart >= 0 && styleEnd > styleStart)
          ? pageHtml.substring(styleStart, styleEnd + 8)
          : '';
  int width = 0;
  int height = 0;
  final wm = RegExp(r'width="(\d+)".*?height="(\d+)"').firstMatch(stripSvg);
  if (wm != null) {
    width = int.parse(wm.group(1)!);
    height = int.parse(wm.group(2)!);
  }
  return FaithfulStripData(
    css: css,
    stripSvg: stripSvg,
    metaJson: metaRaw,
    width: width,
    height: height,
  );
}

/// 原样流水视图:横带单行滚动,练习时播放头固定视口 1/3 处、内容随拍
/// 自动滚动(updateBeat 由拍位驱动;空闲 = 静态横带手动拖读)。
/// WebView JS 仅处理播放头(内容为本地静态 SVG,无外部源)。
class FaithfulStripView extends StatefulWidget {
  const FaithfulStripView({
    super.key = const Key('faithful-strip'),
    required this.data,
    required this.beat,
  });

  final FaithfulStripData data;

  /// 当前主轴拍位(示范/跟练运行中由页面 poll 推送;null = 空闲)。
  final ValueListenable<double?> beat;

  @override
  State<FaithfulStripView> createState() => _FaithfulStripViewState();
}

class _FaithfulStripViewState extends State<FaithfulStripView> {
  /// 播放头/跟滚锚:视口宽的 1/3(与 ScoreSheetLayout 同纪律)。
  static const viewportAnchor = 1 / 3;

  late final WebViewController _controller;
  var _jsReady = false;
  double? _pendingBeat;

  @override
  void initState() {
    super.initState();
    final data = widget.data;
    final wrapper = '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, '
        'initial-scale=1">${data.css}</head>'
        '<body style="margin:0;background:#fff">'
        '<div style="position:relative">${data.stripSvg}</div>'
        '<script>var M=${data.metaJson};'
        'function beatX(b){var i=Math.min(M.bars.length-1,Math.floor(b/4));'
        'var bar=M.bars[i];return bar.x+(b-i*4)*(bar.w/4);}'
        'window.updateBeat=function(b){window.scrollTo('
        'beatX(b)-window.innerWidth/3,0);};</script>'
        '</body></html>';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => NavigationDecision.prevent,
          // 页面装载完成 = JS 可用;先到的拍位补发(竞速收口)。
          onPageFinished: (_) {
            _jsReady = true;
            final pending = _pendingBeat;
            if (pending != null) _onBeatValue(pending);
          },
        ),
      )
      ..loadHtmlString(wrapper);
    widget.beat.addListener(_onBeat);
  }

  @override
  void dispose() {
    widget.beat.removeListener(_onBeat);
    super.dispose();
  }

  void _onBeat() {
    final beat = widget.beat.value;
    if (beat == null) return;
    _onBeatValue(beat);
  }

  void _onBeatValue(double beat) {
    if (!_jsReady) {
      _pendingBeat = beat;
      return;
    }
    _controller.runJavaScript(
      'window.updateBeat(${beat.toStringAsFixed(3)})',
    );
  }

  @override
  Widget build(BuildContext context) {
    // 播放头红线用 Flutter 覆盖层画(票07 机型实录):OEM WebView 对
    // position:fixed 覆盖 div 的合成层滚动前不重绘、滚动后错位——不
    // 依赖 WebView 内 CSS 定位。Flutter 层贴视口左 1/3,与跟滚锚同位。
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          WebViewWidget(controller: _controller),
          Positioned(
            left: constraints.maxWidth * _FaithfulStripViewState.viewportAnchor,
            top: 0,
            bottom: 0,
            width: 2,
            child: ColoredBox(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}