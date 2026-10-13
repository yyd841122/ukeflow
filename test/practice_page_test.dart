import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/features/play/practice_page.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';

/// 跟练会话页:引擎一律注入 FakeAudioEngine,时间用 engine.advance 推进
/// (真定时器靠 tester.pump(duration) 喂)。
void main() {
  late FakeAudioEngine engine;

  Future<void> pumpPage(WidgetTester tester) async {
    engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEngineProvider.overrideWithValue(engine),
          chordLibraryFixtureOverride(),
        ],
        child: MaterialApp(home: const Scaffold(body: SizedBox.shrink())),
      ),
    );
    // 经路由压栈打开:会话页在产品里是 push 页(带返回钮),与导航一致。
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(
          builder: (_) => PracticePage(chart: practiceFixtureChart),
        ));
    await tester.pumpAndSettle(); // 空闲页无周期定时器,可安全落定
  }

  /// 从开始起推进 [ms] 引擎时间,并喂轮询/调度定时器。
  Future<void> advanceAndPump(WidgetTester tester, int ms) async {
    var left = ms;
    while (left > 0) {
      final step = left > 400 ? 400 : left;
      engine.advance(Duration(milliseconds: step));
      await tester.pump(const Duration(milliseconds: 60));
      left -= step;
    }
  }

  testWidgets('空闲渲染:曲名进 AppBar、谱面 tempo 为默认速度、节奏型可挑、就绪可启', (tester) async {
    await pumpPage(tester);

    expect(find.text('测试曲'), findsOneWidget, reason: 'AppBar 曲名');
    expect(find.text('测试者 · C 调 · 80 BPM'), findsOneWidget,
        reason: '元信息行来自谱面 meta');
    expect(find.text('引擎就绪'), findsOneWidget);
    expect(find.byKey(const Key('pattern-island')), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('practice-start')))
          .onPressed,
      isNotNull,
      reason: '引擎就绪后可启',
    );
  });

  testWidgets('引擎初始化失败:错误可见,开始禁用', (tester) async {
    engine = FakeAudioEngine()..failInitialization = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEngineProvider.overrideWithValue(engine),
          chordLibraryFixtureOverride(),
        ],
        child: MaterialApp(home: PracticePage(chart: practiceFixtureChart)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('引擎初始化失败'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('practice-start')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('开始即入跟练:当前行/和弦/拍号渲染,推进后随引擎时刻前移', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('practice-start')));
    await tester.pump(); // start 生效
    await tester.pump(const Duration(milliseconds: 20)); // 喂 16ms 轮询首查

    expect(find.byKey(const Key('practice-stop')), findsOneWidget);
    expect(find.byKey(const Key('practice-start')), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('lyric-current')))
          .textSpan!
          .toPlainText(),
      contains('第一行歌词'),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('chord-name'))).data,
      'Am',
      reason: '首小节和弦',
    );

    // 一小节(3 秒)后:第二行、C 和弦。节拍声不验证在此(控制器已测),
    // 这里验证的是轮询把练习状态灌进视图。
    await advanceAndPump(tester, 3100);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('lyric-current')))
          .textSpan!
          .toPlainText(),
      contains('第二行歌词'),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('chord-name'))).data,
      'C',
    );
  });

  testWidgets('曲末自动回闲:节拍声恰为全曲拍数(无幻拍),控制面板回归', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('practice-start')));
    await tester.pump();

    // 全曲 16 拍 × 750ms = 12 秒;多推 1 秒喂完尾拍。
    await advanceAndPump(tester, 13000);

    expect(find.byKey(const Key('practice-start')), findsOneWidget,
        reason: '曲末自动回闲');
    expect(engine.scheduleLog, hasLength(16),
        reason: '节拍声恰为全曲拍数,曲末无幻拍声');
    for (final call in engine.scheduleLog) {
      expect(call.time.inMilliseconds, lessThan(12000), reason: '都在曲长内');
    }

    final countAfterEnd = engine.scheduleLog.length;
    await advanceAndPump(tester, 2000);
    expect(engine.scheduleLog, hasLength(countAfterEnd), reason: '回闲后不再调度');
  });

  testWidgets('窄屏(360dp):空闲面板与运行视图都不溢出', (tester) async {
    // 默认测试面 800×600 抓不到窄屏溢出(工单 04 教训)。
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await pumpPage(tester);
    expect(tester.takeException(), isNull, reason: '空闲面板');

    await tester.tap(find.byKey(const Key('practice-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull, reason: '运行视图');
  });

  testWidgets('运行中弹回:页面卸载即停,不残留调度', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('practice-start')));
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final countAfterPop = engine.scheduleLog.length;
    await advanceAndPump(tester, 2000);
    expect(engine.scheduleLog, hasLength(countAfterPop), reason: '弹回即停');
  });
}
