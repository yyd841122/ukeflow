# 04: Karplus-Strong 拨弦合成器

**What to build:** 纯 Dart Karplus-Strong 拨弦合成:给定目标音高(如 G4/C4/E4/A4)合成拨弦 PCM,经引擎内存注入可发声(ADR-0004:合成兜底音源,音源与引擎解耦)。调研确认 Dart 生态无现成实现,自建。合成器本体纯函数化,测试不依赖引擎。

**Blocked by:** 03 节拍器页

**Status:** ready-for-agent

- [ ] 四根空弦音基频误差 <1%(单测锁定:输出长度、基频、衰减包络)
- [ ] 合成 PCM 经引擎 loadMem 真机出声,听感"像拨弦"
- [ ] 不同音高/持续参数化可调
- [ ] 合成器单测全部纯 Dart,不启动引擎
