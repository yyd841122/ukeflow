# 05: 原谱视图(WebView 渲染矢量谱页原样 HTML)

**Status:** done

**Blocked by:** 无(可与票02/03 并行)

**What to build:** 导入谱详情加「原谱」视图:WebView 加载自包含 HTML
(doctype + alphaTab 官方 CSS + 内嵌 Bravura woff base64 + 原 div 原文),
像素级复刻谱站原渲染。配方与调研:docs/research/2026-11-06-vector-page-faithful-render.md。

**范围:**

1. **存原 HTML**:ImportedSoloCharts 表加列 `sourceHtml`(TEXT,可空;旧行
   null = 无原谱视图入口),schemaVersion bump + 迁移;导入流选到 .html
   时(或工作台产物带 HTML 时)落原文。矢量谱页导入链(票04)产 JSON 时
   同产原谱 HTML——解析器本就吃 HTML,顺手保存原文零成本;
2. **原谱视图页**:webview_flutter 加载(loadHtmlString 或 flutter_asset);
   WebView 手势缩放/滚动原生;深色背景适配(HTML 自带白底,容器加边距即可);
3. **详情页入口**:谱面视图(自绘,跟练用)与 原谱视图(阅读)并存切换;
   无原谱 HTML 的旧条目不显示入口;
4. **字体共享**:Bravura woff(414KB)提取为共享资产,HTML 用相对路径引用
   (loadDataWithBaseURL / WebViewAssetLoader),免每谱内嵌 0.6MB——首版可
   先内嵌(自用谱量小),共享化留后续。

**验收:**

1. 两首样本(天空之城/萱草花)原谱视图真机渲染,与站方原样目验一致
   (谱号/拍号/音符/卷弦波纹/简谱行/歌词全到位);
2. 缩放流畅,长谱(萱草花 6 系统/天空之城 12 系统)滚动无卡顿;
3. 旧条目(无 sourceHtml)不炸不显示入口;check.sh 全闸绿。

**Non-goals:** 原谱上做交互(点音编辑/回放定位)——阅读专用;替代自绘
谱面视图(自绘承载跟练高亮,两者并存);萱草花弹唱谱入库(票03)。

## Comments

### 2026-11-06 收口:真机原样渲染通过

- **实现**:schema v7(ImportedSoloCharts + sourceHtml 列,addColumn 迁移);
  导入流拆键(矢量谱页产物可选键 sourceHtml 内嵌,落库时拆列:sourceJson
  保持纯 IR,原谱进独立列);ready/page/dao 全链透传;详情页 AppBar「原谱
  视图」入口(menu_book,仅 sourceHtml 非空条目显示);FaithfulScoreViewPage
  (webview_flutter,JS 关、导航全拦,纯静态渲染);CLI 内嵌
  (--no-faithful 可关;字体 vendored fonts/Bravura.woff + OFL.txt)。
- **配方来源**:alphaTab 官方 Node.js 指南 §4 CSS 模板 + Bravura(SIL OFL);
  详见 docs/research/2026-11-06-vector-page-faithful-render.md。
- **真机验证**(OPPO PCAM00,release 包):天空之城原样渲染完整呈现——
  TAB 谱号/4-4 拍号/休止符/符尾/附点/连音弧/琶音波纹/和弦图/Part 分段/
  高把位数字全部到位(截图存 /tmp/devshots/faithful-view.png)。缩放滚动
  走 WebView 原生。萱草花待票03 入库时同链补验(机制同函数)。
- **过程中修的两个坑**:
  1. 指纹语义:contentSha 原按剥离后 IR 算 → 带原谱的重导入命中旧行
     (去重),原谱静默丢失。修 = 指纹改「导入文件全文」
     (fingerprintOf = sourceJson + \0 + sourceHtml);判定单位是文件,
     不是语义 IR。测试锁定(带原谱≠纯 IR;同文件重导=去重)。
  2. 运行时简谱推导遇变化音(F#)抛错 → 灰板(昨日已修,声部模型改
     完整伴奏 + 自然音旋律参考行);ScoreSheetLayout 布局推导进
     validate_score_ir.dart 前置防线。
- **测试**:vector_chart pytest 16/16;flutter 988(含 flow 拆离/去重
  语义、页面 sourceHtml 落列、原谱入口显隐、v6→v7 迁移);check.sh
  全闸绿。诊断日志(T05-DIAG)已清,收口版 APK 已装机。
- 设备遗留:调试期产生的同名旧条目(id 6/7,无原谱)未清,用户可在
  曲库隐藏或设置页恢复管理;不影响新条目。

### 2026-11-06 追记:UX 改为「默认原样视图」+ 设备遗留说明

- 用户验收反馈:打开卡片仍是自绘谱面,原样视图藏在图标里不显眼。改:
  ScoreSheetPage 有原谱 HTML 时**默认先示原样视图**(阅读优先),AppBar
  图标互切原样/跟练;运行中(示范/跟练)强制回自绘(时间轴宿主);
  `faithfulFirst` 参数为测试缝(锁自绘流程用)。
- 过程中误操作:调试期反复导入 + 一次坐标点按失误,把独奏谱类目全部
  软隐藏(可恢复,无数据丢失)。已向用户说明恢复路径(设置 → 隐藏的谱
  → 恢复);最新条目(id 9,带 sourceHtml 994227)恢复后即为唯一所需
  卡片,旧的无原谱条目可继续隐藏。
- 设备点按(adb input)被本机安全策略拦下,最后一步恢复交用户手点。
