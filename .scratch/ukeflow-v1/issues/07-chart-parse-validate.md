# 07: 文本谱解析+校验+5 首目标曲录入

**What to build:** 曲谱地基(可验证型工单):ChordPro 文本→弹唱谱模型(chord_pro 0.8.0);自建校验层——段落闭合检查+和弦名白名单(对照和弦库数据),因为解析器极宽容、几乎不报错(ADR-0006)。5 首目标曲(爱你不是两三天、沧海一声笑、Big Big World、Love You More Than I Can Say、Yesterday Once More)手工录入为文本谱并全部通过解析+校验。spike C 的解析语义回归测试迁入。

**Blocked by:** 02 和弦库浏览

**Status:** ready-for-agent

- [ ] 5 首目标曲全部解析、过校验、可被后续工单取用(测试绿)
- [ ] 坏谱被校验拦截:未闭合段落、白名单外和弦名,错误信息可读可定位
- [ ] spike C 三语义回归测试迁入:root 只含根音字母(quality 分离)、{transpose} 不改 token 流、宽容性(未知指令/未闭合段落静默)
- [ ] 中文歌词与 [和弦] 紧贴解析正确(回归测试)
