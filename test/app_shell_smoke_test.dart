import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/app.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';

import 'helpers/chord_fixtures.dart';

void main() {
  // 每个用例各建一个 ProviderScope，各自创建并关闭 AppDatabase；关闭是异步的，
  // 下一个用例建库时会撞上 drift「重复建库」调试启发式误报。测试用例之间没有
  // 共享 executor 的竞态，按 drift 给出的口径关掉该警告。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // 工单 02 起和弦页启动即加载和弦资产：注入 fixture 数据替代（见 helper 注释）。
  Widget app() => ProviderScope(
    overrides: [chordLibraryFixtureOverride()],
    child: const UkeFlowApp(),
  );
  Finder navLabel(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  // 工单 01 验收：App 启动渲染出导航壳。
  testWidgets('启动渲染五页签导航壳，初始落在调音器', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['调音器', '和弦', '跟练', '路径', '曲库']) {
      expect(navLabel(label), findsOneWidget, reason: '页签 $label 应存在');
    }
    // 当前页（调音器）= 页签 label + 页面标题各一份；未切到的页只出现在页签上。
    expect(find.text('调音器'), findsNWidgets(2));
    expect(find.text('曲库'), findsOneWidget);
  });

  testWidgets('点击页签可在五个页面间切换', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 页面标记 = 各页内独有的文本（占位页标题 / 和弦库分组头，工单 02 起和弦页为真页面）。
    const pageMarkers = {
      '调音器': '此页由后续工单实现',
      '和弦': '常用',
      '跟练': '此页由后续工单实现',
      '路径': '此页由后续工单实现',
      '曲库': '此页由后续工单实现',
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

  testWidgets('跟练页的节拍器入口可直达节拍器页(假引擎)', (tester) async {
    final engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chordLibraryFixtureOverride(),
          audioEngineProvider.overrideWithValue(engine),
        ],
        child: const UkeFlowApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(navLabel('跟练'));
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

  testWidgets('跟练页的节奏型训练入口可直达训练页(假引擎)', (tester) async {
    final engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chordLibraryFixtureOverride(),
          audioEngineProvider.overrideWithValue(engine),
        ],
        child: const UkeFlowApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(navLabel('跟练'));
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
