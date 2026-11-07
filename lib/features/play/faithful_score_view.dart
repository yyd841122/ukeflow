import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:webview_flutter/webview_flutter.dart';

/// 原站播放高亮红(票08,用户录屏 15 帧逐帧众数 RGB(200,97,109)):
/// 站方播放头线与「当弹」字形同色——线色即染色色,常量两处共用。
const Color faithfulHighlightRed = Color(0xFFC8616D);

/// 同上色的 CSS 形态(横带页 JS 染色用)。
const String _highlightRedCss = '#c8616d';

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

/// 会话锚(曲头时刻 t0 + 拍周期 ms),与控制器 visualAnchor 同构。
typedef StripAnchor = ({Duration t0, double periodMs});

/// 横带时间线:页持有(票08),轮询把会话锚推给 [anchor];视图内置
/// ticker 按 [clock](引擎时钟缝,页装填控制器的 visualNow 原样)逐帧
/// 驱动原生 scrollTo 与染色。ADR-0005 不破:唯一时间源仍是引擎时钟,
/// 页把缝原样递给视图,页内无第二时间源。暂停 = 引擎时钟冻结(同一
/// 拍位反复算出同一目标,视图侧去重后零下发);未运行 = 缝返回 null,
/// ticker 自停。
class FaithfulStripTimeline {
  /// 当前会话锚;null = 未运行。记录等值(字段同值)不重复通知。
  final ValueNotifier<StripAnchor?> anchor = ValueNotifier<StripAnchor?>(null);

  /// 引擎时钟缝:运行中 = 引擎当前时刻,暂停 = 冻结时刻,未运行 null。
  Duration? Function()? clock;
}

/// 染色列驱动(票08,幂等重发自愈):算当前拍位应染的列号,与上次
/// 不同才返回(去重);列倒退(回到开头/循环接遍)照发——paint 是
/// 绝对状态指令,任意时刻重发都收敛到正确状态,-1 = 全还原(预备期/
/// 停止还原)。
class StripColorDriver {
  int? _last;

  /// 上次下发的列号(装载完成后补发用;从未发过 null)。
  int? get last => _last;

  void reset() => _last = null;

  /// 拍位 → 列号:无变化 null;预备期(负拍)-1;越界钳两端。
  int? update(double beat, int columnCount) {
    if (columnCount <= 0) return null;
    final k = stripColorColumn(beat, columnCount);
    if (k == _last) return null;
    _last = k;
    return k;
  }
}

/// 染色列边界(八分网格):k 列覆盖拍 [0.5k, 0.5k+0.5],x 与滚动锚
/// 同一插值——染色永远钉在移动的播放头上。0 号列起点 = 曲头;
/// 每小节 8 列(4 拍 × 2),与 [_FaithfulStripViewState] 的列数同源。
List<double> faithfulStripColumnBounds(FaithfulStripData data) {
  final bars = data.bars;
  if (bars.isEmpty) return const [];
  return [
    for (var k = 0; k <= bars.length * 8; k++)
      faithfulStripBeatX(data, k * 0.5),
  ];
}

/// 拍位 → 染色列号(八分网格):预备期负拍 -1,越界钳两端。
int stripColorColumn(double beat, int columnCount) => beat < 0
    ? -1
    : (beat * 2).floor().clamp(0, columnCount - 1);

/// 主轴拍位 → 横带内容 x(css px):小节序线性 + 小节内按拍线性
/// (弱起小节印张按 4 拍铺满,同一插值);负拍钳 0(预备期曲头在
/// 线上等待),超出末小节钳末缘。
double faithfulStripBeatX(FaithfulStripData data, double beat) {
  final bars = data.bars;
  if (bars.isEmpty) return 0;
  if (beat < 0) beat = 0;
  var i = (beat / 4).floor();
  if (i > bars.length - 1) {
    i = bars.length - 1;
  }
  final bar = bars[i];
  final local = (beat - i * 4) * (bar.w / 4);
  return i == bars.length - 1 && local > bar.w ? bar.x + bar.w : bar.x + local;
}

