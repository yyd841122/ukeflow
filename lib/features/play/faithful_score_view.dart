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
/// ticker 按 [clock](引擎时钟缝,页装填控制器的 visualNow 原样)按列
/// 变化率下发 seek、页内 rAF 逐帧平滑。ADR-0005 不破:唯一时间源仍是
/// 引擎时钟,页把缝原样递给视图,页内无第二时间源。暂停 = 引擎时钟
/// 冻结(视图检出后冻结页内死推);未运行 = 缝返回 null,ticker 自停。
class FaithfulStripTimeline {
  /// 当前会话锚;null = 未运行。记录等值(字段同值)不重复通知。
  final ValueNotifier<StripAnchor?> anchor = ValueNotifier<StripAnchor?>(null);

  /// 引擎时钟缝:运行中 = 引擎当前时刻,暂停 = 冻结时刻,未运行 null。
  Duration? Function()? clock;
}

/// seek 下发节拍(票08 机检反三):首发锚、跨 0(预备→正曲/回开头)、
/// 每 4 拍周期校正。列变化**不再**下发——机检实测 OEM JS 桥按批冲刷,
/// 逐列指令的到达延迟 57-484ms 且成抖动,正是「声音与时间线不同步」
/// 的根因;染色改由页内时间轴逐帧现算(seek 只承担锚与校正)。
bool stripNeedsSeek(double beat, double? lastSentBeat) {
  if (lastSentBeat == null) return true;
  if ((beat >= 0) != (lastSentBeat >= 0)) return true;
  return beat >= 0 && lastSentBeat >= 0 && beat - lastSentBeat >= 4;
}

/// 染色列边界(八分网格):k 列覆盖拍 [0.5k, 0.5k+0.5],x 与滚动锚
/// 同一插值——染色永远钉在移动的播放头上。0 号列起点 = 曲头;
/// 每小节 8 列(4 拍 × 2),与横带页内联脚本的列数同源。
List<double> faithfulStripColumnBounds(FaithfulStripData data) {
  final bars = data.bars;
  if (bars.isEmpty) return const [];
  return [
    for (var k = 0; k <= bars.length * 8; k++)
      faithfulStripBeatX(data, k * 0.5),
  ];
}

/// 拍位 → 染色列号(八分网格,页内联脚本同式):预备期负拍 -1,
/// 越界钳两端。仅测试/文档用——染色由页内时间轴逐帧现算。
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
/// 视口宽×2/3,随装载一次性烘进 padding——曲头位置 0 恰落在播放头线
/// 上,流过末小节恰好触线而止。几何数字一律 Dart 算好注入,**禁用页面
/// innerWidth**(OEM 报值不可信,曾把内容整体推出屏外成白板)。
///
/// 跟滚引擎(票08 机型实录改版):OEM WebView 对连续 `View.scrollTo`
/// 做动画化/限速应用——逐帧绝对目标下显示以 ~35% 速率爬行(机检实测:
/// 指令 beat 105 vs 显示 beat 40,滞后随时间增长),且该路径拖慢
/// Flutter UI 线程(ticker 掉到 27Hz)。故跟滚**不走滚动**:内容 div
/// 由页内 rAF 逐帧写 `translateX`(合成器动画,亚像素平滑),拍位锚由
/// Dart 按列变化率(~0.375s)经 JS 桥单发 `UF.seek(beat,periodMs)`
/// 供给,页内按引擎拍周期死推,桥丢发由下一列 seek 重锚自愈。空闲态
/// rAF 停、overflow 还原,手动拖读谱不受影响。
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
      '<div id="ufs" style="position:relative;will-change:transform;'
      'padding-left:${lead}px;padding-right:${tail}px">${data.stripSvg}</div>'
      '<script>var M={cols:[$cols]};$_stripIndexJs</script>'
      '</body></html>';
}

