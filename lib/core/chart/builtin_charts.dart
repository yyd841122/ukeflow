import 'strum_chart_parser.dart';

/// 内置曲库（GLOSSARY「内置曲库」）的一条曲目。
class BuiltInChart {
  const BuiltInChart({required this.id, required this.chart});

  /// 曲目 id = 资产文件名去扩展名（如 `cang-hai-yi-sheng-xiao-strum`）。
  final String id;
  final StrumChart chart;
}

/// 内置曲库清单：id 与资产路径一一对应。新增目标曲在此登记。
const builtinChartCatalog = <({String id, String asset})>[
  (
    id: 'ai-ni-bu-shi-liang-san-tian-strum',
    asset: 'assets/charts/ai-ni-bu-shi-liang-san-tian-strum.pro',
  ),
  (id: 'cang-hai-yi-sheng-xiao-strum', asset: 'assets/charts/cang-hai-yi-sheng-xiao-strum.pro'),
  (id: 'big-big-world-strum', asset: 'assets/charts/big-big-world-strum.pro'),
  (
    id: 'love-you-more-than-i-can-say-strum',
    asset: 'assets/charts/love-you-more-than-i-can-say-strum.pro',
  ),
  (id: 'yesterday-once-more', asset: 'assets/charts/yesterday-once-more.pro'),

  // ── 旧项目迁移谱(2026-10-18,自 ukulele-demo / ukulele-glm 转录)──
  // demo 三首(段落结构齐全):送别 / 友谊地久天长 / 茉莉花;
  // glm 十六首(自由段,歌词+和弦位转录):
  // 小星星 生日快乐 两只老虎 欢乐颂 粉刷匠 春天来了 铃儿响叮当
  // Oh Susanna 摇篮曲 童年 隐形的翅膀 You Are My Sunshine
  // London Bridge Row Row Row 新年好 康康舞曲。
  // 与内置指弹曲同曲不同谱的 id 加 -strum 后缀区分(xiao-xing-xing-strum 等)。
  (id: 'song-bie', asset: 'assets/charts/song-bie.pro'),
  (
    id: 'you-yi-di-jiu-tian-chang',
    asset: 'assets/charts/you-yi-di-jiu-tian-chang.pro',
  ),
  (id: 'mo-li-hua', asset: 'assets/charts/mo-li-hua.pro'),
  (id: 'xiao-xing-xing-strum', asset: 'assets/charts/xiao-xing-xing-strum.pro'),
  (id: 'sheng-ri-kuai-le', asset: 'assets/charts/sheng-ri-kuai-le.pro'),
  (id: 'liang-zhi-lao-hu', asset: 'assets/charts/liang-zhi-lao-hu.pro'),
  (id: 'huan-le-song-strum', asset: 'assets/charts/huan-le-song-strum.pro'),
  (id: 'fen-shua-jiang', asset: 'assets/charts/fen-shua-jiang.pro'),
  (id: 'chun-tian-lai-le', asset: 'assets/charts/chun-tian-lai-le.pro'),
  (
    id: 'ling-er-xiang-ding-dang',
    asset: 'assets/charts/ling-er-xiang-ding-dang.pro',
  ),
  (id: 'oh-susanna', asset: 'assets/charts/oh-susanna.pro'),
  (id: 'yao-lan-qu', asset: 'assets/charts/yao-lan-qu.pro'),
  (id: 'tong-nian', asset: 'assets/charts/tong-nian.pro'),
  (id: 'yin-xing-de-chi-bang', asset: 'assets/charts/yin-xing-de-chi-bang.pro'),
  (
    id: 'you-are-my-sunshine',
    asset: 'assets/charts/you-are-my-sunshine.pro',
  ),
  (id: 'london-bridge', asset: 'assets/charts/london-bridge.pro'),
  (id: 'row-row-row', asset: 'assets/charts/row-row-row.pro'),
  (id: 'xin-nian-hao', asset: 'assets/charts/xin-nian-hao.pro'),
  (id: 'kang-kang-wu-qu', asset: 'assets/charts/kang-kang-wu-qu.pro'),
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
