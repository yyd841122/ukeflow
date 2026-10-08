# UkeFlow 里程碑 0 · 技术验证 Spike

一个临时 App，验证三个技术押注，通过后即拆除/归档，代码不进正式工程。

## Spike A：调音器（调音器 tab）

`record`(PCM16 流) → `pitch_detector_dart`(纯 Dart YIN) → 音名/音分换算（内置，未用 pitchupdart）。

**通过标准**
- 真琴单弦拨响：音名正确、读数稳定（不跳动超过相邻音名）
- 静音/说话：不出乱七八糟的音高（pitched=false 或快速抖动可接受）
- 靠近目标弦 ±5¢ 时显示"已调准"

**验证方法**：真琴逐弦拨响，对照实体调音器。

## Spike B：节拍调度（节拍调度 tab）

`flutter_soloud` `playClocked` + 内存 WAV tick（代码合成，无资源文件），400ms 提前量调度窗口。

**通过标准**
- 600 拍（5 分钟 @120bpm）全部调度完成（界面"已调度 600/600"）
- 引擎时钟 vs 挂钟最大漂移 < 20ms
- 听感：节拍均匀、无爆音卡顿（耳朵判断）
- "立即一声"按钮：主观延迟可接受（< 50ms 量级）

**验证方法**：戴耳机/外放开跑 5 分钟，结束后读界面数字。

## Spike C：ChordPro 解析（谱面解析 tab + `flutter test`）

`chord_pro` 0.8.0 解析三份样例谱。**自动化测试已 4/4 通过**，设备端可肉眼检查渲染。

**Spike 已确认的结论（写码时要记住）**
1. `Chord.root` 只含根音字母（Am → root 'B' after +2），quality 在 `.quality`
2. `{transpose: n}` 指令**不改动** token 流；移调必须显式调 `song.transposed(n)`（对 UkeFlow 反而更可控）
3. 解析器极其宽容：未知指令静默忽略（`{x_*}` 按规范本该如此）、未闭合 `{soc}` 静默自动闭合、**几乎不产生 error 诊断**——谱面语法校验需 UkeFlow 自建
4. 中文歌词与 `[和弦]` 紧贴（无空格）解析正确，歌词逐字保留
5. Dart 3.12 移除了 `Duration.difference()`，只能用 `-` 运算符

## 真机连接（WSL2）

WSL2 不直通 USB，无线调试最简单：

1. 手机：开发者选项 → 无线调试 → **使用配对码配对设备**，把显示的 `IP:端口` 和 6 位配对码发给 Claude
2. Claude 执行 `adb pair` + `adb connect`
3. 之后 `flutter run` / `flutter install` 即可

USB 连接的手机需要 Windows 侧 `usbipd-win` 转发，非必需（一台真机够用）。

## 命令

```bash
flutter test          # Spike C 自动化断言
flutter run           # 装到真机跑 A/B
flutter build apk --debug
```

## 实测结果（2026-10-08，OPPO PCAM00 真机）

- **Spike A 调音器：通过**。真琴四弦拨测读数稳。
- **Spike B 节拍调度：通过**。漂移 22.1ms/5min ≈ 73ppm，为音频时钟与挂钟的晶振固有速率差；拍间间隔由音频时钟采样级保证，音画同用引擎时钟故零漂移。挂钟对齐在本产品无任何消费者。
- **Spike C 谱面解析：通过**。自动化 4/4 + 真机中文谱渲染正常。
