import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';
import 'package:ukeflow/core/practice/play_timeline.dart';
import 'package:ukeflow/core/scoring/report.dart';
import 'package:ukeflow/core/scoring/strum_scorer.dart';
import 'package:ukeflow/features/play/scoring/practice_scoring_controller.dart';
import 'package:ukeflow/features/play/scoring/scoring_report_page.dart';

import 'helpers/chart_fixtures.dart';

/// 评分报告页(工单55):头部「合格/覆盖」两数拆分 + 小节卡片按合格率
/// 着色——全红小节不该是满格棕。报告经假控制器注入,页内无计算状态。

/// 注入的报告(用例先赋值再 pump;页只读它)。
ScoringReport _pumpedReport = _emptyReport();

ScoringReport _emptyReport() {
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
    onsets: const [],
  );
  return buildReport(timeline: timeline, result: result);
}

/// 假控制器:直接吐已完成的报告,不走会话生命周期。
class _FixedReportController extends PracticeScoringController {
  @override
  PracticeScoringState build() =>
      PracticeScoringState(status: ScoringStatus.finished, report: _pumpedReport);
}

void main() {
  // 测试谱 practiceFixtureChart:4 小节 × 4 点。小节 1(点 4-5)错 2、
  // 小节 2(点 8-10)错 3,其余全准——三档合格率各一小节。
  ScoringReport reportOf() {
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
      onsets: [for (var i = 0; i < 16; i++) ScoredOnset(4.0 + i, 750)],
      // verifyChord:true = 和弦对(与生产 verifyChord 语义同)。
      verifyChord: (i, _) => !(i >= 4 && i <= 5) && !(i >= 8 && i <= 10),
    );
    return buildReport(timeline: timeline, result: result);
  }

  Future<void> pump(WidgetTester tester) async {
    _pumpedReport = reportOf();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [practiceScoringProvider.overrideWith(_FixedReportController.new)],
        child: const MaterialApp(home: ScoringReportPage()),
      ),
    );
    await tester.pump();
  }

  Color chipDot(WidgetTester tester, String label) =>
      (tester.widget<Chip>(find.widgetWithText(Chip, label)).avatar! as Icon)
          .color!;

  testWidgets('头部:大数字 = 合格率,覆盖在副行(错不计入合格)', (tester) async {
    await pump(tester); // 16 点:错 5 → 合格 11/16=69%,覆盖 16/16
    expect(find.text('69%'), findsOneWidget);
    expect(
      find.textContaining('覆盖 100%'),
      findsOneWidget,
      reason: '覆盖含「错」;大数字不再报这个数',
    );
  });

  testWidgets('小节卡片:底色与数字按合格率(全红小节不再满格棕)', (tester) async {
    await pump(tester);
    final scheme = Theme.of(
      tester.element(find.byType(ScoringReportPage)),
    ).colorScheme;
    // 三档:4/4 → primary;2/4(=0.5)→ tertiary;1/4 → error。
    expect(chipDot(tester, '1:4/4'), scheme.primary);
    expect(chipDot(tester, '2:2/4'), scheme.tertiary);
    expect(chipDot(tester, '3:1/4'), scheme.error);
  });
}