/// 染色索引 + rAF 跟滚脚本(票08,随横带页内联一次;不经 JS 桥,OEM
/// jam 面零——桥上只走列变化率的 seek/hold/follow 单发)。
///
/// 视频帧实证(用户录屏,票08):站方播放染色只有两态——**当弹**列的
/// 品数字形变红(与播放头线同色),其余一切(已弹/未弹/谱线/符干/
/// 和弦名/小节号)保持原样不变。可染元素 = 纯数字 text 且字号 ≥ 全页
/// 最大数字字号×0.9(品数字 10.92px 入选,小节号 9.24px 淘汰;两首
/// 实测比值 0.85/0.69,均在界外)。索引建在字体就绪后(Bravura 晚到
/// 会改字形度量),2.5s 兜底;横带是嵌套 svg 裁切——每片含整系统 body
/// 副本,按「元素中心落在该片盒内」判定可见副本,strip x = 片 x +
/// (中心 − 片左缘)。color(n) 全量重刷 = 幂等,pending 暂存建索引前
/// 到达的指令。
final String _stripIndexJs = '''
var UF={mode:0,raf:0,a:0,at:0,per:750,p:null,b:null,bx:0,blendT:0,blendX:0,lc:null};
var cont=document.getElementById('ufs');
UF.color=function(n){UF.p=n;if(UF.b)UF.x();};
UF.x=function(){var n=UF.p;if(n==null||!UF.b)return;UF.p=null;
 var bs=UF.b;
 for(var i=0;i<bs.length;i++){var arr=bs[i];if(!arr.length)continue;
  var f=(i==n)?'$_highlightRedCss':null;
  for(var j=0;j<arr.length;j++){arr[j][0].setAttribute('fill',f!=null?f:arr[j][1]);}
 }};
UF.hold=function(){
 if(UF.raf){cancelAnimationFrame(UF.raf);UF.raf=0;}
};
UF.follow=function(off){
 if(off)return;
 UF.hold();UF.mode=0;
 cont.style.transform='none';
 document.body.style.overflow='';
 window.scrollTo(0,0);
 UF.color(-1);
};
UF.seek=function(b,per,te){
 if(per>0)UF.per=per;
 // 锚 = 「到达时刻的真拍位」:te(发送 epoch)与 Date.now() 同一 OS 墙钟,
 // b+(now−te)/per 即到达时的精确拍位——桥延迟多大都被时间戳自带消掉
 // (票08 机检反四:此前按观测最小延迟补偿,而到达延迟 60-484ms 抖动,
 // 误差在 0~半拍间摆 = 「不同步」根因;改时间戳锚后实测误差 ≤15ms)。
 var bA=b;
 if(te!=null){var l=Date.now()-te;
  if(l>=0&&l<60000)bA=b+l/UF.per;}
 if(b<0){ // 预备期/回开头:钳 0 并当场冻结——死推不得前爬(前爬数拍
  // 再被音乐首拍拽回,即「开始卡顿」根因,票08 机检反三)
  UF.hold();
  UF.a=0;UF.at=performance.now();
  if(!UF.mode){UF.mode=1;document.body.style.overflow='hidden';}
  UF.bx=0;cont.style.transform='translateX(0.00px)';
  UF.color(-1);UF.lc=-1;
  return;
 }
 var want=UF.traj(bA);
 UF.hold();
 UF.a=bA;UF.at=performance.now();
 if(!UF.mode){UF.mode=1;document.body.style.overflow='hidden';}
 // 软校正:|偏差|≤25px(半拍)从当前渲染位 150ms 滑入(吸收残余钟差);
 // 大偏差(回开头/跳列)硬切。
 if(Math.abs(want-UF.bx)>25){UF.bx=want;UF.blendT=0;}
 else{UF.blendT=performance.now();UF.blendX=UF.bx;}
 UF.lc=null;
 if(!UF.raf)UF.raf=requestAnimationFrame(UF.step);
};
UF.traj=function(b){
 var f=b*2,k=Math.floor(f);
 if(k>M.cols.length-2)k=M.cols.length-2;
 return M.cols[k]+(M.cols[k+1]-M.cols[k])*(f-k);
};
UF.step=function(){
 UF.raf=0;
 if(!UF.mode)return;
 var now=performance.now();
 var cb=UF.a+(now-UF.at)/UF.per;
 var lim=(M.cols.length-1)/2;
 if(cb>lim)cb=lim;
 var col=Math.floor(cb*2);
 if(col!==UF.lc){UF.lc=col;UF.color(col);}
 var x=UF.traj(cb);
 if(UF.blendT){
  var t=(now-UF.blendT)/150;
  if(t>=1){UF.blendT=0;}
  else{x=UF.blendX+(x-UF.blendX)*t;}
 }
 UF.bx=x;
 cont.style.transform='translateX('+(-x).toFixed(2)+'px)';
 UF.raf=requestAnimationFrame(UF.step);
};
UF.build=function(){
 if(UF.b)return;
 var svg=document.querySelector('#ufs svg');if(!svg)return;
 // 位置一律取属性(片 x/viewBox + 数字 text x)——OEM WebView 的
 // getBoundingClientRect 曾把盒测歪(机检实录 filled=72/应 290),
 // 属性坐标与缩放/时机无关。品数字两首全带 x 属性(census 实证)。
 var i,j,slices=[],ss=svg.querySelectorAll('svg');
 for(i=0;i<ss.length;i++){var s=ss[i];
  var vb=s.getAttribute('viewBox');if(!vb)continue;
  var vp=vb.split(' ');var lo=parseFloat(vp[0]),w=parseFloat(vp[2]);
  slices.push([parseFloat(s.getAttribute('x'))||0,lo,lo+w,s]);
 }
 var cand=[],mx=0;
 for(i=0;i<slices.length;i++){var sl=slices[i];
  var ts=sl[3].querySelectorAll('text');
  for(j=0;j<ts.length;j++){var t=ts[j];
   var c=(t.textContent||'').trim();
   if(!/^[0-9]+\$/.test(c))continue;
   var fs=parseFloat(getComputedStyle(t).fontSize)||0;
   if(fs>mx)mx=fs;
   var ax=parseFloat(t.getAttribute('x'));
   if(isNaN(ax)||ax<sl[1]||ax>sl[2])continue;
   cand.push([sl[0]+(ax-sl[1]),fs,t]);
  }}
 if(mx<=0||!cand.length)return;
 var lim=mx*0.9,cols=M.cols,bs=[];
 for(i=0;i<cols.length-1;i++)bs.push([]);
 for(i=0;i<cand.length;i++){
  if(cand[i][1]<lim)continue;
  var sx=cand[i][0],k=0;
  while(k<cols.length-2&&cols[k+1]<=sx)k++;
  bs[k].push([cand[i][2],cand[i][2].getAttribute('fill')||'#000']);
 }
 UF.b=bs;UF.x();
};
if(document.fonts&&document.fonts.ready&&document.fonts.ready.then){
 document.fonts.ready.then(function(){UF.build();});
}else{UF.build();}
setTimeout(function(){if(!UF.b)UF.build();},2500);
''';

