# 47: 识谱工作台骨架 + 谱面体检 + 谱型判别（CLI）

**Status:** ready-for-agent

**What to build:** `tools/score_workbench/`（Python 3；PyMuPDF/Pillow/opencv-python；venv+requirements）。CLI：①体检——PDF 矢量/位图检测（文本层有无+图像覆盖率），矢量谱遇到只报告不处理；②判别——启发式（检出四线谱系统→solo；和弦名+简谱行无 TAB→strum；否则 image），误判可手改（ADR-0009）；③输出分流报告 JSON。**第一步子任务：** dolce（悦谱，MIT，lodebar2026/dolce）跑谱全了样张，评估其简谱输出对工单 49 的可用性，结论落 docs/research/。

**Non-goals:** 任何符号识别（48-50）、UI、服务器。
