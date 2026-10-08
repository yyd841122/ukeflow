# 音频与采集骨干：flutter_soloud + record + pitch_detector_dart

 Spike B/A 实测通过后锁定。flutter_soloud 独家提供 playClocked 采样级调度与 loadMem 内存 PCM 注入（Karplus-Strong 合成_pcm 的直接入口），单库覆盖节拍器、扫弦触发、拨弦合成、逐音指弹示范四类发声，MIT、极活跃；soundpool（约 3 年未发版）、metronome 专用包（仅覆盖节拍）、just_audio（非低延迟场景）被否决。调音链路 record（PCM16 流）+ pitch_detector_dart（纯 Dart YIN），Spike A 真琴验证稳定。已量化的约束：引擎时钟与挂钟存在 ~73ppm 固有速率差，产品内一切时间同步只认引擎时钟（getEngineTime），禁止用挂钟做音画对齐。
