# 44: 导入页（选 JSON → 校验 → 预览 → 确认入库）

**Status:** done

**Blocked by:** 43

**What to build:** 曲库入口新增「导入识谱源」：file_selector `openFile`（先例 backup_flow.dart）选 .json → validator 全检（阻塞错误逐条人话列出）→ 预览页复用谱面视图渲染（试物化）→ 命名+确认入 `ImportedSoloCharts`。重复 contentSha 提示已存在。

**Non-goals:** PDF 直选（识别在电脑端，App 只吃校对后的 JSON）；编辑（45）。

## Comments

- 2026-10-26 (落地·914 绿): 五件套——①core 预检缝 `checkScoreIrSource`(imported_solo_charts.dart):一次解析两用,坏源逐条人话全量列(与读出管线首异常即抛 deliberately 分岔,入口要一次亮全问题),合法则 IR 在手;②DAO `getByContentSha` + `_shaOf`→公开 `shaOf`(查重与入库同一指纹函数,口径不许漂移);③`ScoreSourceImportFlow`(image_pick_flow 模式):选 .json→解码→校验全检→查重→试物化,picker/查重注入;校验先行于查重(坏源不值得查重);④`ImportScoreSourcePage`:ScoreStripView 静态读谱预览 + 命名(建议名=文件名去扩展名,回退源内曲名)+ 入库名覆盖照 43 纪律,reviewedAt 照录;⑤独奏谱类目「导入识谱源」入口,坏源对话框逐条列 + 「重新选择」闭环,重复 contentSha 提示已有条目名。测试 25 新增(core 4/dao 2/flow 9/页 5/曲库 5);全量 914 绿 + analyzer 净。评审消化:真库"关掉再写"不炸(探针证伪)故落库故障走 provider 覆盖注入;9 个无关文件被 dart format 重排已还原保持提交聚焦。真机验走装机后(选源→预览→入库→跟练全链)。
