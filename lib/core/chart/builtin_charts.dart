import 'strum_chart_parser.dart';

/// 内置曲库（GLOSSARY「内置曲库」）的一条曲目。
class BuiltInChart {
  const BuiltInChart({required this.id, required this.chart});

  /// 曲目 id = 资产文件名去扩展名（如 `cang-hai-yi-sheng-xiao`）。
  final String id;
  final StrumChart chart;
}

/// 内置曲库清单：id 与资产路径一一对应。新增目标曲在此登记。
const builtinChartCatalog = <({String id, String asset})>[
  (
    id: 'ai-ni-bu-shi-liang-san-tian',
    asset: 'assets/charts/ai-ni-bu-shi-liang-san-tian.pro',
  ),
  (id: 'cang-hai-yi-sheng-xiao', asset: 'assets/charts/cang-hai-yi-sheng-xiao.pro'),
  (id: 'big-big-world', asset: 'assets/charts/big-big-world.pro'),
  (
    id: 'love-you-more-than-i-can-say',
    asset: 'assets/charts/love-you-more-than-i-can-say.pro',
  ),
  (id: 'yesterday-once-more', asset: 'assets/charts/yesterday-once-more.pro'),
];

/// 内置曲库加载：逐份解析+校验，任何坏谱当场抛错（内置内容必须完美，
/// 与和弦库 ChordDataError 同一哲学——坏内容是缺陷，不带病进入曲库页）。
class BuiltInCharts {
  BuiltInCharts._();

  /// [readAsset] 注入资产读取（生产传 rootBundle.loadString，测试传内存字符串）。
  static Future<List<BuiltInChart>> load({
    required Future<String> Function(String asset) readAsset,
    required Set<String> allowedChords,
  }) async {
    final charts = <BuiltInChart>[];
    for (final entry in builtinChartCatalog) {
      final result = StrumChartParser.parse(
        await readAsset(entry.asset),
        allowedChords: allowedChords,
      );
      if (!result.ok) {
        throw StateError(
          '内置谱 ${entry.asset} 未过校验，'
          '内置内容不允许带病入库：\n'
          '${result.issues.map((i) => i.message).join('\n')}',
        );
      }
      charts.add(BuiltInChart(id: entry.id, chart: result.chart!));
    }
    return List.unmodifiable(charts);
  }
}
