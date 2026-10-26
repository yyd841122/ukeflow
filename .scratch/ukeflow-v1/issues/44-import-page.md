# 44: 导入页（选 JSON → 校验 → 预览 → 确认入库）

**Status:** ready-for-agent

**Blocked by:** 43

**What to build:** 曲库入口新增「导入识谱源」：file_selector `openFile`（先例 backup_flow.dart）选 .json → validator 全检（阻塞错误逐条人话列出）→ 预览页复用谱面视图渲染（试物化）→ 命名+确认入 `ImportedSoloCharts`。重复 contentSha 提示已存在。

**Non-goals:** PDF 直选（识别在电脑端，App 只吃校对后的 JSON）；编辑（45）。
