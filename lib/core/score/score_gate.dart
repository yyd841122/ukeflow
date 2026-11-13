/// 换歌体检(ADR-0012「逐首体检」)的结论模型。
///
/// 体检规则与转换器守门**同源**:两者跑同一趟 walk(reference_score.dart
/// 的采集式守门),这里只定义结论与展示结构——违例条目、三态判定、
/// 报告页要用的谱面概览。绝不在此另写一套判别规则。
library;

import 'reference_score.dart';

/// 违例类别 = 报告「谱面清点」的行(票08:拍号/调弦/反复/连音/效果记号
/// 逐项;另有变速/声部/结构三行)。
enum GateCategory {
  timeSignature('拍号'),
  tuning('调弦'),
  repeat('反复'),
  tuplet('连音/时值'),
  effect('效果记号'),
  miscMark('其他记号'),
  tempo('变速'),
  voices('声部'),
  structure('结构');

  const GateCategory(this.label);
  final String label;
}

/// 三态结论(票08):可练 / 缺规则待补 / 资料不够。
enum ScoreHealthVerdict {
  /// 零违例,守门放行,可直接进跟练。
  ready('可以练'),

  /// 资料完整可信,但含转换器明确拒绝的记号(反复/连音/效果等)——
  /// 补上规则后可重新体检,不是坏数据。
  needsRules('缺规则待补'),

  /// 资料本身无法可靠读取(格式坏/小节缺失/时值对不上),清点在
  /// 中止点之前的部分可信,整谱不可导入。
  insufficient('资料不够');

  const ScoreHealthVerdict(this.label);
  final String label;
}

/// 一条违例:[ruleId] 供测试锁定,[
/// category]/[measure] 供报告逐项展示,[message] 与转换器守门抛出的
/// 用户可读文本同源;[structural] 定三态(结构类 → 资料不够)。
class ScoreViolation {
  const ScoreViolation({
    required this.ruleId,
    required this.category,
    required this.message,
    this.measure,
    this.structural = false,
  });

  final String ruleId;
  final GateCategory category;

  /// 1 起小节号;结构级(进小节循环前)违例为 null。
  final int? measure;
  final String message;

  /// true = 结构类(资料本身坏 → 资料不够);false = 能力类(缺规则待补)。
  /// 与展示类别(category)正交:调弦坏是「调弦」行的结构类违例。
  final bool structural;
}

/// 体检报告:三态结论 + 违例明细 + 谱面概览(清点)。
class ScoreHealthReport {
  const ScoreHealthReport({
    required this.verdict,
    required this.violations,
    this.featureNotes = const [],
    this.title = '',
    this.artist = '',
    this.measureCount,
    this.eventCount,
    this.noteCount,
    this.durationSeconds,
    this.tuning1to4,
    this.capo,
    this.timeSignatures = const {},
    this.score,
  });

  final ScoreHealthVerdict verdict;

  /// 按 walk 顺序(小节序)排列,首条 = 转换器守门会抛的那条。
  final List<ScoreViolation> violations;
  final String title;
  final String artist;
  final int? measureCount;
  final int? eventCount;
  final int? noteCount;
  final double? durationSeconds;
  final List<int>? tuning1to4;
  final int? capo;

  /// 谱内出现过的拍号(如 {'4/4'})。
  final Set<String> timeSignatures;

  /// 支持记号的清点事实句(「扫弦/琶音 ×23」「第50小节起 80→82 BPM」)。
  final List<String> featureNotes;

  /// 仅 [ScoreHealthVerdict.ready] 时非空:同一趟 walk 的转换产物。
  final ReferenceScore? score;

  bool get ok => verdict == ScoreHealthVerdict.ready;

  /// 转换器守门抛的用户可读文本 = 首条违例消息(同源语义)。
  String get firstMessage =>
      violations.isEmpty ? '曲谱数据格式无效' : violations.first.message;

  /// 类别 → 条数(报告分组与结论副行用)。
  Map<GateCategory, int> get categoryCounts {
    final counts = <GateCategory, int>{};
    for (final v in violations) {
      counts[v.category] = (counts[v.category] ?? 0) + 1;
    }
    return counts;
  }
}
