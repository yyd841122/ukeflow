# 04: Karplus-Strong 拨弦合成器

**What to build:** 纯 Dart Karplus-Strong 拨弦合成:给定目标音高(如 G4/C4/E4/A4)合成拨弦 PCM,经引擎内存注入可发声(ADR-0004:合成兜底音源,音源与引擎解耦)。调研确认 Dart 生态无现成实现,自建。合成器本体纯函数化,测试不依赖引擎。

**Blocked by:** 03 节拍器页

**Status:** ready-for-agent

- [x] 四根空弦音基频误差 <1%(单测锁定:输出长度、基频、衰减包络)
- [ ] 合成 PCM 经引擎 loadMem 真机出声,听感"像拨弦"
- [x] 不同音高/持续参数化可调
- [x] 合成器单测全部纯 Dart,不启动引擎

## Comments

- 2026-10-12: 落地。切片 TDD:① `KarplusStrong.pluck(freq, ms, sampleRate, gain)` 纯函数——延迟线 N=round(fs/f) 定音高(四空弦整数量化误差 ≤0.45%),固定种子噪声激励保证逐字节确定性,时长取 t60 语义(整段 ms 即幅度降 60dB)反解损耗因子,末段 4ms 淡出兜截断爆音 ② `wav_pcm16` 共享 WAV 封装(TickSynth 一并收敛)③ `PluckPlayer` 引擎接缝(合成→loadMem→playClocked,按精确音高键缓存不重注入,`after` 延迟参数供工单 05 错峰琶音,错误上抛)④ `pluckPlayerProvider` 应用级装配 ⑤ `UkeString` 四空弦域模型(弦号/音名/等律基频,枚举序 4弦→1弦 齐指法 frets 下标)⑥ 调音器页"空弦试音"卡片(点弦名拨标准音)——真机听感验收入口,正式调音工单 19 迁入。测试 18 项纯 Dart 不启动引擎:WAV 头/长度按规范手工真值,四空弦基频用 Hann 窗 DFT 扫频+二次插值独立实测(期望值是等律理论字面量,不引自实现),分段 RMS 锁衰减包络+ms 翻倍衰减放慢+尾部无爆音;PluckPlayer×FakeAudioEngine(fake_audio_engine.dart 预定的工单 04 消费方式)锁缓存/预定时刻/after/错误路径。全量 121 测绿,analyzer 净。
- 2026-10-12: 双轴评审(Standards/Spec)结论:两轴均无硬违规。已修:TickSynth 接共享封装删私有副本(消文档失真)、测试 helper(sampleAt/peakOf)去重、缓存键改精确 double 串(近音高零碰撞)、PluckPlayer 提为 provider(页面重建不重注入)、`after` 补契约测试。Spec 轴认定 gain 参数/调音器入口/UkeString 模型为可辩护的轻微超范围。遗留观察项:音源缓存无上限且 EngineSound 无 unload 接口(每音 ~132KB PCM,工单 05 和弦示范若大量载入不同音高需留意);GLOSSARY 候选词条"空弦试音"待定。
- 2026-10-12: 装机成功(无线 adb 192.168.0.2:37155,冷启新包)。真机冒烟通过:启动无崩溃、空弦试音卡片与四弦钮可见、点"4弦 G"无异常、点后 audio_flinger 输出非 standby(混音活跃)、logcat 零引擎错误。**剩验收 2:四根弦各拨一耳朵听感"像拨弦",待用户亲测。**
