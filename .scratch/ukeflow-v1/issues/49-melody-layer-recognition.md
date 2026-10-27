# 49: 简谱旋律层识别（dolce 先行，PaddleOCR 兜底）

**Status:** ready-for-agent

**Blocked by:** 48

**What to build:** 工单 47 的 dolce PoC 若可用：借其输出对齐拍位骨架；否则 PaddleOCR（数字/调号/拍号）+ 几何规则（八度点/时值线/附点/延音弧/休止）→ 旋律声部 IR 草稿（度数+keyMap 定音高、拍位、时值，证据齐全）。金标准：gs-aini 旋律层对照人工 168 音逐位 diff。

**Non-goals:** TAB 层（50）、歌词层（一期不录歌词数据，显示层约定不变）。

## Comments

- 2026-10-27 (工单47 PoC 后的前提校准,retro 补记): 本票面「dolce 先行,PaddleOCR 兜底」写于工单47 PoC 之前。47 已实证 dolce **不能当识别引擎**(无证据链/无拍位/X 静默丢/裁条不稳,见 docs/research/2026-10-27-dolce-jianpu-poc.md),只可当**互证对照源**(其人声段度数/时值/八度与人工台账逐项全对)。认领本票时按此校准:主识别路径须自带证据链与拍位(消费工单48 切分的 jianpu 层裁图+候选拍网格),dolce 输出降为对照源之一;PaddleOCR 兜底思路不受影响。
