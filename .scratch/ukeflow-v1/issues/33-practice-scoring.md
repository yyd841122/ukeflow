# 33: 跟练评分（Practice Scoring）

**What to build:** 跟练加评分：麦克风听取实际弹奏，对时间轴上每个扫弦点（PlayStrumEvent，引擎时刻已知）判定 ✓/早/晚/漏/错（GLOSSARY「跟练评分」），跟练结束后出全曲报告，看完即弃不落库。仅弹唱谱、挂跟练流程内；实时提示、指弹评分、自由弹奏识别、历史留存一律不做。参照实现：ukulele-demo（持久克隆 /home/youyd/projects/ukulele-demo/flutter_app，OnsetDetector + strum_scorer + 延迟校准已真机验证）+ ukulele-glm（chord_recognizer 的 Chroma 管线）。

**Blocked by:** 无（依赖已收官的跟练引擎）

**Status:** implemented (awaiting device check)

- [ ] 跟拍弹奏：报告判定与人耳一致（准/早/晚不颠倒）；故意漏扫/抢拍/拖拍/按错和弦分别判出 漏/早/晚/错
- [ ] 节拍声全程开着弹完整首：无每拍误判扫弦的分数虚高（滤波承重墙真机实测）
- [ ] 全早/全晚时倾向提示方向正确；数拍自动校准生效，报告滑块可微调且保存跨会话生效
- [ ] 变速 50% 与 AB 循环：判定网格正确，循环重开清零，报告只反映最后一遍；暂停挂起、退出弃评
- [ ] 报告：扫弦点轨道按判定着色 + 点格重听该声 + 最差三处 + 行/小节聚合；drift 零改动、备份零改动

## Comments

- 2026-10-19 (拷问会话): 设计共识三轮定案，要点——**判定**：贪心全局最近配对（容差 180ms、准 ±50ms；高 BPM 窗口重叠时朴素逐拍最近会抢配，demo 踩过）；「错」= Chroma 目标和弦封闭验证（二值，不识别弹成了什么、不归因单弦；**全票唯一无真机验证环节，票内留 spike 调参**；glm 调用侧先例：==target 或 bestMatch==target 且 score>0.6，余音抖动配 ~300ms 冷却）。**采集**：record startStream PCM16/44.1kHz/mono，autoGain/echoCancel/noiseSuppress 全关（AGC 毁安静门、降噪毁频谱；现有 TunerRecorder 的这三项配置需先核实，不得直接复用未核实配置）。**时钟**：麦 chunk 到达即打引擎钟时间戳（ADR-0005 唯一时钟；demo 单开 Stopwatch 的做法不照抄），期望记录从首个麦 chunk 后开始，常量差交延迟校准吸收。**自家声音隔离（承重墙，demo 配方）**：评分中静音示范扫弦声、参考音强制切节拍声；节拍声换评分专用可滤嘀声（880Hz 正弦 30ms + 6ms 指数衰减 + 4ms 升余弦淡入；硬起音的宽带溅射是 demo 最大坑）；麦端 150Hz 高通 + 880/1320 双陷波 + 持续性门（上升沿候选需后续 2 帧撑住 minEnergy）；回归测试锁死「嘀声压 ≥40dB 且不误伤宽带扫弦」。**Onset 参数起点**（demo 默认）：能量通量、hop 10ms、自适应阈值 = 3×近 0.5s flux 均值（**阈值须用加入当前 flux 之前的滑窗均值**——顺序坑，滑窗无论是否触发都要更新）、fluxFloor 2e-4、minEnergy 3e-4、不应期 0.12s。**延迟校准（GLOSSARY）**：预备数拍期间用户照常扫四下取偏移中位数，采不到退回持久化值（默认 0.10s）；报告滑块 ±200ms、10ms 一档，拖动实时重算，可保存；倾向提示用 meanSignedError（整体偏早/偏晚→拖动方向）。**范围语义**：变速照评（网格随时间轴重编译）；AB 循环每遍独立、循环重开清零、报告只反映最后一遍；暂停 = 挂起（引擎钟冻结→时间轴冻结，评分自然停）；退出跟练页 = 弃评不弹报告；会话音频仅内存留存供重听，退页即弃。**已知限制（票面如实）**：只弹不唱场景调优，人声污染 Chroma；demo 前史教训——评分引擎造超前而 UI 没跟上会成死代码（commit 81be4f2→9728f65），先做纯函数 scorer + 薄接线。另：glm 无和弦识别准确率记录，其 NCCF 是单音检测器与和弦无关。
- 2026-10-20 (实现会话): **评分内核+薄接线落地,全库 768 测绿、analyzer 零告警(基线 694,+74)**。结构:纯函数内核 `lib/core/scoring/`(OnsetDetector 滤波链 HP150+880/1320 双陷波、贪心全局最近配对 strum_scorer、预备四拍中位数校准 calibration、Chroma FFT4096 封闭验证 chroma、Int16 会话音频缓冲 mic_audio_buffer、报告组装 report)+ 评分嘀声对 ScoringTickSynth(880/1320,4ms 升余弦淡入)+ 薄接线 `lib/features/play/scoring/`(PracticeScoringController 经 PracticeSessionHandle 窄缝读跟练会话,页与报告页)。
- **关键域决策**:onset 以**拍域**存(自调度锚点,拍数守恒)——变速/暂停重锚只动秒域映射,判定误差按各 onset 检出时的拍周期折秒,变速照评是结构保证;麦 chunk 到达即打引擎钟戳(ADR-0005,无第二时钟)。拍位公式单源 `PlayStrumEvent.scheduleBeat(prepBeats)`;容差/准窗单源 `strumToleranceSec/strumOnTimeWindowSec`。
- **承重墙回归**已锁(测试):稳态嘀声过链 ≥40dB(880/1320 各测)、嘀声轨零误报、嘀声+扫弦混弹只报扫弦、宽带过链损耗 <3dB。校准混入正曲 onset 经域界核算不可能(1 拍 ≥288ms>容差 180ms)。色度无证据(全零窗)不算错(时机判定为准)。
- **会话语义**:循环重开清零、报告只反映最后一遍、暂停挂起(挂起期 onset 不收)、退出弃评、一开播就停不弹报告。滑块重算走 per-onset 色度缓存零重付,重听定位随重算;重听一次性音源新听旧卸(AudioEngine.unload 新接口)。
- **双轴评审消化**(Standards/Spec):startPractice 权限弹窗后补 mounted 闸;采集三项(AGC/回声/降噪)在 RecordTunerRecorder 显式钉 false+核实结论注释(2.1.0 缺省即 false,已查源);其余重复收拢(拍位/容差/onsets 视图/matcher 缓存/测试信号夹具复用)。已知简化:评分会话结束后参考音停在节拍声不恢复会前选择(空闲面板可改,不改)。
- **真机待验清单**:①承重墙实测(节拍声全程开着弹整首,无每拍虚报);②真琴判定与人耳一致(漏/早/晚/错四向);③数拍自动校准效果与全早/全晚倾向提示方向;④Chroma 阈值 0.6 调参(票面 spike,唯一无真机环节——弹错和弦能否稳定判「错」);⑤变速度 50% 与循环实弹。过了转 done。