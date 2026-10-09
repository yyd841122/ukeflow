# 内置曲谱（文本谱，ChordPro）

工单 07 录入的 5 首目标曲。格式 = ChordPro（chord_pro 0.8.0 解析）：
`[和弦]` 紧贴歌词、`{start_of_verse: 段落名}` 圈段落、头部 `{title}/{artist}/{key}/{tempo}`。

## 歌词待录

当前每行歌词是占位符 `♪`（歌词文本有版权，需由维护者自行录入）。
替换方法：把每行的 `♪` 换成正式歌词即可——**和弦记号与其在行内的位置保持不动**，
行数不足/多余可直接增删整行。改完跑 `tool/check.sh full`，
`builtin_charts_asset_test` 会重新解析+校验全部资产，改坏会当场报错并给出行列。

## 约定

- 调性统一 C 调新手编配；速度与和弦为录入时的合理起点，**以对照原曲核对为准**。
- 和弦名必须是 `assets/chords/ukulele.json` 里的显示名（如 `C`、`Am7`、`Fmaj7`），
  校验白名单即来源于此；v1 不用斜杠和弦（如 `G/B`）。
- 段落用 `{start_of_verse: 主歌一}` / `{start_of_chorus: 副歌}` / `{start_of_bridge: 桥段}`，
  重复的段落直接重写内容（不用 `{chorus}` 复述指令），时间轴编译按谱面顺序走。
