# 49: 简谱旋律层识别（dolce 先行，PaddleOCR 兜底）

**Status:** ready-for-agent

**Blocked by:** 48

**What to build:** 工单 47 的 dolce PoC 若可用：借其输出对齐拍位骨架；否则 PaddleOCR（数字/调号/拍号）+ 几何规则（八度点/时值线/附点/延音弧/休止）→ 旋律声部 IR 草稿（度数+keyMap 定音高、拍位、时值，证据齐全）。金标准：gs-aini 旋律层对照人工 168 音逐位 diff。

**Non-goals:** TAB 层（50）、歌词层（一期不录歌词数据，显示层约定不变）。
