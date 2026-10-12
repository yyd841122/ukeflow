# 03: 节拍器页(SoloudEngine+TickSynth+调度)

**What to build:** 音频地基:音频引擎封装(init、引擎时钟暴露、内存 PCM 注入入口)+代码合成节拍 WAV(无资源文件)+playClocked 提前量调度(400ms 窗口/40ms 轮询,spike B 已验证参数)。节拍器页:BPM 可调、启停、4/4 强弱拍。ADR-0005 唯一时钟规则自此工单起贯彻:产品内一切时间同步只认引擎时钟。引擎封装提供假实现,供后续工单测试。

**Blocked by:** 01 工程骨架与五页导航壳

**Status:** ready-for-agent

- [ ] 真机 120 BPM 连跑 5 分钟:600/600 拍全部调度完成,听感均匀无爆音
- [x] BPM 大范围可调(40–208)且即时生效
- [x] 调度窗口决策为纯函数并有单元测试(假时钟驱动)
- [x] 引擎封装有假实现,后续工单可用它测试而不碰真引擎
- [x] 代码中无任何挂钟参与音画对齐的路径(对照 ADR-0005)

## Comments

- 2026-10-12: 落地。切片 TDD:① `TickSynth` 代码合成节拍 WAV(强拍 1kHz/弱拍 600Hz,指数包络,零资源文件;头结构+声学量独立真值测试)② `AudioEngine` 接口封装(init/唯一时钟/loadMem/playClocked/stop)+ `SoloudAudioEngine` 真实现(spike B 参数:44.1kHz/buffer1024/mono/lowLatency)+ `FakeAudioEngine` 假实现(手动驱动时钟、scheduleLog 全量记录,后续工单不碰真引擎可测)③ `BeatSchedule` 调度窗口决策纯函数(拍时刻 = t0+round(i×period)ms,窗语义与 spike B 一致;含 5 分钟 600 拍零缺口回归与换速 reanchor 相位保持测试)④ `BeatScheduler` 驱动器(40ms 轮询/400ms 窗写死,Timer 仅作触发器;出错上报自停)⑤ 节拍器页(BPM 滑杆+±钮钳制 40–208、启停、4/4 拍点+拍号、已预定拍数可核对 600/600)。101 测全绿,analyzer 无告警。
- 2026-10-12: 唯一时钟审计:lib/ 内无 DateTime/Stopwatch(唯一字样是禁止它的文档注释);Timer.periodic×2(调度 40ms、UI 16ms)均为纯触发器,时刻一律读引擎时钟,UI 拍状态经 `beatAt` 纯函数(ADR-0005 ✓)。跨模型双轴评审修正:真实现去 `_sounds` 冗余表(强转直取 source)、`EngineVoice.id` 降出接口(Fake 内部记账)、"4/4"收敛为 `beatsPerBar` 领域常量、驱动器旋钮参数删除(spike 参数写死)、死引擎读时钟返回零点而非抛(停机路径仍会读)、轮询随运行启停(空闲页零定时器)。
- 2026-10-12: 已知边界(供后续工单):FakeAudioEngine 不校验预定时刻 ≥ now 与 playClocked ~2 秒窗(真引擎的窗口约束假引擎测不出);reanchor 在轮询停滞的病态下会丢弃过期拍(正常 40ms 轮询不可达);入口暂挂跟练页(壳无 rhythm 页签,工单 09 重做 PlayPage 时须迁移,已在其票注明)。APK(67MB)已出包。
- 2026-10-12: 装机成功(无线 adb 重连 192.168.0.2:37155)。真机冒烟通过:启动无崩溃、跟练页入口直达节拍器、引擎就绪(SoLoud 初始化无错)、120 BPM 运行 4 秒已预定 10 拍(=4s×120BPM+提前量 2 拍,精确吻合)、拍点/拍号随动、运行中 + →121 即时生效不断流、停止复位干净、logcat 零引擎错误。**剩验收 1:120 BPM 连跑 5 分钟核对 600/600 与听感无爆音,待用户亲测。**
