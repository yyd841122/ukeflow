# UkeFlow v1 架构与里程碑

依据：GLOSSARY.md（术语）、docs/adr/0001~0006（已定决策）、docs/research/similar-projects.md（轮子调研）、spikes/tech_validation（已验证）。

## 技术栈（spike 验证后锁定）

| 层 | 选择 | 理由 |
|---|---|---|
| 框架 | Flutter 3.44 / Dart 3.12 | ADR-0001 |
| 状态管理 | Riverpod | 可测试、编译期安全、社区主流 |
| 存储 | drift (SQLite) | 活跃度最高的响应式本地库；打卡/设置/自建曲库 |
| 音频引擎 | flutter_soloud | ADR-0005；唯一时钟 getEngineTime() |
| 麦克风采集 | record | ADR-0005 |
| 音高检测 | pitch_detector_dart (YIN) | ADR-0005 |
| 谱面解析 | chord_pro + 自建校验层 | ADR-0006 |
| 和弦指法图 | 自绘 CustomPainter | 指弹四线谱反正是自绘，统一技术；数据用 chords-db ukulele.json (MIT) |
| 图片谱查看 | photo_view | 无争议 |

## 模块划分

```
lib/
├── core/
│   ├── audio/        # SoloudEngine 封装(init/playClocked/loadMem)、TickSynth(WAV合成)、
│   │                 # KarplusStrong(拨弦→PCM→loadMem)、Scheduler(节拍/跟练共用时钟)
│   ├── model/        # StrumChart(ChordPro→Section/Line/Tokens)、TabChart(逐音事件:弦/品位/时刻)、
│   │                 # Chord、PracticePath/DailyTask/CheckIn、StrumPattern(节奏型)
│   ├── chart/        # ChordPro 校验器(段落闭合/和弦名白名单)、谱库仓库、
│   │                 # builtin_tab_charts(内置指弹曲 Dart 常量目录+校验,ADR-0003 v1 无解析导入)
│   ├── practice/     # 练习内核(纯函数,零引擎依赖):play_timeline.dart 时间轴编译(谱+节奏型+BPM+变速→动作事件时间轴)、
│   │                 # practice_state.dart 跟练练习状态((时间轴,引擎时刻)→当前拍/动作/预告/歌词行)、
│   │                 # rhythm_state.dart 节奏型训练状态(循环网格先行版)、
│   │                 # tab_timeline.dart 指弹谱→逐音事件时间轴(工单 12,取整语义与弹唱时间轴同型、类型独立)、
│   │                 # tab_practice_state.dart 逐音练习状态((时间轴,引擎时刻)→当前音/预亮窗/拍,工单 13)
│   ├── ui/           # 共享基础组件（PlaceholderPage 占位页等）
│   └── theme.dart    # 统一主题（琥珀木色 Material 3）
├── data/             # drift 表：checkins、charts(自建)、settings；assets/：内置谱、chords-db、采样
├── features/
│   ├── tuner/        # 调音器（spike A 代码升级迁入）
│   ├── chords/       # 和弦库：指法图+按法要点+示范音
│   ├── rhythm/       # 节奏型训练器：节拍器+↓↑箭头可视化慢练
│   ├── play/         # 跟练引擎（核心）：同步视图+俄罗斯方块预告+扫弦箭头/四线谱高亮
│   ├── demo/         # 示范试听：弹唱谱按节奏型扫弦、指弹谱逐音
│   ├── path/         # 30 天练习路径+打卡
│   └── library/      # 曲库列表+导入(粘贴文本/链接/Cifra Club WebView)+图片谱查看
└── import/           # CifraClubParser(WebView DOM)、PasteParser(粘贴文本→ChordPro)
```

## 同步引擎设计（产品核心，ADR-0005 约束）

- **唯一时钟** = `SoLoud.instance.getEngineTime()`。禁止挂钟参与任何音画对齐。
- 跟练视图是纯函数：`(engineTime) → UI 状态`（当前拍、下一动作、高亮、歌词行）。
  UI 以 ~16ms 轮询重绘（spike B 已验证此模式漂移可忽略）。
- 曲谱预编译为**动作事件时间轴**（core/practice/play_timeline.dart）：
  sealed PlayEvent（PlayStrumEvent 扫弦[方向+和弦] / PlayLyricEvent 歌词行 /
  PlaySectionEvent 段落），时刻为**相对量**（自 0），锚定 t0 由消费方决定；
  指弹谱的单音事件（note 弦+品位）归指弹逐音事件时间轴
  （core/practice/tab_timeline.dart，工单 12；与弹唱时间轴取整语义同型、
  sealed 事件族互不统属——ADR-0003 的模型分界在时间轴层同样成立），
  弹唱谱时间轴
  只含扫弦/歌词行/段落。事件时刻逐事件四舍五入不累加，与 BeatSchedule.beatTime
  同语义——拍点扫弦与节拍声同源同刻（工单 08 测试守护）。
  当前动作 = 二分查找 now；俄罗斯方块预告 = 取 (now, now+lookahead] 窗口
  （core/practice/practice_state.dart）。
- 一切发声（节拍 tick、扫弦采样错峰、KS 拨弦、逐音示范）都走 `playClocked` 预定，
  与视觉事件出自**同一份时间轴**——音画同步是结构保证，不是校准出来的。

## 里程碑（中值 ~7.5 周，目标区间 6~10 周）

| 里程碑 | 内容 | 预算 |
|---|---|---|
| **M1 地基** | 正式工程、Riverpod+drift 骨架、导航/主题、和弦库页（数据+指法图+试听） | ~1.5 周 |
| **M2 音频核心** | SoloudEngine/TickSynth、节拍器+节奏型训练器、Karplus-Strong 拨弦、和弦示范音 | ~1.5 周 |
| **M3 跟练引擎** | 弹唱谱跟练（时间轴+预告+箭头+歌词滚动）、示范试听、指弹谱模型+四线谱+跟练、内置 5 首目标曲 | ~2 周 |
| **M4 路径与曲库** | 30 天路径+打卡、备份导入导出、粘贴导入、Cifra Club WebView、图片谱查看器 | ~1.5 周 |
| **M5 打磨收尾** | 调音器手感（阻尼/表针）、设置页、真机长测、稳定性 | ~1 周 |

每里程碑结束：真机可用 + 可演示。M3 是"做出好产品"的主战场，优先级最高、预算可上浮。
