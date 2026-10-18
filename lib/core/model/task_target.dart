/// 每日任务的直达目标(工单 22,GLOSSARY「每日任务」的练什么落点):
/// 学/练文案点名、可一键直达的 App 内对象。三类(工单 22 验收):
/// 和弦→和弦详情、节奏型→节奏型训练器、曲目→跟练页。
///
/// 纪律:builtin_learning_path 的守护测试锁住「目标标签逐字出现在
/// 当天文案里」「id 真实存在」——链与文脱节、坏 id 都当场拦下。
library;

import 'chord.dart';
import 'strum_chart.dart';
import 'strum_pattern.dart';

/// 一个直达目标。
sealed class TaskTarget {
  const TaskTarget();

  /// 目标 chip 显示文字;守护测试锁它逐字出现在当天学/练文案里。
  String get label;
}

/// 和弦目标:直达和弦库详情页。
class ChordTarget extends TaskTarget {
  const ChordTarget(this.chordLabel);

  /// 和弦名(Chord.label,如 C、Am、G7)。
  final String chordLabel;

  @override
  String get label => chordLabel;
}

/// 节奏型目标:直达节奏型训练器,带型预选。
class PatternTarget extends TaskTarget {
  const PatternTarget(this.patternId, {required this.label});

  /// 内置节奏型 id(builtinStrumPatterns)。
  final String patternId;

  @override
  final String label;
}

/// 曲目目标:直达跟练页,带谱上下文。
class SongTarget extends TaskTarget {
  const SongTarget(this.chartId, {required this.label});

  /// 内置曲库 id(builtinChartCatalog)。
  final String chartId;

  @override
  final String label;
}

/// 目标解析结果(工单 22 验收「目标页缺失时优雅降级为文字提示」):
/// resolved 三态带上下文对象供页面直达,missing 由页面降级为提示。
sealed class TaskTargetResolution {
  const TaskTargetResolution();
}

class ChordTargetResolved extends TaskTargetResolution {
  const ChordTargetResolved(this.chord);

  final Chord chord;
}

class PatternTargetResolved extends TaskTargetResolution {
  const PatternTargetResolved(this.pattern);

  final StrumPattern pattern;
}

class SongTargetResolved extends TaskTargetResolution {
  const SongTargetResolved(this.chart);

  final StrumChart chart;
}

/// 目标缺失:和弦库/曲库/内置表里查不到(数据漂移或加载未就绪)。
class TargetMissing extends TaskTargetResolution {
  const TargetMissing();
}

/// 按三张查找表解析一个目标。纯函数:页面喂 provider 数据,解析与
/// 降级判定在此处可单测(工单 22 缝 1)。
TaskTargetResolution resolveTaskTarget(
  TaskTarget target, {
  required Map<String, Chord> chordsByLabel,
  required Map<String, StrumPattern> patternsById,
  required Map<String, StrumChart> chartsById,
}) => switch (target) {
  ChordTarget(:final chordLabel) => switch (chordsByLabel[chordLabel]) {
    null => const TargetMissing(),
    final chord => ChordTargetResolved(chord),
  },
  PatternTarget(:final patternId) => switch (patternsById[patternId]) {
    null => const TargetMissing(),
    final pattern => PatternTargetResolved(pattern),
  },
  SongTarget(:final chartId) => switch (chartsById[chartId]) {
    null => const TargetMissing(),
    final chart => SongTargetResolved(chart),
  },
};
