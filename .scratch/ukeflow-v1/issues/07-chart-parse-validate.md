# 07: 文本谱解析+校验+5 首目标曲录入

**What to build:** 曲谱地基(可验证型工单):ChordPro 文本→弹唱谱模型(chord_pro 0.8.0);自建校验层——段落闭合检查+和弦名白名单(对照和弦库数据),因为解析器极宽容、几乎不报错(ADR-0006)。5 首目标曲(爱你不是两三天、沧海一声笑、Big Big World、Love You More Than I Can Say、Yesterday Once More)手工录入为文本谱并全部通过解析+校验。spike C 的解析语义回归测试迁入。

**Blocked by:** 02 和弦库浏览

**Status:** done

- [x] 5 首目标曲全部解析、过校验、可被后续工单取用(测试绿)
- [x] 坏谱被校验拦截:未闭合段落、白名单外和弦名,错误信息可读可定位
- [x] spike C 三语义回归测试迁入:root 只含根音字母(quality 分离)、{transpose} 不改 token 流、宽容性(未知指令/未闭合段落静默)
- [x] 中文歌词与 [和弦] 紧贴解析正确(回归测试)

## Comments

- 2026-10-09: 落地。切片 TDD:① spike 三语义回归原样迁入 `test/parser_semantics_test.dart`(+样例谱 fixture)② `StrumChartParser.parse`(core/chart,唯一入口)→ `StrumChart` 纯模型(core/model,零 chord_pro 依赖,工单 08 只认这里):段落/行/歌词逐字/和弦标记带歌词内偏移 ③ 校验层:解析器诊断复判(未闭合/嵌套/多余结束/不匹配→error,含行列与指令原文)+和弦白名单(对照 `ChordLibrary.labels`,不认识/解析不了→error,坏谱不产出模型)④ `BuiltInCharts.load` 内置曲库清单加载器(坏资产当场抛错)+ `builtinChartsProvider`(data/chart_providers.dart)。62 测试全绿,analyzer 无告警。
- 2026-10-09: **歌词为占位符待人工录入**(版权内容,需本人录入核对——spec「内容工作是硬任务」)。5 首 .pro 的和弦、段落结构、元数据已就位,歌词行是 `♪`,替换方法见 `assets/charts/README.md`:逐行把 ♪ 换成正式歌词(和弦记号不动),改完 `tool/check.sh full` 自动重新解析+校验全部资产。和弦编配为 C 调新手版(经检索常用谱:沧海一声笑 Am-Dm-G-C 五声循环等),速度/和弦**以对照原曲核对为准**,谱内有 {c:} 提示。
- 2026-10-09: 范围说明:节奏型不进 StrumChart(同一首谱可换节奏型练,故事 23;弹唱谱+节奏型+BPM→时间轴是工单 08 的编译参数,模型 doc 注明)。校验比工单多两小项:{new_song} 多歌拦截(导入工单 16 依赖)、解析器 error 级诊断兜底——都是「坏谱不进库」同一语义。白名单是精确匹配(谱面写法=和弦库显示名),保证按名查指法/示范音必命中。
