/// 报告组装(GLOSSARY「跟练评分」报告侧):把评分判定接到时间轴谱面信息
/// 上,产出扫弦点轨道(逐格判定/误差/谱面位置)、最差三处与行/小节聚合。
/// 纯函数、零引擎依赖;报告本身看完即弃不落库,本模块只管算。
library;

import '../practice/play_timeline.dart';
import 'strum_scorer.dart';

/// 轨道上一格:一个谱面扫弦点 + 它的判定。按谱序排列(与传入 result 的
/// verdicts 同序),[spotIndex] 即轨道格序号(重听定位与 UI key 共用)。
class StrumSpot {
  const StrumSpot({
    required this.spotIndex,
    required this.barIndex,
    required this.slotInBar,
    required this.chord,
    required this.sectionIndex,
    required this.lineIndex,
    required this.judgment,
    required this.errorSec,
  });

  /// 轨道格序号(= 时间轴扫弦序,自 0)。
  final int spotIndex;

  /// 全曲小节序号与小节内八分槽位(谱面定位,报告详情显示用)。
  final int barIndex;
  final int slotInBar;

  /// 目标和弦名(null = 谱首无和弦,不判错)。
  final String? chord;

  /// 所属段落与行(聚合用)。
  final int sectionIndex;
  final int lineIndex;

  final StrumJudgment judgment;

  /// 时机误差秒(正晚负早;missed 无意义恒 0)。
  final double errorSec;
}

/// 一次评分的全曲报告。
class ScoringReport {
  const ScoringReport({required this.result, required this.spots});

  /// 判定统计(total/matched/五判定计数/平均误差,含 meanSignedError——
  /// 校准方向指南针)。
  final ScoreResult result;

  /// 扫弦点轨道,谱序。
  final List<StrumSpot> spots;
}

/// 判定结果 × 时间轴 → 报告。[result.verdicts] 须由 [timeline.strums]
/// 同序的 targets 算出(评分控制器的构造契约;长度不齐抛 ArgumentError)。
ScoringReport buildReport({
  required PlayTimeline timeline,
  required ScoreResult result,
}) {
  final strums = timeline.strums;
  if (result.verdicts.length != strums.length) {
    throw ArgumentError(
      'verdicts(${result.verdicts.length}) 与时间轴扫弦数(${strums.length})不一致',
    );
  }
  // 行归属:扫弦点属于「时刻 ≤ 它」的最后一个歌词行事件(时间轴已按
  // section→lyric→strum 同刻定序,二分走 events 不必另建索引——量级
  // 数百事件,线性推进一遍即可)。
  final spots = <StrumSpot>[];
  var eventCursor = 0;
  var sectionIndex = -1;
  var lineIndex = -1;
  var currentSection = -1;
  var currentLine = -1;
  for (var i = 0; i < strums.length; i++) {
    final strum = strums[i];
    while (eventCursor < timeline.events.length &&
        timeline.events[eventCursor].time <= strum.time) {
      final event = timeline.events[eventCursor];
      if (event is PlaySectionEvent) {
        sectionIndex = event.sectionIndex;
      } else if (event is PlayLyricEvent) {
        lineIndex = event.lineIndex;
      }
      eventCursor++;
    }
    // 同刻行事件已推进;行未开始(谱首无行)记 -1(聚合时归并)。
    currentSection = sectionIndex;
    currentLine = lineIndex;
    final verdict = result.verdicts[i];
    spots.add(
      StrumSpot(
        spotIndex: i,
        barIndex: strum.barIndex,
        slotInBar: strum.slotInBar,
        chord: strum.chord,
        sectionIndex: currentSection,
        lineIndex: currentLine,
        judgment: verdict.judgment,
        errorSec: verdict.errorSec,
      ),
    );
  }
  return ScoringReport(result: result, spots: spots);
}

/// 「差」的序:漏(没弹)> 错(弹错和弦)> 早/晚(按 |误差| 降序)。
int _severity(StrumSpot s) => switch (s.judgment) {
  StrumJudgment.missed => 0,
  StrumJudgment.wrong => 1,
  _ => 2,
};

/// 最差 [count] 处(报告「最差三处」)。全准返回空。
List<StrumSpot> worstSpots(ScoringReport report, {int count = 3}) {
  final candidates = report.spots
      .where((s) => s.judgment != StrumJudgment.onTime)
      .toList();
  candidates.sort((a, b) {
    final bySeverity = _severity(a).compareTo(_severity(b));
    if (bySeverity != 0) return bySeverity;
    final byError = b.errorSec.abs().compareTo(a.errorSec.abs());
    if (byError != 0) return byError;
    return a.spotIndex.compareTo(b.spotIndex); // 并列保谱序
  });
  return candidates.take(count).toList();
}

/// 小节聚合:每小节的命中/总数(谱序,无扫弦点的小节不出现)。
class BarAccuracy {
  const BarAccuracy({
    required this.bar,
    required this.matched,
    required this.total,
  });

  final int bar;
  final int matched;
  final int total;
}

List<BarAccuracy> accuracyByBar(ScoringReport report) {
  final order = <int>[];
  final byBar = <int, (int, int)>{};
  for (final spot in report.spots) {
    if (!byBar.containsKey(spot.barIndex)) order.add(spot.barIndex);
    final (matched, total) = byBar[spot.barIndex] ?? (0, 0);
    byBar[spot.barIndex] = (
      matched + (spot.judgment == StrumJudgment.missed ? 0 : 1),
      total + 1,
    );
  }
  return [
    for (final bar in order)
      BarAccuracy(bar: bar, matched: byBar[bar]!.$1, total: byBar[bar]!.$2),
  ];
}

/// 行聚合:每行的命中/总数(谱序;谱首无行事件的点归 (−1,−1) 行)。
class LineAccuracy {
  const LineAccuracy({
    required this.sectionIndex,
    required this.lineIndex,
    required this.matched,
    required this.total,
  });

  final int sectionIndex;
  final int lineIndex;
  final int matched;
  final int total;
}

List<LineAccuracy> accuracyByLine(ScoringReport report) {
  final order = <(int, int)>[];
  final byLine = <(int, int), (int, int)>{};
  for (final spot in report.spots) {
    final key = (spot.sectionIndex, spot.lineIndex);
    if (!byLine.containsKey(key)) order.add(key);
    final (matched, total) = byLine[key] ?? (0, 0);
    byLine[key] = (
      matched + (spot.judgment == StrumJudgment.missed ? 0 : 1),
      total + 1,
    );
  }
  return [
    for (final (si, li) in order)
      LineAccuracy(
        sectionIndex: si,
        lineIndex: li,
        matched: byLine[(si, li)]!.$1,
        total: byLine[(si, li)]!.$2,
      ),
  ];
}
