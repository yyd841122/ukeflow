import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/data/settings_providers.dart';
import 'package:ukeflow/features/demo/demo_playback_controller.dart';
import 'package:ukeflow/features/play/play_practice_controller.dart';
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
          // 「默认 BPM」消费缝(工单 20):override 隔离,不触真库。
          defaultBpmProvider.overrideWithValue(80),
        ],
        child: MaterialApp(home: const Scaffold(body: SizedBox.shrink())),
      ),
    );
    // 经路由压栈打开:会话页在产品里是 push 页(带返回钮),与导航一致。
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => PracticePage(chart: practiceFixtureChart),
          ),
        );
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
    expect(
      find.text('测试者 · C 调 · 80 BPM'),
      findsOneWidget,
      reason: '元信息行来自谱面 meta',
    );
    expect(find.text('引擎就绪'), findsOneWidget);
    expect(find.byKey(const Key('pattern-island')), findsOneWidget);
    expect(
      find.byKey(const Key('speed-slider')),
      findsOneWidget,
      reason: '空闲可定变速',
    );
    expect(
      find.byKey(const Key('reference-beat')),
      findsOneWidget,
      reason: '空闲可选参考音',
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('practice-start')))
          .onPressed,
      isNotNull,
      reason: '引擎就绪后可启',
    );
  });

  testWidgets('引擎初始化失败:错误可见、开始禁用,重试钮原地恢复', (tester) async {
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
      tester
          .widget<FilledButton>(find.byKey(const Key('practice-start')))
          .onPressed,
      isNull,
    );

    // 原地重试:失败源解除后恢复就绪。
    engine.failInitialization = false;
    await tester.tap(find.byKey(const Key('warmup-retry')));
    await tester.pumpAndSettle();
    expect(find.text('引擎就绪'), findsOneWidget);
    expect(find.textContaining('引擎初始化失败'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('practice-start')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('开始即入预备:倒计 4 起步,预备完进正曲渲染行/和弦/拍号', (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(find.byKey(const Key('practice-start')));
    await tester.tap(find.byKey(const Key('practice-start')));
    await tester.pump(); // start 生效
    await tester.pump(const Duration(milliseconds: 20)); // 喂 16ms 轮询首查

    // 预备数拍:倒计面板,起步倒数 4;正曲视图未上。
    expect(find.byKey(const Key('prep-count')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('prep-count'))).data, '4');
    expect(find.byKey(const Key('lyric-current')), findsNothing);

    // 预备 4 拍(80BPM = 3 秒)后进正曲:第一行、Am。
    await advanceAndPump(tester, 3100);
    expect(find.byKey(const Key('prep-count')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('lyric-current')),
        matching: find.textContaining('第一行歌词'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('lyric-current')),
        matching: find.text('Am'),
      ),
      findsOneWidget,
      reason: '和弦行在歌词上方',
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
      find.descendant(
        of: find.byKey(const Key('lyric-current')),
        matching: find.textContaining('第二行歌词'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<Text>(find.byKey(const Key('chord-name'))).data, 'C');
  });

  testWidgets('预备数拍逐拍递减:4→3', (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(find.byKey(const Key('practice-start')));
    await tester.tap(find.byKey(const Key('practice-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.widget<Text>(find.byKey(const Key('prep-count'))).data, '4');

    await advanceAndPump(tester, 800); // 过第 1 预备拍(750ms)
    expect(tester.widget<Text>(find.byKey(const Key('prep-count'))).data, '3');
  });

  testWidgets('暂停冻结画面,继续后随引擎时刻续跑', (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(find.byKey(const Key('practice-start')));
    await tester.tap(find.byKey(const Key('practice-start')));
    await advanceAndPump(tester, 4600); // 曲内 1600ms:第一行、Am

    await tester.tap(find.byKey(const Key('practice-pause')));
    await tester.pump();
    final frozenChord = tester
        .widget<Text>(find.byKey(const Key('chord-name')))
        .data;
    final frozenBeat = tester
        .widget<Text>(find.byKey(const Key('beat-number')))
        .data;

    await advanceAndPump(tester, 2000); // 暂停期间引擎照走
    expect(
      tester.widget<Text>(find.byKey(const Key('chord-name'))).data,
      frozenChord,
      reason: '暂停画面冻结',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('beat-number'))).data,
      frozenBeat,
    );

    await tester.tap(find.byKey(const Key('practice-pause'))); // 继续
    await advanceAndPump(tester, 2000);
    expect(
      tester.widget<Text>(find.byKey(const Key('beat-number'))).data,
      isNot(frozenBeat),
      reason: '继续后拍号前移(从暂停处续跑)',
    );
  });

  testWidgets('回到开头:重进预备倒计', (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(find.byKey(const Key('practice-start')));
    await tester.tap(find.byKey(const Key('practice-start')));
    await advanceAndPump(tester, 4600);
    expect(find.byKey(const Key('prep-count')), findsNothing);

    await tester.tap(find.byKey(const Key('practice-restart')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      find.byKey(const Key('prep-count')),
      findsOneWidget,
      reason: '重新数预备拍',
    );
    expect(tester.widget<Text>(find.byKey(const Key('prep-count'))).data, '4');
  });

  testWidgets('真机反馈轮:右栏预告与随行扫弦均已撤除,版式回全宽', (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(find.byKey(const Key('practice-start')));
    await tester.tap(find.byKey(const Key('practice-start')));
    await advanceAndPump(tester, 4200); // 曲内 1200ms:第一行、Am

    expect(
      find.byKey(const Key('preview-past')),
      findsNothing,
      reason: '右侧俄罗斯方块栏已撤',
    );
    expect(find.byKey(const Key('preview-upcoming-0')), findsNothing);
    expect(
      find.byKey(const Key('lyric-strums')),
      findsNothing,
      reason: '随行扫弦已撤(歌词对齐方案暂缓)',
    );
  });

  testWidgets('运行面板:参考音可切示范扫弦(拨弦声入窗)、变速滑杆生效', (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(find.byKey(const Key('practice-start')));
    await tester.tap(find.byKey(const Key('practice-start')));
    await advanceAndPump(tester, 3700); // 曲内 700ms

    await tester.tap(find.byKey(const Key('reference-strum')));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('reference-strum'))),
    );
    expect(
      container.read(playPracticeProvider).reference,
      ReferenceSound.strum,
    );
    expect(
      engine.scheduleLog.any((e) => e.key.startsWith('pluck_')),
      isTrue,
      reason: '切扫弦后窗内事件预定拨弦声',
    );

    // 变速滑杆:点中点 = 75%,运行中即时重编译(视觉不炸即可,编译已测)。
    await tester.tap(
      find.byKey(const Key('speed-slider')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(container.read(playPracticeProvider).speed, 0.75);
    expect(tester.takeException(), isNull);
  });

  testWidgets('曲末自动回闲:节拍声恰为预备+全曲拍数(无幻拍),控制面板回归', (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(find.byKey(const Key('practice-start')));
    await tester.tap(find.byKey(const Key('practice-start')));
    await tester.pump();

    // 预备 4 拍(3 秒)+ 全曲 16 拍(12 秒)= 20 声;曲末 15 秒,多推 1 秒喂完尾拍。
    await advanceAndPump(tester, 16000);

    expect(
      find.byKey(const Key('practice-start')),
      findsOneWidget,
      reason: '曲末自动回闲',
    );
    expect(
      engine.scheduleLog,
      hasLength(20),
      reason: '预备 4 声 + 曲内 16 声,曲末无幻拍声',
    );
    expect(
      engine.scheduleLog.where((e) => e.key == 'tick_count'),
      hasLength(4),
      reason: '预备数拍专用音源',
    );
    for (final call in engine.scheduleLog) {
      expect(call.time.inMilliseconds, lessThan(15000), reason: '都在预备+曲长内');
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

    await tester.ensureVisible(find.byKey(const Key('practice-start')));
    await tester.tap(find.byKey(const Key('practice-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.takeException(), isNull, reason: '运行视图');
  });

  testWidgets('运行中弹回:页面卸载即停,不残留调度', (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(find.byKey(const Key('practice-start')));
    await tester.tap(find.byKey(const Key('practice-start')));
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final countAfterPop = engine.scheduleLog.length;
    await advanceAndPump(tester, 2000);
    expect(engine.scheduleLog, hasLength(countAfterPop), reason: '弹回即停');
  });

  /// 工单 11:示范试听(空闲面板一键整曲扫弦)。
  group('示范试听', () {
    DemoPlaybackState demoState(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(Navigator)), // 弹回后按钮已不在树上
        ).read(demoPlaybackProvider);

    testWidgets('空闲面板有试听钮:引擎未就绪禁用,就绪可点', (tester) async {
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
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('demo-toggle')))
            .onPressed,
        isNull,
        reason: '引擎未就绪不可试听',
      );
    });

    testWidgets('点按即整曲发声(下扫长衰减),再点停止:未响弦停净、按钮回', (tester) async {
      await pumpPage(tester);
      await tester.ensureVisible(find.byKey(const Key('demo-toggle')));
      await tester.tap(find.byKey(const Key('demo-toggle')));
      await tester.pump(); // 准备链(假引擎即时完成)+ 重绘

      expect(demoState(tester).status, DemoPlaybackStatus.playing);
      expect(
        engine.scheduleLog.where((c) => c.key.startsWith('pluck_')),
        isNotEmpty,
        reason: '窗内扫弦事件已预定拨弦',
      );
      expect(find.text('停止试听'), findsOneWidget);

      await tester.tap(find.byKey(const Key('demo-toggle')));
      await tester.pump();
      expect(demoState(tester).status, DemoPlaybackStatus.idle);
      final nowAtStop = engine.engineTime();
      expect(
        engine.scheduleLog.where(
          (c) => c.key.startsWith('pluck_') && !c.stopped && c.time > nowAtStop,
        ),
        isEmpty,
        reason: '未响的弦停净,无残留声',
      );
      expect(find.text('示范试听'), findsOneWidget);
    });

    testWidgets('试听走到曲末自动回闲,之后不再有预定', (tester) async {
      await pumpPage(tester);
      await tester.ensureVisible(find.byKey(const Key('demo-toggle')));
      await tester.tap(find.byKey(const Key('demo-toggle')));
      await tester.pump();

      await advanceAndPump(tester, 14000); // 曲长 12s+错峰尾+判定轮询余量

      expect(find.text('示范试听'), findsOneWidget, reason: '曲末自动回闲');
      final countAtEnd = engine.scheduleLog.length;
      await advanceAndPump(tester, 2000);
      expect(engine.scheduleLog, hasLength(countAtEnd), reason: '回闲后冻结');
    });

    testWidgets('试听中点开始跟练:试听即停,会话起跑不叠声', (tester) async {
      await pumpPage(tester);
      await tester.ensureVisible(find.byKey(const Key('demo-toggle')));
      await tester.tap(find.byKey(const Key('demo-toggle')));
      await tester.pump();
      expect(demoState(tester).status, DemoPlaybackStatus.playing);

      await tester.ensureVisible(find.byKey(const Key('practice-start')));
      await tester.tap(find.byKey(const Key('practice-start')));
      await tester.pump();

      expect(demoState(tester).status, DemoPlaybackStatus.idle, reason: '试听即停');
      expect(
        ProviderScope.containerOf(
          tester.element(find.byType(Navigator)), // 开跑后空闲面板已下树
        ).read(playPracticeProvider).running,
        isTrue,
      );
      final nowAtSwitch = engine.engineTime();
      expect(
        engine.scheduleLog.where(
          (c) =>
              c.key.startsWith('pluck_') && !c.stopped && c.time > nowAtSwitch,
        ),
        isEmpty,
        reason: '跟练起跑前试听未响弦已停',
      );
    });

    testWidgets('试听引擎出错:错误文案可见,按钮回示范试听', (tester) async {
      await pumpPage(tester);
      engine.failNow = true;
      await tester.ensureVisible(find.byKey(const Key('demo-toggle')));
      await tester.tap(find.byKey(const Key('demo-toggle')));
      await tester.pump();

      expect(find.textContaining('试听已停止'), findsOneWidget);
      expect(find.text('示范试听'), findsOneWidget);
    });

    testWidgets('试听中弹回:页面卸载即停,无残留调度', (tester) async {
      await pumpPage(tester);
      await tester.ensureVisible(find.byKey(const Key('demo-toggle')));
      await tester.tap(find.byKey(const Key('demo-toggle')));
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(demoState(tester).status, DemoPlaybackStatus.idle);
      final countAfterPop = engine.scheduleLog.length;
      await advanceAndPump(tester, 2000);
      expect(engine.scheduleLog, hasLength(countAfterPop), reason: '弹回即停');
    });
  });

  testWidgets('单曲循环:遍末自动接下一遍,预备数拍即遍间停顿;关循环曲末回闲', (tester) async {
    await pumpPage(tester);
    await tester.ensureVisible(find.byKey(const Key('practice-start')));
    await tester.tap(find.byKey(const Key('practice-start')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('practice-loop')));
    await tester.pump();
    expect(find.text('第 1 遍'), findsOneWidget);

    // 遍 1:预备 3s + 全曲 12s = 15s;多推 1s 喂完尾拍触发 nextPass。
    await advanceAndPump(tester, 16000);
    await advanceAndPump(tester, 3000); // 遍 2 预备数拍喂完
    expect(find.text('第 2 遍'), findsOneWidget, reason: '循环开:自动接下一遍');
    expect(find.byKey(const Key('practice-stop')), findsOneWidget, reason: '仍在会话中');
    expect(
      engine.scheduleLog.where((e) => e.key == 'tick_count'),
      hasLength(8),
      reason: '两遍预备各 4 声',
    );

    // 遍 2 中关循环:本遍曲末回闲,不再续。
    await tester.ensureVisible(find.byKey(const Key('practice-loop')));
    await tester.tap(find.byKey(const Key('practice-loop')));
    await tester.pump();
    await advanceAndPump(tester, 14000); // 遍 2 曲长 12s+1s
    expect(find.byKey(const Key('practice-start')), findsOneWidget, reason: '循环关:曲末回闲');
    final count = engine.scheduleLog.length;
    await advanceAndPump(tester, 2000);
    expect(engine.scheduleLog, hasLength(count), reason: '回闲后不再调度');
  });

}
