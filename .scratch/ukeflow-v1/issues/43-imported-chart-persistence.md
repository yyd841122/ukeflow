# 43: 导入谱持久化 + 曲库合并（Broken 兜底）

**Status:** done

**Blocked by:** 42

**What to build:** drift 新表 `ImportedSoloCharts`（id/title/schemaVersion/sourceJson/contentSha/createdAt/updatedAt/reviewedAt），schemaVersion 5→6 迁移。读路径仿 CustomCharts（源 JSON 唯一真源）：watch 流 → 解析+校验+物化 → Ready（产出 ScoreSheetDef+双 TabChart）/ Broken（解析或校验失败，保留源可重试）。曲库独奏谱类目合并 builtin+imported（扩展 `_soloEntries` 派生模式）；隐藏状态沿 Settings 集合模式。

**Non-goals:** 导入 UI（44）、编辑（45）。

## Comments

### 2026-10-26 实现(Agent)

五路曲库合流落地,全量 889 绿(21 测新增)+ analyzer 净。

**文件:** `ImportedSoloCharts` 表(id/title/schemaVersion/sourceJson/contentSha/createdAt/updatedAt/reviewedAt)+ schemaVersion 5→6(建表走既有 createAll 幂等策略);`imported_solo_charts_dao.dart`(add 现算 contentSha=源 JSON sha256、getAll/watchAll 按入库序);core 读出缝 `core/import/imported_solo_charts.dart`(解码→ScoreIr.fromJson→物化,三异常域统一,入库名 withTitle 覆盖 def+双谱题);`chart_providers.dart`(ImportedSoloEntry sealed=Ready 三源/Broken 留错,importedSoloChartsProvider 逐行降级,hiddenImportedSoloIds 设置键+ImportedSoloVisibility,LibraryContent 增 importedSolos);曲库独奏类目并列渲染(内置在前导入尾随,Broken 禁用卡)与设置页恢复区(导入独奏谱 · 行名,陈年 id 原样呈现)。

**实现裁量(票面未定处,评审确认):**
- 展示名以入库命名为准(自建谱命名纪律同款):新增 TabChart/ScoreSheetDef.withTitle(同名原样返回),读出时覆盖源内曲名。
- 删除语义 = 隐藏出曲库(票面「隐藏沿 Settings 集合模式」):源永久保留在库,恢复口在设置页;Broken 条目同口——隐藏不销毁,修源重导入/管线演进后恢复即重试。
- 类目合并走 LibraryContent 新字段 + 独奏段第二循环,未把导入条目塞进 `_soloEntries` 的内置记录类型——行为等价(内置前导入尾随),卡 key 独立命名空间(imported-solo-<行id>)不与内置目录 id 冲突。
- reviewedAt 存 text 照录源 review.reviewedAt(ISO 串不转格式,零漂移)。

**评审消化(两轴,2026-10-26):** 修 = 坏源卡不可点的负断言改 byType(ScoreSheetPage)(原文本前缀匹配放过真导航)、测试轮询收敛 pollUntil、architecture.md 数据层树补 imported_solo_charts;不修 = withTitle 三处复制(显式直落是仓库品味,copyWith 属投机)、行 id 十进制串过 Settings 集合(编码已文档化,与工单 32 内置集同构)、chart_providers.dart 曲库中枢持续膨胀(记录为未来拆分点)。

**范围外记录:** 导入谱不随备份导出(story 66,backup_doc 仍四表,restore 不清本表无数据丢失);后续票接 backup 格式与导入 UI(44)/轻改(45)。
