# 51: 校对台（本机 web：左裁图/右数据/点击互跳）

**Status:** ready-for-agent

**Blocked by:** 49, 50

**What to build:** 本机 Flask（localhost 单页，不联网、非服务器部署）：左侧系统条带裁图（bbox 高亮当前校对位），右侧该小节 IR 数据表（音/时值/休止/技巧/置信度）；点击互跳；逐小节「确认」；全曲确认 → 导出 UkeFlow IR JSON（工单 42 schema）。**金标准对照模式：** 载入 builtin 参考 JSON → 逐位 diff 报表（数字/拍位/休止 P-R/技巧 F1），作为识别质量验收面板。

**Non-goals:** 音乐性重构编辑、批量技巧录入之外的重活、任何网络服务。