/// 横带页包装(纯函数,票08):曲头左余量 = 视口宽/3、曲尾右余量 =
/// 视口宽×2/3,随装载一次性烘进 padding——scrollTo(0) 时曲头位置 0
/// 恰落在播放头线上,流过末小节恰好触线而止(maxScroll = 横带宽)。
/// 几何数字一律 Dart 算好注入,**禁用页面 innerWidth**(OEM 报值不可信,
/// 曾把内容整体推出屏外成白板)。染色索引脚本同页内联:装载后建
/// 「数字字形按 x 分列桶」索引,paint(n) 绝对状态幂等,丢发自愈。
String faithfulStripWrapper(FaithfulStripData data, double viewportWidth) {
  final lead = (viewportWidth / 3).toStringAsFixed(1);
  final tail = (viewportWidth * 2 / 3).toStringAsFixed(1);
  final cols = faithfulStripColumnBounds(data)
      .map((x) => x.toStringAsFixed(1))
      .join(',');
  return '<!DOCTYPE html><html><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, '
      'initial-scale=1">${data.css}</head>'
      '<body style="margin:0;background:#fff">'
      '<div id="ufs" style="position:relative;padding-left:${lead}px;'
      'padding-right:${tail}px">${data.stripSvg}</div>'
      '<script>var M={cols:[$cols]};$_stripIndexJs</script>'
      '</body></html>';
}

/// 染色索引与改色脚本(票08,随横带页内联一次;不经 JS 桥,OEM jam 面零)。
///
/// 视频帧实证(用户录屏,票08):站方播放染色只有两态——**当弹**列的
/// 品数字形变红(与播放头线同色),其余一切(已弹/未弹/谱线/符干/
/// 和弦名/小节号)保持原样不变。可染元素 = 纯数字 text 且字号 ≥ 全页
/// 最大数字字号×0.9(品数字 10.92px 入选,小节号 9.24px 淘汰;两首
/// 实测比值 0.85/0.69,均在界外)。索引建在字体就绪后(Bravura 晚到
/// 会改字形度量),2.5s 兜底;横带是嵌套 svg 裁切——每片含整系统 body
/// 副本,按「元素中心落在该片盒内」判定可见副本,strip x = 片 x +
/// (中心 − 片左缘)。paint(n) 全量重刷 = 幂等,pending 暂存建索引前
/// 到达的指令。
final String _stripIndexJs = '''
var UF={p:null,b:null};
UF.paint=function(n){UF.p=n;if(UF.b)UF.a();};
UF.a=function(){var n=UF.p;if(n==null||!UF.b)return;UF.p=null;
 var bs=UF.b;
 for(var i=0;i<bs.length;i++){var arr=bs[i];if(!arr.length)continue;
  var f=(i==n)?'$_highlightRedCss':null;
  for(var j=0;j<arr.length;j++){arr[j][0].setAttribute('fill',f!=null?f:arr[j][1]);}
 }};
UF.build=function(){
 if(UF.b)return;
 var svg=document.querySelector('#ufs svg');if(!svg)return;
 var i,j,slices=[],ss=svg.querySelectorAll('svg');
 for(i=0;i<ss.length;i++){var s=ss[i];
  var vb=s.getAttribute('viewBox');if(!vb)continue;
  var vp=vb.split(' ');var lo=parseFloat(vp[0]),w=parseFloat(vp[2]);
  var r=s.getBoundingClientRect();
  slices.push([parseFloat(s.getAttribute('x'))||0,lo,lo+w,r.left,r.left+w]);}
 var ts=svg.querySelectorAll('text'),cand=[],mx=0;
 for(i=0;i<ts.length;i++){var t=ts[i];
  var c=(t.textContent||'').trim();
  if(!/^[0-9]+\$/.test(c))continue;
  var fs=parseFloat(getComputedStyle(t).fontSize)||0;
  if(fs>mx)mx=fs;
  var rc=t.getBoundingClientRect();
  cand.push([rc.left+rc.width/2,fs,t]);}
 if(mx<=0||!slices.length)return;
 var lim=mx*0.9,cols=M.cols,bs=[];
 for(i=0;i<cols.length-1;i++)bs.push([]);
 for(i=0;i<cand.length;i++){
  if(cand[i][1]<lim)continue;
  var cx=cand[i][0];
  for(j=0;j<slices.length;j++){var sl=slices[j];
   if(cx>=sl[3]&&cx<=sl[4]){
    var sx=sl[0]+(cx-sl[3]);
    var k=0;while(k<cols.length-2&&cols[k+1]<=sx)k++;
    bs[k].push([cand[i][2],cand[i][2].getAttribute('fill')||'#000']);
    break;}}}
 UF.b=bs;UF.a();
};
if(document.fonts&&document.fonts.ready&&document.fonts.ready.then){
 document.fonts.ready.then(function(){UF.build();});
}else{UF.build();}
setTimeout(function(){if(!UF.b)UF.build();},2500);
''';

