# 矢量谱页原样渲染:Bravura 字体配方与 WebView 方案(票01 真机验收引出)

2026-11-06。票01 真机验收:ScoreIR 自绘谱面可弹,但用户反馈**细节不复刻**(自绘
是简化谱面,不是印刷复刻)。用户提出:能不能把我给的渲染 div HTML **按原样**渲染?
调研结论:**能,而且官方文档就有现成配方**,已本地实证并产出两首自包含 HTML。

## 发现

矢量谱页 = alphaTab(谱站所用开源渲染引擎)的渲染面序列化:`div.at-surface` +
逐系统 SVG,语义文本在 `<text>`,音乐符号在 `<g class="at">` 内的 PUA 字形
( 谱号、/ 拍号等)。PUA 字形**依赖 Bravura 音乐字体**:
alphaTab 渲染时往页面注入 `@font-face`(font-family 名就叫 `'alphaTab'`)+ 
`.at`/`.at-surface` 规则;缺字体则符号不显示。官方 Node.js 指南 §4「The CSS
dependency」给出完整模板(https://alphatab.net/docs/guides/nodejs)。

## 配方(已实证)

1. 字体:Bravura(Steinberg SMuFL 参考字体,**SIL OFL**,可自由嵌入再分发)。
   源:github.com/steinbergmedia/bravura `redist/`(woff 414KB / otf 889KB;
   woff2 已从 redist 移除);alphaTab 发行版亦内置 `dist/font/Bravura.ttf`。
2. 包装:doctype + viewport + 官方 CSS(@font-face 的 src 换
   `data:font/woff;base64,…` 内嵌)+ **原 div 原文**(不重排不重序列化)。
   产物单文件自包含(840-993KB),浏览器双击直开。
3. 本地验证:Bravura.ttf 入 fontconfig,cairosvg 按解析重建渲染 sys1——
   谱号/音符字形从占位变真字形。验证脚手架的 hanging-baseline 位移是
   脚手架 artifact,浏览器按原 CSS 无此问题。
4. 产物:`~/ukeflow-sources/vector-pages/{tiankongzhicheng,xuancaohua}-原样渲染.html`。

## 应用内方案提案(未实施,待立项)

- **原谱视图** = WebView(webview_flutter)加载自包含 HTML;缩放/滚动走
  WebView 原生;谱面像素级=站方原样。
- **分工不变**(ADR-0003/0009/0011):ScoreIR 继续承载跟练/播放/评分(时间轴
  与发声),原谱视图只管「阅读」——两条渲染路线互不替代。
- 代价:导入谱表需加列存原 HTML(schemaVersion bump + 迁移);WebView 依赖;
  每谱 +0.8-1MB(字体可提取共享,重复内嵌是偷懒方案)。
- 许可:Bravura OFL 无碍;alphaTab 代码本身不进包(只渲染其输出文件,纯自用);
  未来若直接集成 alphaTab 库须先核其许可(GitHub license 字段 NOASSERTION)。
