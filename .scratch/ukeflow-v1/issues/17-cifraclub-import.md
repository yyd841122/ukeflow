# 17: Cifra Club 搜索+链接导入

**What to build:** 搜索源页(v1 仅 Cifra Club 一个):WebView 站内搜索→结果列表→进曲谱页→从 DOM 提取内嵌和弦数据→转为文本谱→走 16 的校验入库管线。禁止服务端 HTTP 直连爬取(站点 Akamai 反爬,调研已确认),一切在 WebView 内发生。

**Blocked by:** 16 文本导入

**Status:** ready-for-agent

- [ ] 真机搜歌→导入→跟练全链路走通
- [ ] DOM 提取失败(结构变化/拦截)给可读失败态,不崩溃
- [ ] 导入谱必过同一校验层
- [ ] 无通用网页导入(仅 Cifra Club,对照 ADR-0002)

## Comments

- 2026-10-09 (工单01 会话): 本票(与 16 粘贴导入)是全项目第一个不可信外部输入面(WebView DOM + 网络文本)。两票都落地后跑一次全库跨模型审计(/cc-suite:audit full,持久化到 .cc-suite/audits/),发现转 triage 工单消化。安全维度收益最高的时点。
- 2026-10-14 (本票会话): **落地,待真机验收**。四片:①核心缝 `core/chart/cifra_extract.dart`(TDD 14 测试):`decodeCifraPayload`(WebView JS 行结构 JSON→纯模型,容错纪律——畸形/双引号包裹一律 null 绝不抛)+`cifraExtractError`(JS `{error}` 失败码)+`buildChordPro`(行结构→文本谱)。转换规则=票 16 机检 Python 原型语义迁 Dart:①悬空行首和弦吸歌词行首(缩进=排版习惯)②行中词中回退词首;**升#降b 同音异名归一**(和弦库根音零升号,Cifra Club 全站升号拼法——不归一几乎首首被 unknownChord 拦,归一只在白名单不收原写法时发生,quality 与斜线低音两端各归一);段落标记 [Chorus]/[Refrão](重音剥离词表)→ start_of/end_of 指令对,识不得的自造 custom 段留标签;连续悬空和弦行只取首条配歌词(双记谱行丢弃)。**真实 DOM 形态两代兼容**:2026-06 存档页是裸 `<pre>`+`<b>`+文本节点换行,调研 2026-10-08 形态是 `pre[data-chord-content]`+行级 div+`data-chord-name`——JS 提取脚本双形态都走;站点 capo 双记谱的第二行渲染成**纯文本无 b 标签**,紧跟悬空行且过半 token 像和弦记号的纯文本行按二记谱行丢弃(负例测试钉死普通歌词不被误杀)。验收级测试:存档 Gravity 行结构→buildChordPro→StrumChartParser+真实 ukulele.json 白名单全过(升号清零、capo 行不入词)。②URL 形态缝 `cifraclub_urls.dart`(4 测试):曲谱页=域名+两段路径+站务词黑名单(调研实抓首页导航)+versao/乐器后缀白名单。③WebView 页 `cifraclub_page.dart`:webview_flutter ^4.14.1(新依赖)+manifest INTERNET 权限(此前 manifest 零联网面,本次新增);站内搜索(SearchBar→busca?q=)、onUrlChange 判曲谱页形、导入钮→页内脚本提取→转换→`TextImportPage(initialSource:)` 预填;提取失败给可读横幅(没内容/没和弦/脚本错各给文案)指路文本导入,不崩溃。④`TextImportPage` 加 `initialSource`:进页自动校验,过→直落报告({title} 预填曲名),不过→落回粘贴态可读报错原文可改——与粘贴路径同一校验层别无旁门(验收③的结构保证)。曲库弹唱谱区头加「Cifra Club」入口。测试 408→430 全绿,analyzer 零告警,release APK 构建通过并已覆盖安装。**待真机**:搜歌→导入→跟练全链路+提取失败态真机呈现(设备锁屏,机检待用户解锁续跑)。**注**:工单01 预约的「16+17 落地后跑 /cc-suite:audit full」条件已到——本会话技能清单无 cc-suite,留待用户侧执行。
