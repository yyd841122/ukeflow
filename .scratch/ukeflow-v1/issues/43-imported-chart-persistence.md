# 43: 导入谱持久化 + 曲库合并（Broken 兜底）

**Status:** ready-for-agent

**Blocked by:** 42

**What to build:** drift 新表 `ImportedSoloCharts`（id/title/schemaVersion/sourceJson/contentSha/createdAt/updatedAt/reviewedAt），schemaVersion 5→6 迁移。读路径仿 CustomCharts（源 JSON 唯一真源）：watch 流 → 解析+校验+物化 → Ready（产出 ScoreSheetDef+双 TabChart）/ Broken（解析或校验失败，保留源可重试）。曲库独奏谱类目合并 builtin+imported（扩展 `_soloEntries` 派生模式）；隐藏状态沿 Settings 集合模式。

**Non-goals:** 导入 UI（44）、编辑（45）。