/// 原样流水视图:横带单行滚动。空闲 = 静态读谱(手动拖);运行 =
/// **页内 rAF 逐帧 transform 跟滚**(票08 机型实录:OEM WebView 的
/// 原生 scrollTo 连续目标下被限速 ~35%,显示永远滞后且拖慢 Flutter
/// 线程;transform 走合成器,亚像素平滑,桥上只走列变化率的 seek)。
/// 曲头左余量烘进页面 padding(内容 x=0 即播放头线),预备数拍期拍位
/// 负钳 0 在线上等待。锚点用 Dart 视口宽的 1/3,不信页面 innerWidth
/// (OEM 曾错报)。播放染色同驱动:列变化率单发 seek(内含染色),
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

  /// seek 下发节拍调度(首发锚/跨 0/每 4 拍校正,见 [stripNeedsSeek])
  /// + 装载完成补发标记(装载期被 OEM 丢掉的 seek 靠它自愈)。
  var _colorsPrimed = false;
  double? _lastSentBeat;
  double? _lastSentPeriod;

  /// 暂停检测:引擎时钟连续 8 帧停走 → 页面 rAF 死推冻结一次
  /// (恢复由锚变更触发 seek,见控制器 resume 的重锚)。
  Duration? _lastClock;
  int _frozenFrames = 0;
  var _held = false;

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

  /// 会话锚到位(开始/循环接遍/恢复重锚):起 ticker;锚变更即置
  /// 最后一发为空(下一帧按新锚立即重发 seek——回到开头/恢复归位,
  /// 不等周期校正)。
  void _onAnchor() {
    final active = widget.timeline?.anchor.value != null;
    if (active && !_ticker.isActive) _ticker.start();
    if (active) {
      _lastSentBeat = null;
      _held = false;
      _frozenFrames = 0;
    }
  }

  /// 装载就绪(幂等;onPageFinished/装载 future/兜底定时器三方竞争):
  /// 遮罩退场 + 补发当前 seek(装载期被 OEM 丢掉的指令自愈)。
  void _loaded() {
    if (!mounted) return;
    _jsArmFallback?.cancel();
    _jsArmFallback = null;
    if (!_pageReady) {
      setState(() => _pageReady = true); // 遮罩退场(触发重绘)
    }
    if (!_colorsPrimed) {
      _colorsPrimed = true;
      final beat = _lastSentBeat;
      final period = _lastSentPeriod;
      if (beat != null && period != null) _sendSeek(beat, period);
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

  void _sendSeek(double beat, double periodMs) {
    _lastSentBeat = beat;
    _lastSentPeriod = periodMs;
    // te = 发送时刻 epoch ms(页内 Date.now() 同一 OS 墙钟):页用它反推
    // 到达时刻真拍位,桥延迟被时间戳自带消掉(票08 反四)。
    final te = DateTime.now().millisecondsSinceEpoch;
    _runJs(
      'UF.seek(${beat.toStringAsFixed(4)},${periodMs.toStringAsFixed(0)},$te)',
    );
  }

  void _onFrame(Duration _) {
    final tl = widget.timeline;
    final anchor = tl?.anchor.value;
    final clock = tl?.clock;
    if (tl == null || anchor == null || clock == null) {
      // 停止/回闲:自停 + 页面跟滚复位(transform 还原/溢出还原/染色
      // 还原——单发 follow(0),丢发的代价只是空闲态停在上次位置)。
      if (_ticker.isActive) {
        _ticker.stop();
        if (_lastSentBeat != null) _runJs('UF.follow(0)');
        _lastSentBeat = null;
        _lastSentPeriod = null;
        _held = false;
        _frozenFrames = 0;
        _lastClock = null;
      }
      return;
    }
    final now = clock();
    if (now == null) return;
    final width = _viewWidth;
    if (width == null || widget.data.bars.isEmpty) return;
    final beat = (now - anchor.t0).inMicroseconds / (anchor.periodMs * 1000);
    // 跟滚锚:首发/跨 0(预备→正曲)/每 4 拍周期校正才下发(低调频避
    // OEM 桥批冲刷延迟);染色由页内时间轴逐帧现算,桥零逐列依赖。
    if (stripNeedsSeek(beat, _lastSentBeat)) {
      _sendSeek(beat, anchor.periodMs);
    }
    // 暂停检测:引擎时钟连续停走 → 冻结页内死推一次(恢复由锚变更
    // 触发 seek 重锚,见 _onAnchor)。8 帧阈值防时钟粒度误判。
    if (now == _lastClock && !_held) {
      if (++_frozenFrames >= 8) {
        _held = true;
        _runJs('UF.hold()');
      }
    } else if (now != _lastClock) {
      _frozenFrames = 0;
    }
    _lastClock = now;
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