/// 原样流水视图:横带单行滚动。空闲 = 静态读谱(手动拖);运行 =
/// **ticker 逐帧驱动**(票08:vsync 同频,拍位每帧按引擎时钟现算,
/// 去掉 16ms 轮询定时器的抖动——原生 scrollTo 平台方法不走 JS 桥,
/// OEM jam 面)。播放头恒在视口 1/3:曲头左余量已烘进页面 padding
/// (票08,scrollTo(0) 时曲头 0 恰在线上),滚动目标 = 弹奏位内容 x。
/// 锚点用 Dart 视口宽的 1/3,不信页面 innerWidth(OEM 曾错报)。
/// 播放染色同帧驱动:列变化率(~0.375s)经 JS 桥单发 UF.paint(k),
/// 绝对状态幂等,丢发下一列自愈。
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

class _FaithfulStripViewState extends State<FaithfulStripView>
    with SingleTickerProviderStateMixin {
  /// 播放头/跟滚锚:视口宽的 1/3(与 ScoreSheetLayout 同纪律)。
  static const viewportAnchor = 1 / 3;

  late final WebViewController _controller;
  late final Ticker _ticker;
  double? _viewWidth;

  /// 已按此视口宽装载(旋转/分屏改宽 >1px 才付重装代价——OEM 装 3MB
  /// 页要数秒)。null = 尚未装载(推迟到首个布局帧,曲头余量要视口宽)。
  double? _bakedWidth;
  var _pageReady = false;
  Timer? _jsArmFallback;

  /// 染色驱动 + 装载完成补发标记(装载期被 OEM 丢掉的 paint 靠它自愈)。
  final StripColorDriver _color = StripColorDriver();
  var _colorsPrimed = false;

  /// 原生滚动去重缓存(暂停/等待期零下发;-1 = 未滚过)。
  var _lastScrollX = -1;

  /// 装载代数:换宽重装后,旧装载的 future/回调过期不置就绪。
  var _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => NavigationDecision.prevent,
          onPageFinished: (_) => _loaded(),
        ),
      );
    widget.timeline?.anchor.addListener(_onAnchor);
    // 会话已在跑(GlobalKey 重挂/运行中换树槽):ticker 续上。
    if (widget.timeline?.anchor.value != null) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant FaithfulStripView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 复用实例(GlobalKey 重挂)时 timeline 可能换绑:重接监听。
    if (!identical(oldWidget.timeline, widget.timeline)) {
      oldWidget.timeline?.anchor.removeListener(_onAnchor);
      widget.timeline?.anchor.addListener(_onAnchor);
      if (widget.timeline?.anchor.value != null && !_ticker.isActive) {
        _ticker.start();
      }
    }
  }

  /// 会话锚到位(开始/循环接遍):起 ticker。停止由 _onFrame 的时钟
  /// 空转自停(anchor 与 clock 同刻变 null,见控制器 visualNow)。
  void _onAnchor() {
    if (widget.timeline?.anchor.value != null && !_ticker.isActive) {
      _lastScrollX = -1;
      _ticker.start();
    }
  }

  /// 装载就绪(幂等;onPageFinished/装载 future/兜底定时器三方竞争):
  /// 遮罩退场 + 补发当前染色列(装载期被 OEM 丢掉的 paint 自愈;
  /// 原生滚动不依赖 JS,无需就绪门)。
  void _loaded() {
    if (!mounted) return;
    _jsArmFallback?.cancel();
    _jsArmFallback = null;
    if (!_pageReady) {
      setState(() => _pageReady = true); // 遮罩退场(触发重绘)
    }
    if (!_colorsPrimed) {
      _colorsPrimed = true;
      final k = _color.last;
      if (k != null) _runJs('UF.paint($k)');
    }
  }

  /// 视口宽就位(首个布局帧)或变了(旋转/分屏):重烘重装。幂等,
  /// 每次 build 后调用无代价。
  void _ensureLoaded(double width) {
    if (width <= 0) return;
    final baked = _bakedWidth;
    if (baked != null && (width - baked).abs() < 1) return;
    _bakedWidth = width;
    _pageReady = false;
    _colorsPrimed = false;
    _color.reset();
    setState(() {}); // 重装期遮罩回归(post-frame 调用,合法)
    _jsArmFallback?.cancel();
    final gen = ++_loadGen;
    _controller
        .loadHtmlString(faithfulStripWrapper(widget.data, width))
        .then((_) {
      if (gen == _loadGen) _loaded();
    });
    // 兜底双保险(票07 机型实录):OEM WebView 的 onPageFinished 偶发
    // 迟到/丢失,装载 future 与 1.5s 定时器同样置就绪。
    _jsArmFallback = Timer(const Duration(milliseconds: 1500), () {
      if (gen == _loadGen) _loaded();
    });
  }

  void _runJs(String js) {
    // OEM 对 JS 框单发也可能丢/装装载期必丢:错误静默,自愈靠幂等重发。
    unawaited(
      _controller.runJavaScript(js).then((_) {}, onError: (Object _) {}),
    );
  }

  @override
  void dispose() {
    _jsArmFallback?.cancel();
    _ticker.dispose();
    widget.timeline?.anchor.removeListener(_onAnchor);
    super.dispose();
  }

  void _onFrame(Duration _) {
    final tl = widget.timeline;
    final anchor = tl?.anchor.value;
    final clock = tl?.clock;
    if (tl == null || anchor == null || clock == null) {
      // 停止/回闲:自停 + 当弹列还原(读谱态干净)+ 位置缓存清零。
      if (_ticker.isActive) {
        _ticker.stop();
        if (_color.last != null && _color.last != -1) _runJs('UF.paint(-1)');
        _color.reset();
        _lastScrollX = -1;
      }
      return;
    }
    final now = clock();
    if (now == null) return; // 暂停:引擎时钟冻结,同拍位去重后零下发。
    final width = _viewWidth;
    if (width == null || widget.data.bars.isEmpty) return;
    final beat = (now - anchor.t0).inMicroseconds / (anchor.periodMs * 1000);
    // 曲头余量已烘进页面(内容 x=0 即播放头线):目标 = 弹奏位内容 x;
    // 预备期负拍钳 0——曲头 0 落在线上等待,首音起再流向线(票08 曲头)。
    final x = faithfulStripBeatX(widget.data, beat).floor().clamp(0, 1 << 30);
    if (x != _lastScrollX) {
      _lastScrollX = x;
      _controller.scrollTo(x, 0);
    }
    // 染色:列变化率(~0.375s)单发,绝对状态幂等,丢发下一列自愈。
    final k = _color.update(beat, widget.data.bars.length * 8);
    if (k != null) _runJs('UF.paint($k)');
  }

  @override
  Widget build(BuildContext context) {
    // 播放头红线 = Flutter 覆盖层(票07 机型实录:OEM WebView 对
    // position:fixed 覆盖 div 的合成层滚动前不重绘、滚动后错位)。
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewWidth = constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureLoaded(constraints.maxWidth);
        });
        return Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (!_pageReady)
            // 装载期遮罩(票07 机型实录:OEM WebView 装 3MB 横带页
            // 要 10s+,期间白板像「没渲染」;明示装载中不误导新手)。
            const ColoredBox(
              color: Colors.white,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
            Positioned(
              left: constraints.maxWidth * viewportAnchor,
              top: 0,
              bottom: 0,
              width: 2,
              // 原站线色(票08 视频帧取样;站方线色=当弹字形同色)。
              child: const ColoredBox(color: faithfulHighlightRed),
            ),
          ],
        );
      },
    );
  }
}
