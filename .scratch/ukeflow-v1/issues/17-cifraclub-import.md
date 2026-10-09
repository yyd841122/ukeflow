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
