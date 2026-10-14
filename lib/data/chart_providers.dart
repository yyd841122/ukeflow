import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/chart/builtin_charts.dart';
import '../core/chart/builtin_tab_charts.dart';
import '../core/chart/custom_charts.dart';
import '../core/model/strum_chart.dart';
import 'chord_library.dart';
import 'providers.dart';

export '../core/chart/builtin_charts.dart'
    show BuiltInChart, builtinChartCatalog;
export '../core/chart/builtin_tab_charts.dart'
    show BuiltInTabChart, builtinTabChartCatalog;

/// 曲库里的自建弹唱谱条目(工单 15):id = 数据库自增主键(卡片 key 用),
/// title = 入库命名(展示名以它为准),chart = 源文本读出解析产物。
typedef CustomStrumChart = ({int id, String title, StrumChart chart});

/// 曲库内容(工单 15):弹唱谱 = 内置 + 自建(尾随),指弹谱 = 内置。
/// 图片谱归工单 18,届时并入此类型。
typedef LibraryContent = ({
  List<BuiltInChart> builtinStrum,
  List<CustomStrumChart> customStrum,
  List<BuiltInTabChart> tab,
});

/// 内置曲库（GLOSSARY「内置曲库」）：5 首目标曲，随 App 交付、开箱即练。
/// 白名单来自和弦库数据；任何内置谱坏损当场抛错（缺陷可见，不静默缺曲目）。
final builtinChartsProvider = FutureProvider<List<BuiltInChart>>((ref) async {
  final library = await ref.watch(chordLibraryProvider.future);
  return BuiltInCharts.load(
    readAsset: rootBundle.loadString,
    allowedChords: library.labels,
  );
});

/// 内置指弹曲（ADR-0003：v1 指弹仅限内置手工录入，Dart 常量直接入库）：
/// 加载期逐份校验，坏谱当场抛错。数据非异步，仍走 FutureProvider——
/// 曲库页对两类曲目用同一套 AsyncValue 错误呈现。
final builtinTabChartsProvider = FutureProvider<List<BuiltInTabChart>>((
  ref,
) async {
  return loadBuiltinTabCharts();
});

/// 自建弹唱谱流(GLOSSARY「自建谱」):数据库行读出即时解析,
/// 导入/录入写入即推送。坏谱抛错——与内置谱同一哲学,缺陷可见,
/// 不静默缺曲目(解析层的报错带曲名,见 core/chart/custom_charts.dart)。
final customStrumChartsProvider = StreamProvider<List<CustomStrumChart>>((
  ref,
) async* {
  final library = await ref.watch(chordLibraryProvider.future);
  // 数据库行读出即时解析;坏谱在 map 内抛错,作为流错误传给曲库页。
  yield* ref.watch(customChartsDaoProvider).watchAll().map(
    (rows) => [
      for (final row in rows)
        (
          id: row.id,
          title: row.title,
          chart: parseCustomChart(
            source: row.source,
            title: row.title,
            allowedChords: library.labels,
          ),
        ),
    ],
  );
});

/// 曲库数据源(工单 15):三类曲目合流为一处 AsyncValue,曲库页
/// 统一呈现加载/错误/数据。自建谱走流,导入后本 provider 自动重建,
/// 新谱即出现在列表(「同一列表」验收的数据面)。
final libraryProvider = FutureProvider<LibraryContent>((ref) async {
  final builtinStrum = await ref.watch(builtinChartsProvider.future);
  final customStrum = await ref.watch(customStrumChartsProvider.future);
  final tab = await ref.watch(builtinTabChartsProvider.future);
  return (builtinStrum: builtinStrum, customStrum: customStrum, tab: tab);
});
