# UkeFlow 前期调研：同类项目与 Flutter 生态轮子

> 调研日期：2026-10-08。所有 star/like 数、最近活跃时间均为当日通过 GitHub API 与 pub.dev API 实查所得；未实查的一律标注"未验证"。纯自用项目，GPL 类许可可用但单独标注。

---

## 1. 摘要

1. **调音器可以完全用现成轮子拼出来**：`record`（麦克风 PCM 流）+ `pitch_detector_dart`（YIN 算法，纯 Dart）+ `pitchupdart`（音符换算）三者组合即是完整方案，全部 BSD-3/MIT，许可无忧。也可选 `flutter_pitch_detection`（Android 端内置 TarsosDSP，连权限都替你处理）。
2. **ChordPro 解析有现成 Dart 包 `chord_pro`（MIT，2026-09 发布，支持 ChordPro 6 规范）**，配套渲染/移调/自动滚动可用 `flutter_chord`（40 likes）。但 `chord_pro` 很新（仅 1 like），需试用验证；备选移植源是 JS 的 ChordMark（MIT，可放心移植），ChordSheetJS 虽然最成熟但是 GPL-2.0（纯自用没问题，仅标注）。
3. **音频引擎建议押注 `flutter_soloud`**（613 likes，MIT，极活跃）：`playClocked/playScheduled` 提供"采样级精确调度"（官方原话"Perfect for metronomes, music sequencers, rhythm games"），实验性 render-ahead 环形缓冲把触发延迟压到约 10ms，且支持 `loadMem` 加载内存 PCM——这一家就同时覆盖节拍器、采样触发、Karplus-Strong 兜底三个需求。
4. **Karplus-Strong 没有任何 Dart/Flutter 现成实现**（GitHub `language:dart` 搜索结果为 0，pub.dev 无相关包）——必须自研，但算法本身是教科书级（约 50~100 行延迟线+平均滤波），难点在工程接入而非算法。
5. **Cifra Club 有真实反爬（Akamai）**：本机直连第二次连续抓取即 403 且数分钟不解除；但成功抓到的页面是服务端渲染的规整 HTML（和弦带 `data-chord-name` 属性、内容集中在 `data-chord-content` 的 `<pre>` 里），解析本身不难，**难在"取"不在"析"**，App 内应走 WebView 取页面再解析。
6. **免费尤克里里采样存在且许可干净**：GitHub 上有两个 CC0 尤克利采样包（单音拨弦，含闷音/揉弦/滑音/泛音）；扫弦采样在 freesound.org 有 95 个 CC0 结果但质量参差。更稳的路线是用单音采样 + 按弦间延迟错开调度来"合成"扫弦（已有同类 App 验证此做法），加上 KS 合成兜底，音源方案闭环。

---

## 2. 直接可用轮子

### 2.1 调音器（功能 1）

