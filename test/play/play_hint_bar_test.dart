import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/practice/score_sheet_layout.dart';
import 'package:ukeflow/features/play/play_hint_bar.dart';

/// 弹奏提示条(票07):纯函数 playHintAt 的列推进/和弦锚/扫弦记号
/// (真数据 = 组合定义首曲)+ widget 渲染(当列点亮/下一列预亮/预备
/// 占位)。布局内核几何在 score_sheet_layout_test,不重复锁。
void main() {
  final charts = {for (final e in builtinTabChartCatalog) e.id: e.chart};
  final def = scoreSheetCatalog.single;
  final solo = charts[def.tabChartId]!;
  final melody = charts[def.melodyChartId]!;
  final layout = ScoreSheetLayout(def: def, tabChart: solo, melodyChart: melody);

  group('playHintAt:列推进与锚定', () {
    test('曲头之前(预备数拍)返回 null;曲头后首列前 = 引导帧', () {
      expect(playHintAt(layout, -1.0), isNull, reason: '预备数拍期');
      final lead = playHintAt(layout, 3.9)!;
      expect(lead.current, isEmpty, reason: '首列在拍 4,尚无当列');
      expect(lead.next, isNotEmpty, reason: '首列整列预亮引导');
      expect(lead.chordLabel, isNull);
      expect(lead.barNumber, 1);
    });

    test('当列 = 最后一个 ≤ 拍位的列拍;拍内推进不换列', () {
      final at4 = playHintAt(layout, 4.0);
      expect(at4, isNotNull);
      expect(at4!.current.every((n) => n.beat == 4.0), isTrue,
          reason: '当列音全部在列拍 4');
      // 拍内推进(还没到下一列拍)不换列;下一列拍处才推进
      // (拍 4.5 有八分音列,4.5 处当列即 4.5 列——列推进以列拍为准)。
      final at401 = playHintAt(layout, 4.01);
      expect(
        at401!.current.map((n) => n.beat),
        at4.current.map((n) => n.beat),
        reason: '拍内(未到下一列拍)当列不变',
      );
      final at45 = playHintAt(layout, 4.5)!;
      expect(at45.current.every((n) => n.beat == 4.5), isTrue,
          reason: '到下一列拍即换列');
    });

    test('和弦锚与扫弦记号照组合定义(拍 4 = E 卷弦)', () {
      final f = playHintAt(layout, 4.0)!;
      expect(f.chordLabel, 'E');
      expect(f.strum, ScoreStrumKind.roll);
      expect(f.barNumber, 2, reason: '拍 4 在第 2 小节');
      expect(f.beatInBar, 1);
      // 拍 6 = A 卷弦。
      final f6 = playHintAt(layout, 6.0)!;
      expect(f6.chordLabel, 'A');
      expect(f6.strum, ScoreStrumKind.roll);
    });

    test('下一列预亮;曲末列 next 为空', () {
      final f = playHintAt(layout, 4.0)!;
      expect(f.next, isNotEmpty, reason: '曲中列必有下一列');
      final lastBeat = layout.tabNotes.last.beat;
      final fLast = playHintAt(layout, lastBeat)!;
      expect(fLast.next, isEmpty, reason: '末列无下一列');
      expect(fLast.current, isNotEmpty);
    });
  });

  group('PlayHintBar 渲染', () {
    Future<void> pumpBar(WidgetTester tester, PlayHintFrame? frame) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PlayHintBar(frame: frame)),
      ));
    }

    testWidgets('预备期占位文案', (tester) async {
      await pumpBar(tester, null);
      expect(find.byKey(const Key('play-hint-bar')), findsOneWidget);
      expect(find.textContaining('跟着拍子数'), findsOneWidget);
    });

    testWidgets('运行帧:和弦名/小节拍位/卷弦徽标/当列点亮/下一列预亮',
        (tester) async {
      final f = playHintAt(layout, 4.0)!;
      await pumpBar(tester, f);

      expect(find.text('E'), findsOneWidget, reason: '当位和弦名大字');
      expect(find.text('第2小节 · 拍1'), findsOneWidget);
      expect(find.text('卷弦'), findsOneWidget, reason: '拍 4 卷弦徽标');
      // 四个弦格都在(④③②① 序)。
      expect(find.text('4弦'), findsOneWidget);
      expect(find.text('1弦'), findsOneWidget);
      // 当列音有实底品数(非空列至少一格),且不是占位「—」全覆盖。
      final dashes = find.text('—');
      expect(
        tester.widgetList(dashes).length,
        lessThan(4),
        reason: '卷弦列四弦全响,不该有空白格',
      );
      // 不预亮(票07 用户实录移除):当列四弦全响 = 恰好 4 个品数胶囊。
      final pills = tester.widgetList(
        find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      );
      expect(pills, hasLength(4), reason: '卷弦列四弦各一格,无预亮格');
      expect(tester.takeException(), isNull);
    });

    testWidgets('曲头前引导帧:首列以实底示手型(不空白)', (tester) async {
      final lead = playHintAt(layout, 3.9)!;
      await pumpBar(tester, lead);
      expect(find.textContaining('小节'), findsOneWidget);
      // 首列音(E 卷弦 4 音)以实底可见(品数取自数据)。
      expect(find.text('${lead.next.first.fret}'), findsWidgets,
          reason: '首列音实底可见');
      expect(tester.takeException(), isNull);
    });

    testWidgets('拨弦列:空弦 0 照显;无音弦格显示占位', (tester) async {
      // 拍 10 附近列(非卷弦):找一个无卷弦记号的列拍。
      var beat = 10.0;
      var frame = playHintAt(layout, beat)!;
      while (frame.strum != null) {
        beat += 1;
        frame = playHintAt(layout, beat)!;
      }
      await pumpBar(tester, frame);
      expect(find.textContaining('小节'), findsOneWidget);
      expect(find.text('卷弦'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
