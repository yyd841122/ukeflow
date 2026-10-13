import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/chart/builtin_charts.dart';
import '../core/chart/builtin_tab_charts.dart';
import 'chord_library.dart';

export '../core/chart/builtin_charts.dart'
    show BuiltInChart, builtinChartCatalog;
export '../core/chart/builtin_tab_charts.dart'
    show BuiltInTabChart, builtinTabChartCatalog;

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
