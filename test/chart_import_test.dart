import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/chart_import.dart';
import 'package:ukeflow/core/chart/strum_chart_parser.dart';

import 'helpers/chart_fixtures.dart';

/// 工单 16 导入管线缝：粘贴文本 → 校验后的谱 → 校验报告。
/// 报告是「导入完成后展示校验报告」（和弦清单、段落结构）的数据面：
/// 和弦按谱面首现顺序去重；段落按谱面顺序，标题取段落标签、
/// 缺省用类型名（主歌/副歌/桥段/自由段/其他）。
void main() {
  // 与 test/fixtures/chords/ui_fixture.json 库面标签一致。
  const fixtureChords = {'Am', 'A7', 'C', 'G7', 'Bm'};

  ChartParseResult parse(String source) =>
      StrumChartParser.parse(source, allowedChords: fixtureChords);

  group('散行真实网上谱（无段落指令）', () {
    const source = importFixtureSource;

    test('校验放行，和弦清单首现去重：C、G7、Am、Bm', () {
      final result = parse(source);

      expect(result.ok, isTrue);
      final report = ChartImportReport.of(result.chart!);
      expect(report.chords, ['C', 'G7', 'Am', 'Bm']);
    });

    test('空行不切段：整谱一个自由段', () {
      final result = parse(source);

      final report = ChartImportReport.of(result.chart!);
      expect(report.sections, hasLength(1));
      expect(report.sections[0].title, '自由段');
      expect(report.sections[0].lineCount, 4);
    });
  });

  group('带段落指令的谱', () {
    const source = '''
{title: 规范谱}
{start_of_verse: Verse 1}
[C]第一行
[G7]第二行
{end_of_verse}

{start_of_chorus}
[Am]副歌一行
[Bm]副歌两行
{end_of_chorus}
''';

    test('段落按谱面顺序，类型名+行数；自定义标签优先于类型名', () {
      final result = parse(source);

      expect(result.ok, isTrue);
      final report = ChartImportReport.of(result.chart!);
      expect(report.sections, hasLength(2));
      expect(report.sections[0].title, 'Verse 1', reason: '段落标签优先');
      expect(report.sections[0].lineCount, 2);
      expect(report.sections[1].title, '副歌');
      expect(report.sections[1].lineCount, 2);
    });

    test('和弦清单跨段去重，首现顺序', () {
      final result = parse(source);

      final report = ChartImportReport.of(result.chart!);
      expect(report.chords, ['C', 'G7', 'Am', 'Bm']);
    });
  });
}
