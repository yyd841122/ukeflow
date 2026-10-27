# 47: 识谱工作台骨架 + 谱面体检 + 谱型判别（CLI）

**Status:** resolved

**What to build:** `tools/score_workbench/`（Python 3；PyMuPDF/Pillow/opencv-python；venv+requirements）。CLI：①体检——PDF 矢量/位图检测（文本层有无+图像覆盖率），矢量谱遇到只报告不处理；②判别——启发式（检出四线谱系统→solo；和弦名+简谱行无 TAB→strum；否则 image），误判可手改（ADR-0009）；③输出分流报告 JSON。**第一步子任务：** dolce（悦谱，MIT，lodebar2026/dolce）跑谱全了样张，评估其简谱输出对工单 49 的可用性，结论落 docs/research/。

**Non-goals:** 任何符号识别（48-50）、UI、服务器。

## Comments

- 2026-10-27 (收口): 工作台落地 tools/score_workbench/(pymupdf/pillow/opencv/numpy,pytest 33 绿;Python 3.12,/tmp/swwenv)。①体检=PDF 对象层探测(文本层/位图覆盖率/矢量指令);②判别=纯函数缝(spec 实现决策7,fixture 驱动 12 测):矢量→只报告、四线谱系统→solo、文本带+简谱证据无 TAB→strum、其余→image,`--type` 人工改判(ADR-0009,auto_type 保留);③分流报告 JSON `ukeflow.workbench.triage/1`(sha256/体检/版面/判定+理由)。版面信号几何 census 直移(scale3 弦距14px);**谱线检测实测教训:行墨量 ≥75%W@灰235(census 同判据)可行,连续 run 判据被字形白晕打断漏检**。
- 真机语料实数:gs-aini 检出 17 组四线谱系统(与工单41 人工普查完全一致)→ solo;gs-bbw 15 组 → solo;两谱 text/digit/underline 带与简谱层分布全数检出,误报五线谱/杂线组 0。合成 fixture 端到端:矢量谱报告不处理、人工改判、空白 PDF 认不出,全过。flutter 全量 951 绿 + analyzer 净(本票零 Dart 改动)。
- [x] 第一步子任务 dolce PoC:结论=**对工单49 不能当识别引擎(无证据链/无拍位/无坐标,X 静默丢,裁条不稳),可当高价值互证对照源**(人声段度数/时值/八度点/连线与人工台账逐项全对;调号 1=E、78bpm 与台账一致);失败三模式(裁条首行塌休止、TAB 行成垃圾行、八度点随输入抖动)与装机注意(onnxruntime-node 装 `ONNXRUNTIME_NODE_INSTALL=skip`)已落 docs/research/2026-10-27-dolce-jianpu-poc.md。
- Non-goals 未越界:无符号识别(48-50)、无 UI、无服务器;工作台带检测顺带产出了 48 要用的简谱带定位雏形(工单48 起正化)。
