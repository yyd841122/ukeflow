import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';
import 'package:ukeflow/core/practice/play_timeline.dart';
import 'package:ukeflow/core/scoring/report.dart';
import 'package:ukeflow/core/scoring/strum_scorer.dart';

import '../../helpers/chart_fixtures.dart';

/// 报告组装(GLOSSARY「跟练评分」报告侧):判定结果 + 时间轴谱面信息 →
/// 扫弦点轨道/最差三处/行与小节聚合。纯函数。
void main() {
  // 测试谱 practiceFixtureChart:4 小节(2 段 × 2 行,每行 1 小节),
  // 全下扫型每小节 4 个扫弦点(槽 0/2/4/6 = 拍 0/1/2/3),共 16 点。
  // 小节 0=Am(段1行1)、1=C(段1行2)、2=C(段2行1)、3=Am(段2行2);
  // 扫弦点拍位 = 4(预备) + 小节×4 + 拍。
  // (parseChart 带 expect,须在测试体内求值,不能提为 main 局部量。)

  ScoringReport reportOf(List<double> onsetBeats, {ChordVerifier? verify}) {
    final timeline = compileTimeline(
      chart: practiceFixtureChart,
      pattern: builtinStrumPatterns.first,
      bpm: 80,
    );
    final result = scoreStrums(
      targets: [
        for (final s in timeline.strums)
          ScoringTarget(s.scheduleBeat(4), chord: s.chord),
      ],
      onsets: [for (final b in onsetBeats) ScoredOnset(b, 750)],
      verifyChord: verify,
    );
    return buildReport(timeline: timeline, result: result);
  }

  List<double> allOnTime() => [for (var i = 0; i < 16; i++) 4.0 + i];

  test('spots 与时间轴扫弦点同序同行:携带轨道序/小节/槽位/和弦/行号', () {
    final report = reportOf(allOnTime());
    expect(report.spots, hasLength(16));
    expect(report.spots.first.spotIndex, 0);
    expect(report.spots.first.barIndex, 0);
    expect(report.spots.first.slotInBar, 0);
    expect(report.spots.first.chord, 'Am');
    expect(report.spots.first.lineIndex, 0);
    expect(report.spots[4].barIndex, 1, reason: '第 5 点 = 小节 1 拍 1');
    expect(report.spots[4].chord, 'C');
    expect(report.spots[4].lineIndex, 1);
    expect(report.spots[8].sectionIndex, 1, reason: '第二段');
    expect(report.spots[8].lineIndex, 0, reason: '段内行号归零(段2行1)');
    expect(report.spots.last.barIndex, 3);
    expect(
      report.spots.map((s) => s.judgment),
      everyElement(StrumJudgment.onTime),
    );
  });

  test('最差三处:漏 > 错 > 物理误差降序;同判定并列保持谱序', () {
    final onsets = allOnTime();
    onsets[0] = -99; // 点 0:漏
    onsets[7] = 4.0 + 7 + 0.16; // 点 7:偏晚 0.16 拍 = 120ms
    final report = reportOf(
      onsets,
      verify: (i, _) => i != 3, // 点 3:时机准但和弦错
    );
    final worst = worstSpots(report, count: 3);
    expect(worst.map((s) => s.spotIndex).toList(), [
      0,
      3,
      7,
    ], reason: '漏(0) > 错(3) > 晚 120ms(7)');
    expect(worst[2].errorSec, closeTo(0.12, 1e-9));
  });

  test('最差三处:数量不足时给实有数;全准时为空', () {
    expect(
      worstSpots(reportOf(allOnTime()), count: 3),
      isEmpty,
      reason: '全准无可举 worst',
    );
    final onsets = allOnTime();
    onsets[2] = 4.0 + 2 - 0.07; // 一处偏早 70ms
    final worst = worstSpots(reportOf(onsets), count: 3);
    expect(worst, hasLength(1));
    expect(worst.single.spotIndex, 2);
  });

  test('小节聚合:每小节 matched/total', () {
    final onsets = allOnTime();
    onsets[0] = -99; // 小节 0 漏 1
    onsets[5] = -99; // 小节 1 漏 1
    onsets[8] = -99; // 小节 2 漏 1
    final report = reportOf(onsets);
    final byBar = accuracyByBar(report);
    expect(byBar, hasLength(4));
    expect(byBar[0].bar, 0);
    expect(byBar[0].matched, 3);
    expect(byBar[0].total, 4);
    expect(byBar[1].matched, 3);
    expect(byBar[2].matched, 3);
    expect(byBar[3].matched, 4);
  });

  test('行聚合:行号带所属段落,各行的命中/总数', () {
    final onsets = allOnTime();
    onsets[0] = -99; // 段1行1 漏 1
    onsets[8] = -99; // 段2行1 漏 1
    final report = reportOf(onsets);
    final byLine = accuracyByLine(report);
    expect(byLine, hasLength(4));
    expect(byLine[0].sectionIndex, 0);
    expect(byLine[0].lineIndex, 0);
    expect(byLine[0].matched, 3);
    expect(byLine[0].total, 4);
    expect(byLine[1].matched, 4);
    expect(byLine[2].sectionIndex, 1);
    expect(byLine[2].matched, 3);
    expect(byLine[3].matched, 4);
  });
}
