import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';
import 'package:ukeflow/core/practice/play_timeline.dart';
import 'package:ukeflow/core/practice/practice_state.dart';
import 'package:ukeflow/core/scoring/strum_scorer.dart';
import 'package:ukeflow/core/ui/judgment_colors.dart';
import 'package:ukeflow/features/chords/chord_diagram.dart';
import 'package:ukeflow/features/play/practice_view.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';

/// 跟练视图(纯渲染):接缝是构造参数——(时间轴, 练习状态, 节奏型, 和弦表)
/// → UI。零引擎:练习状态用 practiceStateAt 在固定锚点上合成。
void main() {
  final island = builtinStrumPatterns.last; // 下 下上 上下上:含空拍槽 1、4
  final chords = {
    for (final chord in uiFixtureLibrary.chords) chord.label: chord,
  };
  const t0 = Duration(milliseconds: 500);

  /// 谱与时间轴每次现构造(parseChart 的 expect 须在测试内求值);
  /// 80 BPM:750ms/拍、一拍两槽 375ms、一行(一小节)3 秒、全曲 16 拍。
  Future<void> pumpView(
    WidgetTester tester,
    Duration elapsed, {
    List<StrumJudgment?>? liveVerdicts,
  }) async {
    final timeline = compileTimeline(
      chart: practiceFixtureChart,
      pattern: island,
      bpm: 80,
    );
    final practice = practiceStateAt(
      timeline: timeline,
      t0: t0,
      now: t0 + elapsed,
    )!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeView(
            timeline: timeline,
            practice: practice,
            pattern: island,
            chords: chords,
            liveVerdicts: liveVerdicts,
          ),
        ),
      ),
    );
  }

  final currentLine = find.byKey(const Key('lyric-current'));

  Color cellColor(WidgetTester tester, int i) =>
      (tester.widget<Container>(find.byKey(Key('play-slot-$i'))).decoration!
              as BoxDecoration)
          .color!;

  Icon? slotIcon(WidgetTester tester, int i) {
    final cell = find.descendant(
      of: find.byKey(Key('play-slot-$i')),
      matching: find.byType(Icon),
    );
    return tester.widgetList<Icon>(cell).firstOrNull;
  }

  /// 判定染色的槽位辅助:槽位的填充/描边/内容色(容器装饰与图标分开读)。
  BoxDecoration slotDecoration(WidgetTester tester, int i) =>
      tester.widget<Container>(
        find.byKey(Key('play-slot-$i')),
      ).decoration! as BoxDecoration;

  Color slotIconColor(WidgetTester tester, int i) =>
      slotIcon(tester, i)!.color!;

  testWidgets('曲首:当前段落下、第一行高亮且和弦在歌词上方、后续行可见、拍号 1', (
    tester,
  ) async {
    await pumpView(tester, const Duration(milliseconds: 100));

    expect(find.text('主歌'), findsOneWidget, reason: '当前段落标签');
    expect(
      find.descendant(of: currentLine, matching: find.text('Am')),
      findsOneWidget,
      reason: '和弦名在当前行内',
    );
    expect(
      find.descendant(of: currentLine, matching: find.textContaining('第一行歌词')),
      findsOneWidget,
    );
    // 布局契约:和弦行在歌词行上方(不与歌词同行混排)。
    final chordRect = tester.getRect(
      find.descendant(of: currentLine, matching: find.text('Am')),
    );
    final lyricRect = tester.getRect(
      find.descendant(of: currentLine, matching: find.textContaining('第一行歌词')),
    );
    expect(chordRect.bottom, lessThanOrEqualTo(lyricRect.top));
    expect(
      find.textContaining('第一行歌词'),
      findsOneWidget,
      reason: '曲首无上一行:该行只作为当前行渲染一次',
    );
    expect(find.textContaining('第二行歌词'), findsOneWidget, reason: '下一行预告可见');
    expect(tester.widget<Text>(find.byKey(const Key('beat-number'))).data, '1');
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byKey(const Key('progress')))
          .value,
      closeTo(0, 1e-9),
    );
  });

  testWidgets('行进:第二行成为当前行,上一行淡出可见,和弦小图切到 C', (tester) async {
    await pumpView(tester, const Duration(seconds: 3, milliseconds: 100));

    expect(
      find.descendant(of: currentLine, matching: find.textContaining('第二行歌词')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: currentLine, matching: find.text('C')),
      findsOneWidget,
      reason: '当前行的和弦行显示 C',
    );
    expect(find.textContaining('第一行歌词'), findsOneWidget, reason: '上一行淡出仍可见');

    expect(
      tester.widget<Text>(find.byKey(const Key('chord-name'))).data,
      'C',
      reason: '当前和弦随小节切换',
    );
    final diagram = tester.widget<ChordDiagram>(
      find.descendant(
        of: find.byKey(const Key('chord-card')),
        matching: find.byType(ChordDiagram),
      ),
    );
    expect(diagram.fingering.frets, [0, 0, 0, 3], reason: 'C 主指法指法图');
  });

  testWidgets('段落切换:副歌标签、和弦 C、进度前移', (tester) async {
    await pumpView(tester, const Duration(seconds: 6, milliseconds: 100));

    expect(find.text('副歌'), findsOneWidget);
    expect(
      find.descendant(of: currentLine, matching: find.textContaining('第三行歌词')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('chord-name'))).data,
      'C',
      reason: '第三行 [C] 独占一小节',
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byKey(const Key('progress')))
          .value,
      closeTo(8 / 16, 1e-9),
      reason: '第 3 小节起:8/16 拍',
    );
  });

  testWidgets('箭头条:8 槽按节奏型排布,当前动作点亮、已扫淡出、未到描边', (tester) async {
    // elapsed 1200ms:槽 3(1125ms 上扫)是当前动作,槽 0、2 已扫。
    await pumpView(tester, const Duration(milliseconds: 1200));

    expect(slotIcon(tester, 0)!.icon, Icons.arrow_downward);
    expect(slotIcon(tester, 1), isNull, reason: '空拍槽画圆点');
    expect(slotIcon(tester, 3)!.icon, Icons.arrow_upward);

    final context = tester.element(find.byKey(const Key('play-slot-3')));
    final primary = Theme.of(context).colorScheme.primary;
    expect(cellColor(tester, 3), primary, reason: '当前动作点亮');
    expect(cellColor(tester, 0), isNot(primary), reason: '已扫淡出');
    expect(cellColor(tester, 5), isNot(primary), reason: '未到描边待命');

    expect(
      tester.widget<Text>(find.byKey(const Key('beat-number'))).data,
      '2',
      reason: '槽 3 = 拍 2 的后半拍',
    );
  });

  testWidgets('实时判定染色(工单 36):弹过的槽按四色渲染,漏灰空心,未定不染', (tester) async {
    // island 槽序 0,2,3,5,6,7 = 谱序 spot 0..5。判定各给一色:
    // slot0 准 / slot2 晚 / slot3 漏 / slot5 未定 / slot6 早 / slot7 错。
    final live = [
      StrumJudgment.onTime,
      StrumJudgment.late,
      StrumJudgment.missed,
      null,
      StrumJudgment.early,
      StrumJudgment.wrong,
    ];
    // elapsed 1200ms:槽 3 是当前动作(spot 2,判漏)。
    await pumpView(tester, const Duration(milliseconds: 1200), liveVerdicts: live);

    // 准=绿:填充语义色,箭头白。
    expect(slotDecoration(tester, 0).color, judgmentOnTimeColor);
    expect(slotIconColor(tester, 0), Colors.white);
    // 晚=黄:填充黄,内容换深色(白在黄上不可读)。
    expect(slotDecoration(tester, 2).color, judgmentLateColor);
    expect(slotIconColor(tester, 2), Colors.black87);
    // 漏=灰空心:透明底 + 灰描边 + 灰内容。
    final missed = slotDecoration(tester, 3);
    expect(missed.color, Colors.transparent);
    expect(missed.border, isNotNull);
    expect(
      missed.border!.top.color,
      judgmentMissedColor,
      reason: '漏 = 灰空心描边',
    );
    expect(slotIconColor(tester, 3), judgmentMissedColor);
    // 未定:不着色,保持未到描边待命的底样式。
    final pending = slotDecoration(tester, 5);
    expect(pending.color, Colors.transparent);
    expect(
      pending.border!.top.color,
      isNot(judgmentMissedColor),
      reason: '未定不染色',
    );
    // 早=蓝、错=红。
    expect(slotDecoration(tester, 6).color, judgmentEarlyColor);
    expect(slotDecoration(tester, 7).color, judgmentWrongColor);
  });

  testWidgets('无评分遍(liveVerdicts null):箭头条保持原样式', (tester) async {
    await pumpView(tester, const Duration(milliseconds: 1200));
    final context = tester.element(find.byKey(const Key('play-slot-3')));
    expect(
      slotDecoration(tester, 3).color,
      Theme.of(context).colorScheme.primary,
      reason: '当前动作照旧点亮',
    );
    expect(slotDecoration(tester, 0).color, isNot(judgmentOnTimeColor));
  });

  testWidgets('下一和弦小预告:曲首显示下一换和弦点 C,图小一号', (tester) async {
    await pumpView(tester, const Duration(milliseconds: 100));

    expect(
      tester.widget<Text>(find.byKey(const Key('next-chord-name'))).data,
      'C',
      reason: 'fixture 第 2 小节 [C] 是 Am 之后的换和弦点',
    );
    expect(find.byKey(const Key('next-chord-diagram')), findsOneWidget);
    final nextRect = tester.getRect(find.byKey(const Key('next-chord-diagram')));
    final curRect = tester.getRect(find.byKey(const Key('chord-diagram')));
    expect(nextRect.width, lessThan(curRect.width), reason: '预告用小尺寸');
  });

  testWidgets('曲末无下一和弦:预告卡不占位', (tester) async {
    // 第 4 小节 [Am] 之后没有换和弦点了。
    await pumpView(tester, const Duration(seconds: 9, milliseconds: 100));
    expect(find.byKey(const Key('next-chord-card')), findsNothing);
  });

  testWidgets('窄屏(360dp)不溢出', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await pumpView(tester, const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('和弦库缺位降级:和弦名照走,只有指法小图缺席', (tester) async {
    final timeline = compileTimeline(
      chart: practiceFixtureChart,
      pattern: island,
      bpm: 80,
    );
    final practice = practiceStateAt(
      timeline: timeline,
      t0: t0,
      now: t0 + const Duration(milliseconds: 100),
    )!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeView(
            timeline: timeline,
            practice: practice,
            pattern: island,
            chords: const {}, // 和弦库缺位的极端路径
          ),
        ),
      ),
    );

    expect(
      tester.widget<Text>(find.byKey(const Key('chord-name'))).data,
      'Am',
      reason: '名字来自扫弦事件,不依赖查表',
    );
    expect(find.byKey(const Key('chord-diagram')), findsNothing);
  });

  testWidgets('超长歌词行+矮屏:歌词区可滚,不溢出', (tester) async {
    tester.view.physicalSize = const Size(1080, 1500); // 360×500 逻辑像素
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final longLine = '很长的一句歌词' * 12;
    final chart = parseChart('{title: 长词}\n[C]$longLine\n[Am]第二行\n');
    final timeline = compileTimeline(chart: chart, pattern: island, bpm: 80);
    final practice = practiceStateAt(
      timeline: timeline,
      t0: t0,
      now: t0 + const Duration(milliseconds: 100),
    )!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PracticeView(
            timeline: timeline,
            practice: practice,
            pattern: island,
            chords: chords,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull, reason: '溢出条纹即失败');
    expect(
      find.byType(SingleChildScrollView),
      findsOneWidget,
      reason: '长内容落在可滚容器里',
    );
  });

  testWidgets('歌词余高不足 24px 不产生负 BoxConstraints 崩溃(审计30 #36)', (tester) async {
    // 高度选在「外层固定控件恰好放下、歌词 Expanded 余高 <24px」的窗口
    // (180px 连外层都会溢出,是另一个问题,不在本条范围):此处旧实现
    // 会算出负 maxHeight 直接 BoxConstraints 断言崩,新实现钳零。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 280);
    addTearDown(tester.view.reset);
    await pumpView(tester, const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull,
        reason: '余高不足 24px 时歌词块 maxHeight 钳零,不得负约束断言崩');
  });

}