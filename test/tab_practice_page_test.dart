import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/features/play/tab_chart_page.dart';

import 'helpers/chart_fixtures.dart';

/// 指弹跟练会话页运行态:引擎一律注入 FakeAudioEngine,时间用
/// engine.advance 推进(真定时器靠 tester.pump(duration) 喂)。
/// 锁页面流转:预备倒计 → 正曲视图 → 曲末回闲;暂停冻结;回开头;停止。
void main() {
  late FakeAudioEngine engine;

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
            builder: (_) => TabChartPage(chart: tabFixtureChart),
          ),
        );
    await tester.pumpAndSettle(); // 空闲页无周期定时器,可安全落定
  }

  /// 从当前起推进 [ms] 引擎时间,并喂轮询/调度定时器。
  Future<void> advanceAndPump(WidgetTester tester, int ms) async {
    var left = ms;
    while (left > 0) {
      final step = left > 400 ? 400 : left;
      engine.advance(Duration(milliseconds: step));
      await tester.pump(const Duration(milliseconds: 60));
      left -= step;
    }
  }

  testWidgets('开始跟练:预备倒计面板 → 正曲四线谱视图(拍号+进度)', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('tab-practice-start')));
    await tester.pump();

    // 引擎 t0=0、80BPM:预备窗 [0, 3000),启动即第 1 声倒计。
    expect(find.byKey(const Key('tab-prep-count')), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    // 跨过预备(3200ms)进正曲:倒计让位,逐音视图就位。
    await advanceAndPump(tester, 3200);
    expect(find.byKey(const Key('tab-prep-count')), findsNothing);
    expect(find.byKey(const Key('tab-beat-number')), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: '曲内第 1 拍');
    expect(find.byKey(const Key('tab-progress')), findsOneWidget);

    // 正曲无强弱拍 tick(逐音示范声即参考声,页面层不再断言声音,见控制器测试)。
    expect(
      engine.scheduleLog.where(
        (e) => e.key.startsWith('tick_') && e.key != 'tick_count',
      ),
      isEmpty,
    );
  });

  testWidgets('曲末自动回闲:节拍网格走出最后一拍,回空闲面板', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('tab-practice-start')));
    await tester.pump();
    await advanceAndPump(tester, 3200);
    expect(find.byKey(const Key('tab-beat-number')), findsOneWidget);

    // 全曲 3000ms:再推 3000 过名义曲长 → 自动回闲,轮询自停。
    await advanceAndPump(tester, 3000);
    expect(
      find.byKey(const Key('tab-practice-start')),
      findsOneWidget,
      reason: '曲末回空闲面板,可再启',
    );
    expect(find.byKey(const Key('tab-beat-number')), findsNothing);
  });

  testWidgets('暂停冻结画面,继续后推进;回到开头重新数拍;停止回闲', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('tab-practice-start')));
    await tester.pump();
    await advanceAndPump(tester, 3200);

    final beatBefore = find.text('1');
    expect(beatBefore, findsOneWidget);
    await tester.tap(find.byKey(const Key('tab-practice-pause')));
    await tester.pump();
    expect(find.text('继续'), findsOneWidget, reason: '按钮翻转为继续');

    final frozenBeats = engine.scheduleLog.length;
    await advanceAndPump(tester, 1000);
    expect(find.text('1'), findsOneWidget, reason: '暂停中拍号冻结');
    expect(engine.scheduleLog.length, frozenBeats, reason: '暂停期间不预定新声');

    await tester.tap(find.byKey(const Key('tab-practice-pause'))); // 继续
    await tester.pump();
    await advanceAndPump(tester, 800);
    expect(find.text('2'), findsOneWidget, reason: '继续后拍位推进无错位');

    // 回到开头:干净复位,重新预备数拍。
    await tester.tap(find.byKey(const Key('tab-practice-restart')));
    await tester.pump();
    expect(find.byKey(const Key('tab-prep-count')), findsOneWidget);

    // 停止:退出会话回空闲。
    await advanceAndPump(tester, 100); // 脱离倒计帧,让停止钮可见
    await tester.tap(find.byKey(const Key('tab-practice-stop')));
    await tester.pump();
    expect(find.byKey(const Key('tab-practice-start')), findsOneWidget);
  });

  testWidgets('运行面板有变速控制,可即时调(状态落盘)', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('tab-practice-start')));
    await tester.pump();
    await advanceAndPump(tester, 3200);

    expect(find.byKey(const Key('speed-slider')), findsOneWidget);
    await tester.tap(find.byKey(const Key('speed-slider')));
    await tester.pump(kTabScrollDuration);
    // 滑块点击落到中点附近即 75%:状态可调即可,精确值归控制器测试。
    expect(find.byKey(const Key('speed-value')), findsOneWidget);
  });

  testWidgets('单曲循环:遍末自动接下一遍;关循环曲末回闲', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('tab-practice-start')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-practice-loop')));
    await tester.pump();
    expect(find.text('第 1 遍'), findsOneWidget);

    await advanceAndPump(tester, 3200); // 遍 1 预备
    await advanceAndPump(tester, 3000); // 遍 1 曲末 → nextPass
    await advanceAndPump(tester, 3200); // 遍 2 预备喂完
    expect(find.text('第 2 遍'), findsOneWidget, reason: '循环开:自动接下一遍');
    expect(find.byKey(const Key('tab-practice-stop')), findsOneWidget, reason: '仍在会话中');

    await tester.tap(find.byKey(const Key('tab-practice-loop')));
    await tester.pump();
    await advanceAndPump(tester, 3000); // 遍 2 曲末
    expect(find.byKey(const Key('tab-practice-start')), findsOneWidget, reason: '循环关:曲末回闲');
  });
}

/// 变速测试里给滑块动画一帧的时间。
const Duration kTabScrollDuration = Duration(milliseconds: 300);
