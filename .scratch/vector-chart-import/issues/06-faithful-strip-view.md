# 06: 原样流水跟练视图(单行横带 + 播放头跟拍)

**Status:** done

**Blocked by:** 05(done)

**What to build:** 用户验收票05 时提出:原样渲染整页多行,练习时需要**单行流水**
展示方便跟练。实现:工作台按小节线把整页切成竖条(逐小节),按曲序横向拼接成
单行横带(nested svg viewBox 裁切,内容原样零改动,Bravura/CSS 全保留);App 内
原样条目默认以流水横带示谱(阅读=手动拖,跟练=播放头固定视口 1/3、内容随拍
自动滚动);AppBar 图标切回自绘跟练(点选轻改/逐拍高亮全功能);示范运行中
强制横带+播放头(切页暂禁)。

**实现:**

- 工作台:`faithful_strip.py`(小节切片拼接 + 植入原样页固定标记节点
  `div#ukeflow-strip` / `script#ukeflow-strip-meta`);decode_tab 暴露
  system_bar_edges(系统→小节线 x 列表);CLI 缺省内嵌。
- App:`extractFaithfulStrip`(标记提取)+ `FaithfulStripView`(WebView 加载
  横带页:CSS 复用 + 播放头 div + updateBeat JS;拍位由页面 poll 经
  ValueNotifier 推送);ScoreSheetPage 三态:原样流水(默认)/自绘跟练/
  整页阅读(票05 的 FaithfulScoreBody 保留于整页模式)。
- 弱起:首小节印张 1 拍,横带按印张切;拍位 0-3 播放头停小节左缘,拍 3 起
  入内容(时序保真优先于播放头平滑)。

**验收:**

1. 天空之城真机:流水横带 51 小节单行呈现(和弦图/谱面/符杠/卷弦原样),
   打开卡片默认即此视图;
2. 开始示范:播放头固定 1/3 视口、横带随拍滚动、曲末停;AppBar 切自绘
   跟练:轻改/高亮全功能不回退;
3. python 横带黄金测试 + flutter 全闸绿。

**Non-goals:** 横带内点选轻改(点选仍在自绘视图);横带逐拍高亮(只有
播放头;高亮是自绘布局的数据);跨小节 tie 的横带内视觉(切缘裁断,
保真由整页模式承担)。

## Comments

### 2026-11-06 实现收口(待真机验收)

- 工作台横带 10104×148,51 小节切片(首片含谱号拍号),本地 cairosvg
  目验:和弦图/谱面/符杠/卷弦波纹/Part 标签完整。
- Dart:extractFaithfulStrip + FaithfulStripView(WebView JS 仅播放头;
  onPageFinished 竞速收口补发拍位)+ ScoreSheetPage 三态接线;
  FaithfulStripView 测试桩 = FakeWebViewPlatform(webview_flutter 平台
  接口 fake,loadHtmlString/runJavaScript 捕获)。
- check.sh 全闸绿(flutter 988+ / python 257);最终产物
  `~/ukeflow-sources/vector-pages/tiankongzhicheng-vector.scoreir.json`
  (3.8MB,含横带)已推手机并重启 App。待用户恢复条目后真机验收。
- 设备遗留:调试期产生的同名隐藏条目若干,用户可在设置页管理。

### 2026-11-06 真机自查通过(装机机检记录)

- 重导入新版产物(3.81MB,含横带)后真机逐项自查:
  1. 打开卡片**默认 = 单行原样流水横带**(TAB 谱号/4-4 拍号/休止符/
     弱起 0-2/Am 卷弦波纹原样),下方速度/轨道/开始示范控件齐全;
  2. 开始示范 → 运行态横带**随拍自动滚动**(实证:播放数分钟后横带自
     第 1 小节滚至 31 小节 Fmaj7 把位段),控制行(循环/暂停/回开头/
     停止/变速)正常;
  3. 停止回空闲,横带回起点;AppBar 书页图标切整页原样(阅读);
  4. logcat 近 500 行 E/flutter=0。
- 附带落地(用户要求):设置页隐藏区导入谱条目增「彻底删除」钮
  (确认对话框 → 整行移除 + 清隐藏集,不可恢复;内置谱保持仅恢复);
  真机删除隐藏导入谱 7 条验证通过。
- 已知小项:播放头红线 2px 偏细(深色谱面上弱),后续可加宽;横带切片
  在小节边界处和弦图有轻微裁切(±3px 余量内),整页模式无此现象。
- 待用户上手跟练听感确认 → 翻 done。

### 2026-11-06 用户复检两案修复(裁头回归 + 预览一致性)

- 「TAB 的标识除了第 1 段,其他不应该再次显示」:根因 = 票内 y 对齐
  重写 faithful_strip.py 时,_bar_ranges 丢了 skip_header 参数(签名只剩
  edges,docstring 却还声称非首系统头被裁)——经典回归。修复:非首系统
  首片 lo = max(edges[0], first_digit_x−5)(首个 TAB 数字左 5px),
  行首重画的谱号/拍号/小节号不进横带;程序化验证 = 51 片含谱号坐标
  (28.4)的仅第 1 片。python 补 2 守卫测试防再犯。
- 「预览导入的曲谱和实际显示的曲谱内容并不一致」:预览页走自绘
  ScoreStripView、卡片走原样 FaithfulStripView,两套渲染必然不同。修复:
  ImportScoreSourcePage 源带横带时同款 FaithfulStripView(静态拍位,
  所见即所得);纯 IR 源回退自绘。widget 测试 ×2(带横带→WebView 装载
  横带内容且无自绘并存;无横带→回退自绘,不进 WebView)。
- 真机复检:重导入后预览页即原样横带,开卡同款;横带内 6→7 系统接缝
  干净(无 TAB/4/4 重复、谱线连续、小节号一次);logcat E/flutter=0。
- 产物已重推并入库(3.8MB,~/ukeflow-sources/vector-pages/)。flutter
  全闸绿 + python 18/18。待用户上手跟练听感 → 翻 done。

### 2026-11-07 用户上手验收通过(横带裁头+预览一致性复检 OK)→ done。
