# 48: 版面切分（四层条带 + 小节 + 拍位网格）

**Status:** ready-for-agent

**Blocked by:** 47

**What to build:** 位图路径：300-400dpi 渲染 → 倾斜纠正 → 按谱全版式规则切四层条带（和弦图+和弦名 / TAB / 简谱 / 歌词）→ 小节线定位 → 每小节候选拍位 x 网格。像素考古结论直移（页宽 993×1404、tabLineGap≈14px@scale3；读谱约定见工单 39 与 docs/research/2026-10-25-pdf-census-gs-aini.md）。输出：逐系统逐层裁图 + 小节/拍位骨架 JSON，bbox 证据全程携带。

**Non-goals:** 符号识别、矢量 PDF 路径。
