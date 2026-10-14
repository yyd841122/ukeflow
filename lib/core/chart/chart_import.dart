import '../model/strum_chart.dart';

/// 导入校验报告（工单 16「导入完成后展示校验报告」）：一份过了校验的谱
/// 给用户过目的摘要——和弦清单（按谱面首现顺序去重）与段落结构。
/// 入库前的确认面板与入库后的成功页共用同一份报告。
class ChartImportReport {
  ChartImportReport.of(StrumChart chart)
    : chords = _chordsInFirstAppearanceOrder(chart),
      sections = [
        for (final section in chart.sections)
          ChartSectionSummary(
            title: section.label ?? _kindName(section.kind),
            lineCount: section.lines.length,
          ),
      ];

  /// 谱内全部和弦名，首现顺序去重（弹唱谱已过白名单，名即可查指法）。
  final List<String> chords;

  /// 段落结构，按谱面顺序。空行不产出段落也不计入行数（解析层语义）。
  final List<ChartSectionSummary> sections;

  static List<String> _chordsInFirstAppearanceOrder(StrumChart chart) {
    final seen = <String>{};
    return [
      for (final section in chart.sections)
        for (final line in section.lines)
          for (final chord in line.chords)
            if (seen.add(chord.name)) chord.name,
    ];
  }
}

/// 报告里的一个段落：标题（段落标签优先，缺省类型名）+ 行数。
class ChartSectionSummary {
  const ChartSectionSummary({required this.title, required this.lineCount});

  final String title;
  final int lineCount;
}

/// 两行式谱防线（工单 16 机检补，App 内直转归工单 26）：解析通过但全谱
/// 零和弦——网上最常见的「和弦悬在歌词上方」两行式排版直接粘贴就是
/// 这个解析结果（和弦行变歌词行），新手拿到的是能入库但不能跟练的
/// 空谱且看不出错在哪。返回给用户的可读指引；有和弦则 null。
String? chordlessGuidance(StrumChart chart) =>
    chart.sections.any((s) => s.lines.any((l) => l.chords.isNotEmpty))
        ? null
        : '谱里没有认出任何和弦记号。网上最常见的「和弦悬在歌词上方」'
            '两行式谱,直接粘贴认不出来——请先转换成 [C]歌词 行内格式再粘'
            '（转换工具或把和弦挪进歌词行,如 [Em]They told him...）';

String _kindName(StrumSectionKind kind) => switch (kind) {
  StrumSectionKind.verse => '主歌',
  StrumSectionKind.chorus => '副歌',
  StrumSectionKind.bridge => '桥段',
  StrumSectionKind.loose => '自由段',
  StrumSectionKind.other => '其他',
};