| 包 | 版本/发布 | likes/points | 许可 | 用途 |
|---|---|---|---|---|
| [record](https://pub.dev/packages/record) | 7.1.1 / 2026-06-29 | 894 / 160 | BSD-3 | 麦克风录音到流或文件，Android 支持 pcm16bits 流式输出（README 明确列表） |
| [pitch_detector_dart](https://pub.dev/packages/pitch_detector_dart) | 0.0.7 / 2024-04-09 | 26 / 160 | BSD-3 | 纯 Dart YIN 算法（自 TarsosDSP 移植）；[仓库](https://github.com/techpotatoes/pitch_detector_dart) 2026-02 仍有提交 |
| [pitchupdart](https://pub.dev/packages/pitchupdart) | 0.0.6 / 2024-04-09 | 14 / 155 | BSD-3 | "用于实现你自己的调音 App"——音符名/目标音偏差换算 |

**怎么用**：`record` 以 44.1kHz/pcm16 流式吐缓冲 → `pitch_detector_dart` 逐帧算频率 → `pitchupdart` 换算成 GCEA 四弦最近音与音分偏差 → UI 画表针。发布时间偏旧（2024-04）但算法稳定、纯 Dart 无平台耦合，出问题也可自行内联（YIN 单文件即可）。

**备选（一体化插件）**：[flutter_pitch_detection](https://pub.dev/packages/flutter_pitch_detection)（1.3.1 / 2025-05-09，5 likes，MIT）——Android 端用 TarsosDSP 实时检测，返回频率/音名/八度/音量/准确度，[仓库](https://github.com/mattiolichiara/flutter_pitch_detection) README 称自动处理麦克风权限、采样率与缓冲可配。缺点：Android-only（对 Android 先行无碍，迁 iOS 时需另找）。[flutter_fft](https://github.com/Slins-23/flutter-fft)（52 likes，2021 年后未更新）是个人项目性质，不推荐。

**参考实现**：[mishkov/guitar_tuner](https://github.com/mishkov/guitar_tuner)（Flutter，GPL-3.0，2026-09 仍活跃）、[CrispStrobe/flutter_tuner](https://github.com/CrispStrobe/flutter_tuner)（MIT，2026-10-06 提交，纯 Dart 调音器）可对照学习缓冲/滤波细节。

### 2.2 和弦库（功能 2）

| 包/仓库 | 数据 | 许可 | 说明 |
|---|---|---|---|
| [chords-db](https://github.com/tombatossals/chords-db) | 586★，JS，2026-05 提交 | MIT | 最流行的开源和弦指法数据库，`lib/ukulele.json`（215KB，已实查存在）含全套尤克里里指法；可直接把 JSON 数据抽出来做 UkeFlow 内置库的数据源 |
| [guitar_chord_library](https://pub.dev/packages/guitar_chord_library) | 0.1.0 / 2026-09-19，6 likes | Apache-2.0 | "吉他和尤克里里的和弦库"，升/降号都支持 |
| [flutter_guitar_chord](https://pub.dev/packages/flutter_guitar_chord) | 0.1.0 / 2026-09-19，15 likes | Apache-2.0 | CustomPainter 绘制的和弦指法图 widget |
| [chord_diagrams](https://pub.dev/packages/chord_diagrams) | 0.7.0 / 2026-04-04，1 like | MIT | 从和弦名直接出吉他/尤克里里指法图 |
| [react-chords](https://github.com/tombatossals/react-chords) | 237★，2025-10 提交 | MIT | SVG 和弦图渲染库（React），可借鉴其绘制参数设计到 CustomPainter |

**怎么用**：数据用 chords-db 的 ukulele.json（或 guitar_chord_library 的数据结构），渲染用 flutter_guitar_chord / chord_diagrams 之一；示范音用 2.4 的音频方案（见 §5 采样资源）。

### 2.3 ChordPro / 和弦谱解析（功能 4、5、7 的文本谱路线）

| 包 | 版本/发布 | likes | 许可 | 说明 |
|---|---|---|---|---|
| [chord_pro](https://pub.dev/packages/chord_pro) | 0.8.0 / 2026-09-20 | 1（points 160/160） | MIT | **纯 Dart 的 ChordPro 6 规范解析器**：类型化和弦/歌词/元数据/注释/图片/布局提示/和弦图，零依赖，解析不抛异常而返回带稳定错误码的 diagnostics，AST 不可变可 diff/缓存，内置移调。[仓库](https://github.com/ryzizub/chord_pro)文档很全。**注意：极新、用户极少，采用前先拿真实谱面试用** |
| [flutter_chord](https://pub.dev/packages/flutter_chord) | 0.1.3 / 2026-07-09 | 40 | MIT | 解析+渲染"和弦上方歌词"式文本，带移调与**自动滚动**（跟练模式相关）；[仓库](https://github.com/paurakhsharma/flutter_chord) 31★，2026-10-08 仍有提交 |
| [custom_flutter_chord](https://pub.dev/packages/custom_flutter_chord) | 1.2.2 / 2026-08-12 | 9 | MIT | flutter_chord 的增强 fork，同样带移调/滚动 |
| [tonic](https://pub.dev/packages/tonic) | 0.2.5 / 2024-03-06 | 40 | （pub.dev 标注，未细查） | 乐理基础类（Pitch/Interval/Chord），做移调、音名换算顺手 |

**JS 生态（移植源/对照）**：
- [ChordSheetJS](https://github.com/martijnversluis/ChordSheetJS)：444★，TypeScript，2026-10-07 仍活跃，**GPL-2.0**。功能最全（解析+多种格式化输出），但移植其代码会传染 GPL——纯自用无碍，仅标注。
- [ChordMark](https://github.com/no-chris/chord-mark)：93★，2026-07-13 活跃，**MIT**。自带语法（歌词+和弦+**节奏信息**三合一）与 `chord-mark-converters` 转换包，可从 ChordPro 转入转出；MIT 移植无负担。在线文档与试玩：chordmark.netlify.app。
- [chord-symbol](https://github.com/no-chris/chord-symbol)：195★，MIT，和弦记号解析/渲染（Am7、C#m7b5 之类），2023 年后未更新但功能完备。

### 2.4 节拍器 / 精确音频调度 + 短采样触发（功能 3、4、5）

| 包 | 版本/发布 | likes | 许可 | 说明 |
|---|---|---|---|---|
| [flutter_soloud](https://pub.dev/packages/flutter_soloud) | 5.1.6 / 2026-10-02 | 613 | MIT | C++ SoLoud 引擎封装。[README 明示](https://github.com/alnitak/flutter_soloud)：`playClocked` 采样级精确播放（"Perfect for metronomes, music sequencers, rhythm games"）、`playScheduled` 整批调度、实验性 render-ahead ring（按键到出声约 10ms）、`loadMem` 内存加载 PCM、实时波形合成、Ogg/Wav/MP3/FLAC 解码 |
| [metronome](https://pub.dev/packages/metronome) | 2.0.13 / 2026-07-28 | 18 | BSD-3 | 专用的跨平台节拍器：2.0 重写后 BPM>600、强拍/拍号回调；[Android 实现](https://github.com/biner88/metronome/blob/main/android/src/main/java/com/sumsg/metronome/Metronome.java)是 AudioTrack MODE_STREAM + PCM 合成（已实查源码），天然无漂移 |
| [soundpool](https://pub.dev/packages/soundpool) | 2.4.1 / 2023-08-25 | 245 | MIT | 短音频内存池低延迟播放的经典方案；**约 3 年未发版**（2023-08），代码稳定但维护趋停，谨慎依赖 |
| [just_audio](https://pub.dev/packages/just_audio) | 0.10.6 / 2026-06-29 | 4150 | （pub.dev 标注） | 完整播放器，适合整曲示范试听（非低延迟场景）；配套 [audio_session](https://pub.dev/packages/audio_session)（365 likes）管理音频焦点 |
| [soundfont_kit](https://pub.dev/packages/soundfont_kit) | 1.1.1 / 2026-10-02 | 1 | MIT | SF2/SF3/SFZ 读取+播放引擎，flutter_soloud 作者的伴生包（采样 SoundFont 路线的直接选项）。极新，需验证 |
| [dart_melty_soundfont](https://pub.dev/packages/dart_melty_soundfont) | 2.0.0 / 2025-08-10 | 50 | MIT | **纯 Dart** 的 SF2 合成器，做离线渲染或经流播放皆可；MIDI 路线（尼龙弦吉他音色代用）的关键件 |
| [flutter_sequencer](https://pub.dev/packages/flutter_sequencer) | 0.4.4 / 2022-03-01 | 63 | （未细查） | SFZ/SF2 音符序列器，2022 年后未更新——作为设计参考，不建议直接依赖 |

**建议组合**：`flutter_soloud` 单家覆盖"节拍器 tick + 扫弦采样 + KS 合成 PCM + 逐音指弹示范"（playScheduled 错开各弦即可合成扫弦），`metronome` 包可作为纯节拍器场景的降级备选。

### 2.5 指弹谱（tab）相关（功能 4、5 的对照）

| 项目 | 数据 | 许可 | 说明 |
|---|---|---|---|
| [CoderLine/alphaTab](https://github.com/CoderLine/alphaTab) | 1861★，TypeScript，2026-10-08 活跃 | **MPL-2.0**（LICENSE 已实查："alphaTab is licensed under MPL-2.0"） | 最主流的开源吉他谱渲染/播放引擎（Guitar Pro 格式、alphaTex），**只有 Web/.NET，无 Flutter 版** |
| [flutter_guitar_tabs](https://pub.dev/packages/flutter_guitar_tabs) | 0.0.10 / 2023-09-18，19 likes | BSD-3 | 显示用 tab widget（空弦/闷音/横按），无播放、未跟进 Flutter 新版 |
| [dart_gp_tab_reader](https://pub.dev/packages/dart_gp_tab_reader) | 0.4.0 / 2026-07-29，0 like | **LGPL-3.0** | 纯 Dart 只读解析 Guitar Pro GP3~GP8——虽然"指弹谱导入"明确不做，但若日后反悔，这是唯一的 Dart 现成入口 |
| [helge17/tuxguitar](https://github.com/helge17/tuxguitar) | 1550★，Java，2026-10-08 活跃 | **LGPL**（help/license.html 实查为 GNU LGPL） | 开源 tab 编辑器标杆；事件模型（track/measure/beat/note）可作为 UkeFlow 指弹事件数据模型的设计对照，也能用来制作练习材料 |

### 2.6 图片谱查看器（功能 7 的只读查看）

- [photo_view](https://pub.dev/packages/photo_view)：0.15.0 / 2024-04-17，3205 likes——手势缩放查看大图的事实标准，直接满足"图片谱只读查看器"。（发版 2024 年，但该品类已无需求缺口。）

### 2.7 本地存储（功能 6、7 打卡/曲库）

- [drift](https://pub.dev/packages/drift)：2.35.2 / 2026-10-07，2479 likes，160/160 points——Flutter 生态最活跃的响应式关系型存储。同类的 Isar/Hive 等本次未逐一核验（未验证），选型时可再对比。

---

## 3. 值得借鉴设计（不抄代码）

**[pandulapeter/campfire](https://github.com/pandulapeter/campfire)**（Kotlin Multiplatform 歌本+节拍器，101★，MPL-2.0，2026-10-08 活跃，Google Play 上架）——同类中最成熟的开源实现：
- **节拍器"每一下按采样数放置而非靠定时器"**（README 原话：so it never drifts）——UkeFlow 跟练模式的画面同步务必采用同一原则：用一个音频时钟（采样计数）驱动 UI 帧计算，而不是 `Timer.periodic`。
- **ChordPro 解析/移调/序列化独立成零依赖模块**，UI 可整体替换——值得照抄的架构分层。
- **"一切皆文件"**：歌曲是 `.cho`、歌单是小 JSON，不锁进数据库；纯自用 App 尤其该如此（备份/迁移零成本）。
- 每首歌自带 BPM/拍号/调性/夹品位置；setlist 按歌自动切；只读模式防误编辑；功能开关面板。

**[baijum/ukulele-companion](https://github.com/baijum/ukulele-companion)**（离线尤克里里学习 App，14★，MIT，2026-10-08 活跃，双商店上架）——**与 UkeFlow 功能重叠度最高**，功能清单值得逐条对照（已实查 README）：
- **混合调音器**：每帧跑快速 YIN + 间隔性神经网络推理纠偏（防八度错误/不稳定帧）——UkeFlow 可借鉴"YIN 为主 + 中值/置信度滤波"的工程化思路。
- **节奏型训练器**：14 种扫弦 + 10 种指弹模式（4/4、3/4、6/8），每步可视化 + 可调速度试听 + 自定义模式——与 UkeFlow 功能 3 几乎重合，交互可对标。
- **歌本**：行内和弦标记（`Some[C]where`）实时预览、Performance Mode 全屏自动滚动、一键跳转段落、歌曲关联节奏型、**练习时长/浏览次数统计**（对应 UkeFlow 打卡）。
- **扫弦发声 = 单音采样按弦间延迟错开播放**（README 原话：strummed with a configurable delay between strings）——直接验证了"用单音采样合成扫弦"路线，省掉扫弦采样需求。
- 和弦 voicing 算法生成 + 长按收藏；tap tempo；节拍器按歌曲 BPM 一键启动。

**[artutra/OpenChord](https://github.com/artutra/OpenChord)**（React Native 歌本，165★，GPL-3.0，2023 年后停滞）：教训型参照——核心曲库依赖自建 API（OpenChordApi，README 自述 BETA 不可靠），App 随 API 一起失去维护。UkeFlow 的"内置手工曲库打底"策略是对的，外部导入必须是锦上添花而非命脉。

**[olvidalo/obsidian-chord-sheets](https://github.com/olvidalo/obsidian-chord-sheets)**（Obsidian 和弦谱插件，176★，MIT，2026-09 活跃）：chords-over-lyrics 与行内 `[Am]` 两种格式都解析、吉他/尤克里里指法图联动、移调——对"粘贴文本导入"的宽容度设计（用户什么格式都可能会贴）有直接参考价值。

**[Desbeers/Chord-Provider](https://github.com/Desbeers/Chord-Provider)**（Swift ChordPro 解析/编辑器，140★，GPL-3.0，2026-10 活跃）与 **[buzcarter/UkeGeeks](https://github.com/buzcarter/UkeGeeks)**（尤克里里 ChordPro 网页渲染，108★，**无 License 文件，代码不可复用，仅看设计**）：UkeGeeks 的亮点是"按尤克里里定音重新解释和弦"（吉他谱转 uke 指法），UkeFlow 曲库迟早遇到这问题。

**[UkuleleTuesday/songbook-generator](https://github.com/UkuleleTuesday/songbook-generator)**（4★，2026-10 活跃，无 License）：真实尤克里里社团在用的 ChordPro→PDF 歌本流水线，说明"文本谱为中心"的工作流在真实人群里成立。

---

## 4. 明确要自己造

1. **Karplus-Strong 拨弦合成（Dart 实现）**：GitHub `karplus language:dart` 搜索 **0 结果**，pub.dev "karplus" 无相关包（均已实查）。必须自写。参考实现：[mrahtz/javascript-karplus-strong](https://github.com/mrahtz/javascript-karplus-strong)（304★，**无 License，只读参考不拷码**，其系列博客讲透了调参）；算法本体约 50~100 行，经 `flutter_soloud.loadMem` 送入引擎即可。
2. **跟练模式同步引擎**（当前动作大字 + 左侧"下一块"预告 + 谱面滚动/高亮）：没有任何现成包做"节拍驱动的谱面时间轴 + UI 高亮调度"。可行方案：`flutter_soloud` 的引擎时钟/`metronome` 的 tickCallback 提供权威时间轴，UI 层按采样时钟插值推进（参考 campfire 的 sample-count 原则）。
3. **指弹谱逐音事件模型 + 实时高亮渲染**：Flutter 没有类 alphaTab 的渲染/播放引擎（alphaTab 本身仅 Web/.NET），flutter_guitar_tabs 只是个静态展示 widget。UkeFlow 本就定义为自有事件模型（弦/品位/时刻），渲染用 CustomPainter 自绘是必然，也是工作量可控的部分。
4. **ChordPro → 跟练时间轴的编译器**：把解析后的 ChordPro 谱 × 节奏型 × BPM 展开成带时刻的事件流（哪个和弦、下/上、何时）。这是 UkeFlow 的核心领域逻辑，无现成物，必须自研。
5. **Cifra Club 导入器**：Dart 生态没有任何现成爬虫/解析器（实查）；且见 §5 反爬结论，取页面要走 WebView。解析器本身简单（`data-chord-name` 属性直出和弦名），但**解析规则要自己维护**（CSS 类名是混淆的 `kvMV`/`XjgwI`，只有 `data-*` 属性相对稳定）。
6. **30 天课程内容 + 打卡**：纯内容与本地状态，无轮子可言；存储用 drift 或文件均可。

---

## 5. 风险与空白

### 5.1 Cifra Club 反爬（实锤，2026-10-08 实测）
- 实测过程：完整浏览器头首两次请求成功（艺人页 200、歌曲页 `embrace/gravity/` 200），随后以 0.4s 间隔连抓 4 页**全部 403**（Akamai，返回 `errors.edgesuite.net` 拒绝页）；冷却 12 秒重试仍 403；数分钟后重试**仍 403**（本机 WSL2 出口 IP 疑似已进黑名单）。
- 页面结构（成功抓取时已确认）：服务端渲染、无需执行 JS。歌曲正文在 `<pre data-chord-content="true" ...>` 内，按行分 `<div>`，每个和弦是 `<b data-chord-name="D#" data-chord-index="0" data-chord-original-text="D#">D#</b>`（和弦名直接在属性里，空格保留做对齐），歌词为同行纯文本；页面含 `ld+json`（歌曲/艺人元数据）。**解析极其规整，风险全在获取端。**
- 结论与建议：① 不要用 Dart HttpClient 直连；② 用 App 内 WebView 加载真实页面（真实浏览器指纹+Cookie+JS 挑战可过），再从 WebView 取 HTML 解析；③ 节流 + 失败优雅降级到"粘贴文本导入"；④ `data-*` 属性可能改版，解析器按防御式写。

### 5.2 采样资源
- **已确认可用（CC0，许可零负担）**：
  - [thgrund/samples-ukulele](https://github.com/thgrund/samples-ukulele)：Ortega 尤克里里（C 调定音），12 个 WAV 约 4.5MB：长/短 × 轻/重音、闷音、揉弦×2、上/下滑音、泛音、闷音死音（上/下扫）——**单音拨弦齐全，正是"采样优先"要的东西**。
  - [NeoSoundFonts/SimonePiervergili-Ukulele](https://github.com/NeoSoundFonts/SimonePiervergili-Ukulele)：Mahalo Hano 尤克里里，SFZ + 9 个 WAV（MIDI 60~81），可直接进 SoundFont 路线（soundfont_kit / dart_melty_soundfont）。
  - freesound.org 搜 "ukulele strum" 过滤 CC0 得 **95 条结果**（搜索页实查计数），但标题显示质量参差（玩具琴、失败录音混在其中），需要人工筛选；API 需注册 key，网页搜索可用。
- **缺口与对策**：专用"和弦扫弦"采样的 CC0 货源不稳 → **用单音采样按弦间延迟错开调度合成扫弦**（ukulele-companion 已验证此做法，`flutter_soloud.playScheduled` 天然支持）；KS 合成作为音色兜底和无限把位的补充。
- **MIDI/尼龙弦吉他代用路线**：技术上通（dart_melty_soundfont + 任一 SF2），但音色"不是尤克里里"，仅作对比实验，不作主路线（具体尼龙弦 SF2 的 CC0 货源本次未验证）。

### 5.3 许可注意点（纯自用前提下）
- **GPL-2.0（ChordSheetJS）/ GPL-3.0（OpenChord、Chord-Provider、Kords）/ LGPL-3.0（dart_gp_tab_reader）/ Artistic-2.0（ChordPro 官方 Perl 实现）**：自用、不分发即无义务开源；**若日后把 UkeFlow 挂到公开仓库或分发 APK，拷了这些代码的部分需按同许可开源**。最干净的做法：这些项目只读思路，需要"移植"一律优先 MIT/MPL/BSD 源（ChordMark、alphaTab、TuxGuitar-LGPL 部分例外规则见原许可）。
- **UkeGeeks、mrahtz/javascript-karplus-strong 无 License**：默认保留所有权利，**代码一行都不可拷**，只作设计与算法理解参考。
- chords-db 的 JSON 数据（MIT）抽取数据进 UkeFlow 内置曲库没有问题。
- Cifra Club 内容本身有站点版权，纯自用缓存没问题，任何分享/再分发功能都不要带它。

### 5.4 维护性风险
- `pitch_detector_dart`/`pitchupdart`（2024-04 后未发版）与 `soundpool`（2023-08 后未发版）都已趋停——前者纯 Dart 可随时内联自持，后者应直接用 flutter_soloud 替代。
- `chord_pro`、`soundfont_kit`、`guitar_chord_library`、`flutter_guitar_chord` 都是新包（likes ≤15），功能描述与 API 需要实际跑 demo 验证后再定依赖。

---

## 6. 主要来源

- GitHub API（star/许可/最近推送，2026-10-08 实查）：本文所有仓库链接本身
- pub.dev API（版本/发布日期/likes/points/许可标签，2026-10-08 实查）：本文所有包链接本身
- ChordPro 官方规范与指令总览：<https://www.chordpro.org/chordpro/chordpro-directives/>（实查，含指令语义与 `{name: arg}` / HTML 风格属性两种参数语法说明）；参考实现 <https://github.com/ChordPro/chordpro>（529★，Artistic-2.0）
- ChordMark 文档：<https://chordmark.netlify.app/docs/getting-started>（入口实查于仓库 README）
- Cifra Club 实测页面：<https://www.cifraclub.com.br/embrace/gravity/>（成功抓取 1 次，后遭 Akamai 403）
- flutter_soloud 能力（playClocked/render-ahead/loadMem）：其 README 与 CHANGELOG（<https://github.com/alnitak/flutter_soloud>，实查）
- metronome 实现方式：其 Android 源码 Metronome.java（AudioTrack MODE_STREAM，实查）
- freesound CC0 计数：<https://freesound.org/search/?q=ukulele+strum&f=license:%22Creative+Commons+0%22>（搜索页实查：95 sounds）
