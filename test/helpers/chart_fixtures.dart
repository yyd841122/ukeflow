import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/strum_chart_parser.dart';
import 'package:ukeflow/data/chart_providers.dart';

/// 练习内核测试（工单 08）共用：谱文本 → 弹唱谱，
/// 走与产品相同的解析+校验入口。
const testAllowedChords = {'C', 'G', 'Am', 'F', 'Em', 'Dm'};

StrumChart parseChart(String source) {
  final result =
      StrumChartParser.parse(source, allowedChords: testAllowedChords);
  expect(result.ok, isTrue, reason: '测试谱必须过校验：${result.issues}');
  return result.chart!;
}

/// 跟练（工单 09）测试用小谱：两段各两行，每行一个和弦记号占一小节
/// （4 小节 = 16 拍；80 BPM 下一行 3 秒、全曲 12 秒）。
/// 和弦取 testAllowedChords 与 ui_fixture.json 库面标签的交集（Am/C）。
const practiceFixtureChartText = '''
{title: 测试曲}
{artist: 测试者}
{key: C}
{tempo: 80}

{start_of_verse: 主歌}
[Am]第一行歌词
[C]第二行歌词
{end_of_verse}

{start_of_chorus: 副歌}
[C]第三行歌词
[Am]第四行歌词
{end_of_chorus}
''';

/// 每次取用现解析（parseChart 里有 expect，须在测试内求值）。
StrumChart get practiceFixtureChart => parseChart(practiceFixtureChartText);

/// 跟练页签（工单 09）UI 测试：内置曲库 provider 覆盖为给定测试谱，
/// 不碰真资产（testWidgets 的 FakeAsync 里 rootBundle 真实文件 I/O 永远
/// 完不了）。求值发生在 provider 首次被读时（测试 zone 内，expect 合法）。
// ignore: strict_top_level_inference
builtinChartsFixtureOverride(List<({String id, StrumChart chart})> charts) =>
    builtinChartsProvider.overrideWith((ref) async => [
          for (final entry in charts) BuiltInChart(id: entry.id, chart: entry.chart),
        ]);
