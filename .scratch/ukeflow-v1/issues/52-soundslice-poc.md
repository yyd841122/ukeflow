# 52: Soundslice 免费档 PoC（需人工操作）

**Status:** ready-for-human

**What to build:** 用户注册 Soundslice 免费档（2 次扫描/月、单次 1 页 32 小节），上传一张谱全了样张（选含典型记号的一页），导出 MusicXML，记录：四弦 TAB 是否被识别、节奏是否如官方博客自认全落四分音符、和弦图/简谱层的下落。结论回填 docs/research/2026-10-26-vlm-jianpu-tab-scan.md 待验证区。已知预期：tab-only 节奏不识别（官方 2022-11 博客自认）；本 PoC 只为实测上限，**不作管线依赖**。
