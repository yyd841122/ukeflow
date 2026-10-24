import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/practice/score_sheet_layout.dart';
import 'package:ukeflow/features/play/score_sheet_page.dart';
import 'package:ukeflow/features/play/score_sheet_view.dart';

/// 谱面视图会话页(工单 39):引擎一律 FakeAudioEngine,时间用
/// engine.advance 推进。锁页面结构与流转:空闲(谱面+轨道选择)→ 预备
/// 倒计 → 跟随视图;双轨换谱可起播。四层对齐/当位查询的内核在
/// score_sheet_layout_test,声音调度复用指弹管线不重复锁。
void main() {
  late FakeAudioEngine engine;
  final def = scoreSheetCatalog.single;
  final charts = {for (final e in builtinTabChartCatalog) e.id: e.chart};
  final solo = charts[def.tabChartId]!;
  final melody = charts[def.melodyChartId]!;

  Future<void> pumpPage(WidgetTester tester) async {
    engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(engine)],
        child: MaterialApp(home: const Scaffold(body: SizedBox.shrink())),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ScoreSheetPage(
              def: def,
              tabChart: solo,
              melodyChart: melody,
            ),
          ),
        );
    await tester.pumpAndSettle(); // 空闲页无周期定时器,可安全落定
  }

  /// 空闲面板高(弹前读谱 420px+控件),开始钮在折叠下:先滚进视野再点。
  Future<void> tapStart(WidgetTester tester) async {
    final start = find.byKey(const Key('score-practice-start'));
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    await tester.tap(start);
  }

  Future<void> advanceAndPump(WidgetTester tester, int ms) async {
    var left = ms;
    while (left > 0) {
      final step = left > 400 ? 400 : left;
      engine.advance(Duration(milliseconds: step));
      await tester.pump(const Duration(milliseconds: 60));
      left -= step;
    }
  }

  testWidgets('空闲渲染:元信息(谱角 1=E)、谱面画布、轨道选择、就绪可启', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('爱你不是两三天'), findsOneWidget, reason: 'AppBar 曲名');
    expect(find.text('谱面视图 · 梁静茹 · 78 BPM · 1=E'), findsOneWidget);
    // 弹前读谱为一行(首系统)——整页太长会顶走开始示范按钮(真机反馈)。
    expect(find.byKey(const Key('score-sheet-line')), findsOneWidget);
    expect(find.text('1=E'), findsOneWidget, reason: '谱角调号画在行首');
    // 一屏可达开始示范:行高(约 180px)+控件行,按钮在首屏视口内。
    final startCenter = tester.getCenter(
      find.byKey(const Key('score-practice-start')),
    );
    expect(
      startCenter.dy,
      lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio),
      reason: '按钮在视口内',
    );
    expect(find.text('伴奏示范'), findsOneWidget);
    expect(find.text('双轨混播'), findsOneWidget);
    final start = find.byKey(const Key('score-practice-start'));
    expect(start, findsOneWidget);
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull,
        reason: '引擎就绪后可启');
    expect(tester.takeException(), isNull);
  });

  testWidgets('单轨示范起播:预备倒计 → 跟随视图(进度条),伴奏谱原样', (tester) async {
    await pumpPage(tester);

    await tester.ensureVisible(find.text('伴奏示范'));
    await tester.tap(find.text('伴奏示范'));
    await tester.pump();
    await tapStart(tester);
    await tester.pump();

    // 78BPM 预备 4 拍:启动即第 1 声倒计。
    expect(find.byKey(const Key('score-prep-count')), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    // 跨过预备(约 3077ms)进正曲:单系统一行视图就位(整页易乱,真机
    // 反馈改一行),拍号与进度条在位。
    await advanceAndPump(tester, 3300);
    expect(find.byKey(const Key('score-prep-count')), findsNothing);
    expect(find.byKey(const Key('score-sheet-line')), findsOneWidget,
        reason: '运行态只出当前一行');
    expect(find.byKey(const Key('score-sheet-canvas')), findsNothing,
        reason: '整页滚动视图不进运行态');
    expect(find.byKey(const Key('score-beat-number')), findsOneWidget);
    expect(find.byKey(const Key('score-progress')), findsOneWidget);
  });

  testWidgets('双轨混播换谱起播:合并谱(旋律+20 拍/+4 半音)照常编译走拍', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.ensureVisible(find.text('双轨混播'));
    await tester.tap(find.text('双轨混播'));
    await tester.pump();
    await tapStart(tester);
    await tester.pump();
    expect(find.byKey(const Key('score-prep-count')), findsOneWidget);

    await advanceAndPump(tester, 3300);
    expect(find.byKey(const Key('score-sheet-line')), findsOneWidget);
    expect(find.byKey(const Key('score-progress')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('弹回即停:运行中退页,无残留异常', (tester) async {
    await pumpPage(tester);
    await tapStart(tester);
    await tester.pump();
    expect(find.byKey(const Key('score-prep-count')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('爱你不是两三天'), findsNothing, reason: '已退页');
  });


  testWidgets('单行视图:任意系统的画布都从原点画(第 2 行起四层可见)', (tester) async {
    engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          home: Scaffold(
            body: ScoreSheetSystemView(
              def: def,
              tabChart: solo,
              melodyChart: melody,
              system: 2,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 画布只有一个系统高;画笔纵原点必须为 0——带系统偏移会把
    // 琴弦/简谱/歌词画到画布外(真机第 2 行起只剩和弦图,2026-10-24)。
    final canvas = tester.renderObject<RenderBox>(
      find.byKey(const Key('score-sheet-line')),
    );
    expect(canvas.size.height, ScoreSheetLayout.systemHeight);
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter != null &&
            w.painter.runtimeType.toString() == '_ScoreSystemPainter',
      ),
    );
    final painter = paint.painter as dynamic;
    expect(painter.originY, 0.0);
    expect(painter.system, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('引擎初始化失败:错误可见、开始禁用,重试钮在位', (tester) async {
    engine = FakeAudioEngine()..failInitialization = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(engine)],
        child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ScoreSheetPage(
              def: def,
              tabChart: solo,
              melodyChart: melody,
            ),
          ),
        );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('warmup-retry')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('score-practice-start')),
          )
          .onPressed,
      isNull,
      reason: '引擎未就绪不可启',
    );
  });
}
