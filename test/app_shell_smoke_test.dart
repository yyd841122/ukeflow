import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/app.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/tuner/tuner_recorder.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';

import 'helpers/chord_fixtures.dart';
import 'helpers/chart_fixtures.dart';
import 'tuner_controller_test.dart' show FakeRecorder;

void main() {
  // 每个用例各建一个 ProviderScope，各自创建并关闭 AppDatabase；关闭是异步的，
  // 下一个用例建库时会撞上 drift「重复建库」调试启发式误报。测试用例之间没有
  // 共享 executor 的竞态，按 drift 给出的口径关掉该警告。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // 工单 02 起和弦页启动即加载和弦资产：注入 fixture 数据替代（见 helper 注释）。
  // 工单 09 起加载内置曲库(工单 15 起归曲库页):同为 fixture 谱。传 engine 时一并注入假引擎。
  // 工单 14 起路径页读打卡库：内存库注入（关库纪律见 path_page_test 注释）。
  Widget app([FakeAudioEngine? engine, FakeRecorder? recorder]) {
    final db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        chordLibraryFixtureOverride(),
        builtinChartsFixtureOverride([
          (id: 'test-chart-a', chart: practiceFixtureChart),
        ]),
        if (engine != null) audioEngineProvider.overrideWithValue(engine),
        if (recorder != null) tunerRecorderProvider.overrideWithValue(recorder),
      ],
      child: const UkeFlowApp(),
    );
  }

  Finder navLabel(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  // 工单 01 验收：App 启动渲染出导航壳(工单 15 裁撤跟练页签,工单 20 增设置页签,五页签)。
  testWidgets('启动渲染五页签导航壳，初始落在调音器', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['调音器', '和弦', '路径', '曲库', '设置']) {
      expect(navLabel(label), findsOneWidget, reason: '页签 $label 应存在');
    }
    // 跟练页签不复存在:跟练是点歌后发生的活动,入口在曲库页与路径页。
    expect(navLabel('跟练'), findsNothing);
    // 当前页(调音器)页签 label 一份;正式页(工单 19)不再带页内大题
    // (页题即底栏页签,与和弦/路径/曲库页一致)。
    expect(find.text('调音器'), findsOneWidget);
    expect(find.text('曲库'), findsOneWidget);
  });

  testWidgets('点击页签可在五个页面间切换', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 页面标记 = 各页内独有的文本(调音器麦克风卡题 / 和弦库分组头 /
    // 路径头 / 曲库工具行,工单 15 起曲库页为真列表页兼练琴工具家;
    // 设置页 A4 行卡题,工单 20)。
    const pageMarkers = {
      '调音器': '麦克风调音',
      '和弦': '常用',
      '路径': '总进度',
      '曲库': '节拍器',
      '设置': 'A4 参考音',
    };
    for (final entry in pageMarkers.entries) {
      await tester.tap(navLabel(entry.key));
      await tester.pumpAndSettle();
      expect(
        find.text(entry.value),
        findsWidgets,
        reason: '点 ${entry.key} 后应显示其页面',
      );
    }
  });

  testWidgets('调音器拾音中切走页签即停麦(IndexedStack 保活不 dispose)', (tester) async {
    final recorder = FakeRecorder();
    await tester.pumpWidget(app(FakeAudioEngine(), recorder));
    await tester.pumpAndSettle();

    await tester.tap(find.text('开始调音'));
    await tester.pump();
    expect(recorder.startStreamCalls, 1);

    await tester.tap(navLabel('和弦'));
    await tester.pumpAndSettle();
    expect(recorder.stopCalls, 1, reason: '切走即停,拾音只在调音器页可见时进行');

    // 切回调音器页不自动续:重开是显式动作。
    await tester.tap(navLabel('调音器'));
    await tester.pumpAndSettle();
    expect(recorder.startStreamCalls, 1);
  });

  testWidgets('曲库页的节拍器入口可直达节拍器页(假引擎)', (tester) async {
    final engine = FakeAudioEngine();
    await tester.pumpWidget(app(engine));
    await tester.pumpAndSettle();

    await tester.tap(navLabel('曲库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('节拍器'));
    await tester.pumpAndSettle();
    expect(find.text('BPM'), findsOneWidget);
    expect(find.text('引擎就绪'), findsOneWidget);
    expect(engine.loadedKeys, containsAll(['tick_strong', 'tick_weak']));

    // 弹回:页面卸载即停,不残留定时器。
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('BPM'), findsNothing);
  });

  testWidgets('曲库页的节奏型训练入口可直达训练页(假引擎)', (tester) async {
    final engine = FakeAudioEngine();
    await tester.pumpWidget(app(engine));
    await tester.pumpAndSettle();

    await tester.tap(navLabel('曲库'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('节奏型训练'));
    await tester.pumpAndSettle();
    expect(find.text('节奏型训练'), findsWidgets, reason: '页标题与入口并存');
    expect(find.text('引擎就绪'), findsOneWidget);
    expect(engine.loadedKeys, containsAll(['tick_strong', 'tick_weak']));

    // 弹回:页面卸载即停,不残留定时器。
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rhythm-toggle')), findsNothing);
  });
}
