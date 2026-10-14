import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/features/play/play_page.dart';

/// 跟练页签(工单 15 起瘦身):练琴工具入口(节拍器/节奏型训练)。
/// 曲目列表已归曲库页(「同一列表」),点曲直达跟练在彼处验收。
void main() {
  Future<void> pumpTab(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(FakeAudioEngine())],
        child: const MaterialApp(home: PlayPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('工具入口齐全:节拍器与节奏型训练', (tester) async {
    await pumpTab(tester);

    expect(find.text('节拍器'), findsOneWidget);
    expect(find.text('节奏型训练'), findsOneWidget);
    // 曲库内容不再在此页:曲目列表唯一家是曲库页。
    expect(find.text('内置曲库'), findsNothing);
    expect(find.text('指弹曲'), findsNothing);
  });

  testWidgets('窄屏(360dp)不溢出', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await pumpTab(tester);
    expect(tester.takeException(), isNull);
  });
}
