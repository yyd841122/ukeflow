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
    // 弹前读谱 = 横带全景(横向可拖)——整页折行已按真机反馈移除。
    expect(find.byKey(const Key('score-strip')), findsOneWidget);
    expect(find.text('1=E'), findsOneWidget, reason: '谱角调号在带首');
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
    expect(tester.widget<ButtonStyleButton>(start).onPressed, isNotNull,
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

    // 跨过预备(约 3077ms)进正曲:流水横带就位,拍号与进度条在位。
    await advanceAndPump(tester, 3300);
    expect(find.byKey(const Key('score-prep-count')), findsNothing);
    expect(find.byKey(const Key('score-strip')), findsOneWidget);
    expect(find.byKey(const Key('score-beat-number')), findsOneWidget);
    expect(find.byKey(const Key('score-progress')), findsOneWidget);

    // 流水跟滚:正曲初期(全休止小节)播放头未过视口锚点,位移为 0。
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('score-strip-scroll')),
    ).controller!;
    expect(scroll.offset, 0.0, reason: '播放头未到视口锚点不滚');

    // 再推 6 秒(主歌进行中):横带已向左滑出一段,流水位移 > 0。
    await advanceAndPump(tester, 6000);
    expect(scroll.offset, greaterThan(0), reason: '横带随播放流水左移');
    final after6s = scroll.offset;
    await advanceAndPump(tester, 2000);
    expect(scroll.offset, greaterThan(after6s), reason: '持续流动不跳变');
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
    expect(find.byKey(const Key('score-strip')), findsOneWidget);
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


  testWidgets('横带双层:静态带与当位覆盖层各一,画布即带宽', (tester) async {
    engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          home: Scaffold(
            body: ScoreStripView(
              def: def,
              tabChart: solo,
              melodyChart: melody,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final strip = tester.widget<SizedBox>(
      find.byKey(const Key('score-strip')),
    );
    final layout = ScoreSheetLayout(
      def: def,
      tabChart: solo,
      melodyChart: melody,
    );
    expect(strip.width, layout.stripWidth);
    final painters = tester.widgetList<CustomPaint>(
      find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter != null &&
            (w.painter.runtimeType.toString() == '_StripPainter' ||
                w.painter.runtimeType.toString() == '_StripHighlightPainter'),
      ),
    ).toList();
    expect(painters, hasLength(2), reason: '静态带 + 当位覆盖层');
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
          .widget<ButtonStyleButton>(
            find.byKey(const Key('score-practice-start')),
          )
          .onPressed,
      isNull,
      reason: '引擎未就绪不可启',
    );
  });

  testWidgets('双钮并排(票07 反馈):示范试听 + 开始跟练同屏,互不顶掉', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('示范试听'), findsOneWidget, reason: '伴奏声试听常在');
    expect(find.text('开始跟练'), findsOneWidget, reason: '节拍声跟练常在');
    expect(tester.widget<ButtonStyleButton>(
      find.byKey(const Key('score-beat-practice-start')),
    ).onPressed, isNotNull, reason: '跟练钮就绪可启');
  });

  testWidgets('节拍跟练起播:预备倒计 → 正曲强弱 tick、无拨弦声、提示条在位', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.ensureVisible(
      find.byKey(const Key('score-beat-practice-start')),
    );
    await tester.tap(find.byKey(const Key('score-beat-practice-start')));
    await tester.pump();
    expect(find.byKey(const Key('score-prep-count')), findsOneWidget);

    // 预备期提示条 = 占位;跨过预备(78BPM 4 拍 ≈ 3077ms)进正曲。
    expect(find.textContaining('跟着拍子数'), findsOneWidget);
    await advanceAndPump(tester, 3600);
    expect(find.byKey(const Key('score-prep-count')), findsNothing);
    expect(find.byKey(const Key('play-hint-bar')), findsOneWidget);
    expect(find.textContaining('跟着拍子数'), findsNothing,
        reason: '正曲期提示条换帧');
    expect(find.textContaining('小节'), findsOneWidget,
        reason: '提示条头部小节拍位行');

    // 参考声 = 强弱 tick,无逐音拨弦(端到端锁 start 参数接线)。
    final ticks = engine.scheduleLog
        .where((e) => e.key.startsWith('tick_'))
        .toList();
    expect(ticks.where((e) => e.key == 'tick_count'), isNotEmpty,
        reason: '预备数拍在响');
    expect(engine.scheduleLog.where((e) => e.key.startsWith('pluck_')),
        isEmpty, reason: '节拍跟练无拨弦声');
    expect(ticks.where((e) => e.key == 'tick_strong'), isNotEmpty,
        reason: '曲头强拍已响');
  });

  testWidgets('伴奏声示范起播:提示条照常在位(逐列推进与声源无关)', (tester) async {
    await pumpPage(tester);
    await tapStart(tester);
    await tester.pump();
    await advanceAndPump(tester, 3600);
    expect(find.byKey(const Key('play-hint-bar')), findsOneWidget);
    expect(find.textContaining('小节'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
