# 28: 搜索源适配器——Ultimate Guitar(英文歌大库)

**What to build:** Cifra Club 之外的第二个搜索源适配器(GLOSSARY「搜索源」复数设计的第二站):Ultimate Guitar 的 Ukulele 专区。搜索→结果→取谱→转换为文本谱→走 17 的校验入库管线(管线复用,适配器只做「取+析」)。界面同 27 的原生结果列表方向(若 27 先落地,本票只加一个数据源)。

**Blocked by:** 无硬依赖;若 27(原生搜索列表)先落地,适配器按其列表框架接入

**Status:** needs-triage

- [ ] spike:真机 WebView 载 UG 搜索/曲谱页,确认 Cloudflare 放行 + 嵌入 JSON 可取
- [ ] 结果列表(ukulele 类型过滤)接入原生搜索 UI
- [ ] 嵌入 JSON → 文本谱转换(Ukulele 型谱),过同一校验层
- [ ] 提取失败给可读失败态(不崩溃)

## Comments

- 2026-10-16 (立票): 用户定向讨论四方向之一,「都先立票缓行」。**已知情报(2026-10-16 实测+调研)**:①全球最大曲谱库,英文歌覆盖第一,有 UKULELE 类型;**中文歌零覆盖**。②反爬 Cloudflare;服务端直抓实测只回标题壳(`<title>Let It Be, 348 chords & tabs found</title>`,正文 JS 渲染)——与 Cifra Club 同逻辑:取走 WebView(真实浏览器指纹),析走**嵌入 JSON**(`window.UGAPP.store` / `__VIEWER_STATE` 类结构)而非 DOM。JSON 是结构化数据,解析比 DOM 稳,但 schema 随站点版本漂移,防御式解析纪律同 17(data-* 级别的稳定锚点要先 spike 找)。③ToS 严格(禁抓取条款)——纯自用缓存立场与 17 相同(GLOSSARY/研究文档 §5.3),任何分享/再分发功能都不要带它。④搜索结果页/曲谱页在 WebView 里的真实表现(放行与否、JSON 结构、ukulele 类型怎么过滤)必须先做 spike 再排实现——本票第一步就是 spike,不要直接写适配器。⑤工作量显著大于 27,收益是英文歌覆盖(用户听英文歌时的主库)。
