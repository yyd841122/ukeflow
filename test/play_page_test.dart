import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/features/play/chart_meta.dart';
import 'package:ukeflow/features/play/play_page.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';

/// 跟练页签:内置曲库列表 + 节拍器/节奏型训练入口(工单 09 迁移保留)。
/// 曲库注入测试谱,不碰真资产;引擎一律 FakeAudioEngine。
void main() {
  late FakeAudioEngine engine;

  Future<void> pumpTab(WidgetTester tester) async {
    engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEngineProvider.overrideWithValue(engine),
          chordLibraryFixtureOverride(),
          builtinChartsFixtureOverride([
            (id: 'test-chart-a', chart: practiceFixtureChart),
            (
              id: 'test-chart-b',
              chart: parseChart('{title: 第二首}\n{tempo: 96}\n[C]词\n'),
            ),
          ]),
        ],
        child: const MaterialApp(home: PlayPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('渲染:两首测试曲、曲名与元信息、工具入口齐全', (tester) async {
    await pumpTab(tester);

    expect(find.text('内置曲库'), findsOneWidget);
    expect(find.text('测试曲'), findsOneWidget);
    expect(find.text('测试者 · C 调 · 80 BPM'), findsOneWidget);
    expect(find.text('第二首'), findsOneWidget);
    expect(find.text('96 BPM'), findsOneWidget, reason: '无 artist/key 时只显示速度');
    expect(find.text('节拍器'), findsOneWidget);
    expect(find.text('节奏型训练'), findsOneWidget);
  });

  testWidgets('点曲进跟练页,弹回回列表', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.byKey(const Key('chart-test-chart-a')));
    await tester.pumpAndSettle();
    expect(find.text('开始跟练'), findsOneWidget, reason: '会话页空闲面板');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('内置曲库'), findsOneWidget);
  });

  testWidgets('窄屏(360dp)列表不溢出', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await pumpTab(tester);
    expect(tester.takeException(), isNull);
  });

  test('chartMetaLine:空白字段剔除,不产孤立分隔符', () {
    final chart = parseChart(
      '{title: T}\n{artist: }\n{key: }\n{tempo: 96}\n[C]词\n',
    );
    expect(chartMetaLine(chart), '96 BPM');

    expect(
      chartMetaLine(parseChart('{title: T}\n[C]词\n')),
      isNull,
      reason: '全空返回 null 而非空串',
    );
  });
}
