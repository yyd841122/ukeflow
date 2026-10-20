# 34: 文本双源接入（Guitarians + UkuTabs）

**What to build:** Cifra Club 退役删除（git 留底），换两个文本谱源，直解析直跟练不经 AI：Guitarians（中文文本主源）+ UkuTabs（英文文本）。搜索页沿用票 27 骨架（原生中文结果列表 + 隐形 WebView 取数 + 「浏览原站」兜底），顶部三 tab：Guitarians / UkuTabs / 曲谱图网（第三个本票灰置，工单 35 点亮）。

**Blocked by:** 无

**Status:** ready-for-agent

- [ ] 中文歌：Guitarians 搜索→列表→导入→过校验入库→跟练（抽样含粤语繁体谱与小节线变体谱）
- [ ] 英文歌：UkuTabs 同流程；**Cloudflare 真机验证是本票闸门，验不过砍此源不硬上**（结论记评论）
- [ ] 升号和弦（F#/C#m 类）导入后白名单放行、指法正确映射；斜线和弦（D/F# 类）支持性验证有结论
- [ ] cifraclub_* 全套（页面/搜索/导入/提取 JS/URL 判定/驱动 + 4 测试）删净，曲库无残留入口；升降号归一逻辑先摘出迁走再删
- [ ] UkuTabs 载页频次克制；challenge 未过给可读降级提示指路文本导入，不崩溃

## Comments

- 2026-10-19 (拷问会话): 调研实证（直抓 + Wayback 存档，/tmp 落盘为临时件，承重结论存此）——**Guitarians**：内容页服务端渲染文本谱、免登录看谱；Cloudflare 在但内容页不拦普通抓取。详情 `/{语区}.guitarians.com/chord/{id}/{歌手-歌名}`，干净口 `zh-hk.guitarians.com/chord/embed/{id}/{slug}`（www 302 到语区子域）。DOM = `<div class="viewSection">` 内 viewChordNoBar / viewLyric 成对 div，&nbsp; 对齐，与文本导入「悬挂和弦行+歌词行」语法同构，转 ChordPro 近直译；带小节线变体（`| C G/B | Am Em |`）按小节切分。服务端移调 GET `?targetKey=D&targetCapo=0` 已探明——**v1 抓原调**，此参数是后置移调小票的现成素材。真机验证项：站内搜索 URL 形态、大陆热歌覆盖抽样、zh-hans 子域是否转歌词简繁。**决策：歌词按源站原样入库不转简体**（转换词库重、错转风险；繁体不影响跟练）。**UkuTabs**：100% 文本 chord-over-lyric；容器 `<pre id="ukutabs-song">`，和弦 = `<a class="ukutabschord">C</a>` 锚点包字，对齐靠等宽空格；段落 = `<strong>Verse</strong>:` 形式；提取只锚定 #ukutabs-song（站有 Weglot 多语言层注入 DOM，勿依赖全页结构）；搜索 WordPress `/?s=`。Cloudflare 在前（curl 无 JS 直连 403 + challenge），WebView 静默通过属推断、待真机；广告重（Freestar 多槽，页面 600KB+）；中文歌仅拼音歌词（照常入库，用户自辨用途）。**记谱归一**：升降号归一复用 cifra_extract.dart 遗产（和弦库根音只认降号拼法，Guitarians/UkuTabs 全是升号拼法，不归一几乎首首被 unknownChord 拦——工单 17 同坑；归一只在白名单不收原写法时发生，quality 与斜线低音两端各归一）；巴西记谱映射（F7M→maj7 等）不要；**删码前先把归一逻辑摘出**。**旧结论修订**：「中文站只有图片谱」对大陆主流站仍成立（吉他社/17吉他/弹琴吧/彼岸吉他/尤克里里中国网/白熊逐站确认无文本谱）；谱友圈 puyouquan.com 技术面最优（开放结构化全谱 API、零反爬、规划了 uku 类型）但全库 9 首、尤克里里 0 首——观察名单，定期查 `/api/pub/scores` 的 total，起来即接。
