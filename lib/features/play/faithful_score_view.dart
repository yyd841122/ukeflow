import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
/// 一小节的横带几何(曲序 x 起点 + 印张宽;Dart 端 beatX 用)。
class FaithfulStripBar {
  const FaithfulStripBar(this.x, this.w);

  final double x;
  final double w;
}

class FaithfulStripData {
  const FaithfulStripData({
    required this.css,
    required this.stripSvg,
    required this.metaJson,
    required this.width,
    required this.height,
    required this.bars,
  });

  /// 原样页的 style 块(含 Bravura @font-face 与 .at 规则),横带复用。
  final String css;

  /// 单行横带 SVG(小节按曲序拼接)。
  final String stripSvg;

  /// 横带元信息 JSON(宽高 + 逐小节 x/w)。
  final String metaJson;

  final int width;
  final int height;

  /// 逐小节几何(4 拍/小节线性插值的锚;票07 起滚动锚由 Dart 计算,
  /// 不再依赖页面 JS——OEM WebView 的 JS 桥会 jam/丢调用)。
  final List<FaithfulStripBar> bars;
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
  List<FaithfulStripBar> bars = const [];
  try {
    final meta = jsonDecode(metaRaw) as Map;
    bars = [
      for (final b in (meta['bars'] as List? ?? const []))
        FaithfulStripBar(
          ((b as Map)['x'] as num).toDouble(),
          (b['w'] as num).toDouble(),
        ),
    ];
  } on Object {
    bars = const []; // 坏 meta:静态读谱可用,跟滚锚缺失不滚(见视图)。
  }
  return FaithfulStripData(
    css: css,
    stripSvg: stripSvg,
    metaJson: metaRaw,
    width: width,
    height: height,
    bars: bars,
  );
}

/// 横带时间线:页持有(票07),轮询把主轴拍位推给视图;视图用
/// **原生 scrollTo**(平台方法,不走 JS 桥)驱动滚动。
class FaithfulStripTimeline {
  /// 当前主轴拍位(运行中每轮询更新;null = 空闲/暂停冻结)。
  final ValueNotifier<double?> beat = ValueNotifier<double?>(null);

  /// 暂停冻结:置 null(视图停止跟随;恢复后下一轮询续上)。
  void freeze() => beat.value = null;
}

/// 原样流水视图:横带单行滚动。空闲 = 静态读谱(手动拖);运行 =
/// 播放头固定视口 1/3、内容随拍自动滚——滚动走 **原生 scrollTo**
/// (票07 机型实录:OEM WebView 对高频 runJavaScript 会 jam 丢调用、
/// rAF 在合成层闲置时也可能节流;平台方法不经过 JS 桥,无此毛病)。
/// 锚点用 Dart 视口宽的 1/3,不信页面 innerWidth(OEM 曾错报)。
class FaithfulStripView extends StatefulWidget {
  const FaithfulStripView({
    super.key = const Key('faithful-strip'),
    required this.data,
    this.timeline,
  });

  final FaithfulStripData data;

  /// 时间线(null = 纯静态读谱,如导入预览页)。
  final FaithfulStripTimeline? timeline;

  @override
  State<FaithfulStripView> createState() => _FaithfulStripViewState();
}

class _FaithfulStripViewState extends State<FaithfulStripView> {
  /// 播放头/跟滚锚:视口宽的 1/3(与 ScoreSheetLayout 同纪律)。
  static const viewportAnchor = 1 / 3;

  late final WebViewController _controller;
  double? _viewWidth;
  var _jsReady = false;
  Timer? _jsArmFallback;

  @override
  void initState() {
    super.initState();
    final data = widget.data;
    final wrapper = '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, '
        'initial-scale=1">${data.css}</head>'
        '<body style="margin:0;background:#fff">'
        '<div style="position:relative">${data.stripSvg}</div>'
        // 尾部余量由 JS 设(视口 2/3):曲末最后一段内容也能滚过播放头
        // 线,不提前钳停(票07 用户实录);仅装载期一发,自愈见 _armJs。
        '<script>var M=${data.metaJson};'
        'function arm(){document.body.style.minWidth='
        '(M.width+window.innerWidth*0.67)+"px";}'
        'arm();</script>'
        '</body></html>';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => NavigationDecision.prevent,
          onPageFinished: (_) => _armJs(),
        ),
      )
      ..loadHtmlString(wrapper).then((_) => _armJs());
    // 兜底:OEM WebView 偶发 onPageFinished 迟到;missed 时尾部余量
    // 缺失(读谱不受影响),arm 后不重试 JS——原生滚动不依赖 JS。
    _jsArmFallback = Timer(const Duration(milliseconds: 1500), _armJs);
    widget.timeline?.beat.addListener(_onBeat);
  }

  /// 开闸(幂等;onPageFinished/装载 future/兜底定时器三方竞争)。
  void _armJs() {
    if (!mounted || _jsReady) return;
    _jsReady = true;
    _jsArmFallback?.cancel();
    _jsArmFallback = null;
  }

  @override
  void dispose() {
    _jsArmFallback?.cancel();
    widget.timeline?.beat.removeListener(_onBeat);
    super.dispose();
  }

  void _onBeat() {
    final beat = widget.timeline?.beat.value;
    if (beat == null || _viewWidth == null || widget.data.bars.isEmpty) {
      return;
    }
    final x = _beatX(beat) - _viewWidth! * viewportAnchor;
    _controller.scrollTo(x.floor(), 0);
  }

  /// 主轴拍位 → 横带内容 x(css px):小节序线性 + 小节内按拍线性
  /// (与页面 JS 版 beatX 同式;弱起小节印张按 4 拍铺满,同一插值)。
  double _beatX(double beat) {
    final bars = widget.data.bars;
    var i = (beat / 4).floor();
    if (i < 0) i = 0;
    if (i > bars.length - 1) i = bars.length - 1;
    final bar = bars[i];
    return bar.x + (beat - i * 4) * (bar.w / 4);
  }

  @override
  Widget build(BuildContext context) {
    // 播放头红线 = Flutter 覆盖层(票07 机型实录:OEM WebView 对
    // position:fixed 覆盖 div 的合成层滚动前不重绘、滚动后错位)。
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewWidth = constraints.maxWidth;
        return Stack(
          children: [
            WebViewWidget(controller: _controller),
            Positioned(
              left: constraints.maxWidth * viewportAnchor,
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
        );
      },
    );
  }
}
