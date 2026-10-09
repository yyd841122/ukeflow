/// Spike C 迁入的三份样例曲谱（自 spikes/tech_validation/lib/sample_charts.dart
/// 原样迁移，内容不改——迁入时是什么样，回归就守什么样）。
/// 1. cleanChart：规范英文谱，含元数据与段落指令
/// 2. chineseChart：中文"和弦紧贴汉字"谱（UkeFlow 的主要真实场景）
/// 3. stressChart：tab 块、未知指令、注释、乱间距 —— 只求不崩、诊断合理
const String cleanChart = '''
{title: Big Big World}
{artist: Emilia}
{key: C}
{tempo: 88}

{start_of_verse}
[C]I'm a big big girl [Am]in a big big world
[Em]It's not a big big thing if you [F]leave me
[Dm]But I do do feel that [G]I do do will miss you much
[C]Miss you much
{end_of_verse}

{start_of_chorus}
[Am]Big big world
[C]Big big world
{end_of_chorus}
''';

const String chineseChart = '''
{title: 爱你不是两三天}
{artist: 梁静茹}
{key: C}

{start_of_verse}
[Am]爱你不是两三天
[Em]每天却想你很多遍
[F]还不[Em]习惯
[Am]你离开的[Em]每一天
{end_of_verse}

{c: 副歌重复两遍}

{start_of_chorus}
[F]爱你不是两三天
[G]一而再再而三
[Am]爱你的心不会变
{end_of_chorus}
''';

const String stressChart = '''
{title: Stress Test}
{artist: ???}
{transpose: 2}
{x_unknown_directive: hello}
# 这是注释行
{soc}
  [C]   weird    [G7]spacing [C#m7b5]here
[G7]沧海[A7]一声[C]笑
{eoc}

{start_of_tab}
e|--0--2--3--|
B|-----1-----|
{end_of_tab}

[H]invalid chord [Am7/G]slash chord
''';

/// 压力谱追加段：永不开闭合的段落，验证解析器的恢复与诊断机制
const String stressChartSuffix = '''
{soc}
[Am]永不开闭合的段落
''';
