import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/tuner/tuner_recorder.dart';
import 'package:ukeflow/data/settings_providers.dart';
import 'package:ukeflow/features/tuner/tuner_page.dart';

import 'tuner_controller_test.dart';

/// 调音器正式页(工单 19):引擎与录音器一律注入假件;读数链路以合成
/// 正弦过真 YIN(复用控制器测试的 FakeRecorder/sineChunks)。
void main() {
  late FakeRecorder recorder;
  late FakeAudioEngine engine;

  Future<void> pumpPage(WidgetTester tester, {double? a4}) async {
    recorder = FakeRecorder();
    engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEngineProvider.overrideWithValue(engine),
          tunerRecorderProvider.overrideWithValue(recorder),
          if (a4 != null) referenceA4Provider.overrideWithValue(a4),
        ],
        child: const MaterialApp(home: Scaffold(body: TunerPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 逐帧推正弦,帧距越过 60ms 检测节流(fake zone 由 pump 驱动)。
  Future<void> pluckTone(WidgetTester tester, double hz) async {
    for (final chunk in sineChunks(hz)) {
      recorder.controller.add(chunk);
      await tester.pump(const Duration(milliseconds: 70));
    }
  }

  /// 目标行/试音行各有 GCEA 大字,行内定位一律经行 key 限定。
  Finder targetLabel(String label) => find.descendant(
    of: find.byKey(const Key('target-row')),
    matching: find.text(label),
  );

  Finder pluckLabel(String label) => find.descendant(
    of: find.byKey(const Key('pluck-row')),
    matching: find.text(label),
  );

  testWidgets('四弦目标钮可选,选中态随点切换', (tester) async {
    await pumpPage(tester);

    // 默认目标 = G(选中态 primaryContainer);点 A 后选中迁移。
    final selectedBefore = tester
        .widgetList<FilledButton>(
          find.descendant(
            of: find.byKey(const Key('target-row')),
            matching: find.byType(FilledButton),
          ),
        )
        .toList();
    expect(selectedBefore, hasLength(4));
    expect(
      selectedBefore[0].style?.backgroundColor,
      isNotNull,
      reason: '默认 G 弦为选中样式',
    );

    await tester.tap(targetLabel('A'));
    await tester.pump();
    final after = tester
        .widgetList<FilledButton>(
          find.descendant(
            of: find.byKey(const Key('target-row')),
            matching: find.byType(FilledButton),
          ),
        )
        .toList();
    expect(
      after[3].style?.backgroundColor,
      selectedBefore[0].style?.backgroundColor,
      reason: 'A 弦获得原 G 弦的选中底色',
    );
  });

  testWidgets('开始后拾音:440Hz 显示 A4,选 A 弦出已调准', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('开始调音'));
    await tester.pump();
    expect(recorder.startStreamCalls, 1, reason: '开始即开麦');

    await pluckTone(tester, 440.0);
    expect(find.byKey(const Key('note-name')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('note-name'))).data, 'A4');

    // 目标切到 A 弦:0 偏差 → 已调准。
    await tester.tap(targetLabel('A'));
    await tester.pump();
    expect(find.byKey(const Key('in-tune')), findsOneWidget);
  });

  testWidgets('权限拒绝:引导态可见,可重试;重试通过后正常拾音', (tester) async {
    await pumpPage(tester);
    recorder.permissionGranted = false;

    await tester.tap(find.text('开始调音'));
    await tester.pumpAndSettle();
    expect(find.textContaining('麦克风权限'), findsWidgets, reason: '引导卡指路');
    expect(recorder.startStreamCalls, 0, reason: '无权限不开麦');

    recorder.permissionGranted = true;
    await tester.tap(find.text('重试'));
    await tester.pump();
    await pluckTone(tester, 440.0);
    expect(find.text('A4'), findsWidgets);
  });

  testWidgets('停止:退麦清读数,音名回落占位', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('开始调音'));
    await tester.pump();
    await pluckTone(tester, 440.0);
    expect(tester.widget<Text>(find.byKey(const Key('note-name'))).data, 'A4');

    await tester.tap(find.text('停止'));
    await tester.pumpAndSettle();
    expect(recorder.stopCalls, 1);
    expect(
      tester.widget<Text>(find.byKey(const Key('note-name'))).data,
      isNot('A4'),
    );
  });

  testWidgets('空弦试音仍在:点弦名拨响标准音', (tester) async {
    await pumpPage(tester);
    await tester.tap(pluckLabel('G'));
    await tester.pumpAndSettle();
    expect(engine.loadedKeys, hasLength(1));
    expect(engine.loadedKeys.single, startsWith('pluck_391.99'));
  });

  testWidgets('A4=432(工单 20 设置):目标频率/判准/试音/音名同源换 432 系', (tester) async {
    await pumpPage(tester, a4: 432.0);

    // 目标行 Hz 标注换 432 系:G 弦 384.87 → 385(其余弦同步换,不逐个钉)。
    expect(find.text('385Hz'), findsOneWidget, reason: '目标频率随 A4 换算');

    // 空弦试音同源:拨 G 响 432 系标准音。
    await tester.tap(pluckLabel('G'));
    await tester.pumpAndSettle();
    expect(
      engine.loadedKeys.single,
      startsWith('pluck_384.86'),
      reason: '试音音源与目标同源',
    );

    // 判准同源:432 系调准的 G 弦音(384.87Hz)过 ±5¢ 判准;读数音名按
    // 432 基准标注为 G4(旧 440 系下此音距 G 目标 -31¢,不得亮已调准)。
    await tester.tap(find.text('开始调音'));
    await tester.pump();
    await pluckTone(tester, 384.87);
    expect(tester.widget<Text>(find.byKey(const Key('note-name'))).data, 'G4');
    expect(
      find.byKey(const Key('in-tune')),
      findsOneWidget,
      reason: '432 系调准音在 432 目标下应判准',
    );
  });

  testWidgets('App 退后台即停麦(隐私:拾音只在页可见时进行)', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('开始调音'));
    await tester.pump();
    expect(recorder.startStreamCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(recorder.stopCalls, 1, reason: '退后台即停');

    // 回前台不自动续拾音:重开是显式动作。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(recorder.startStreamCalls, 1);
  });

  testWidgets('手机宽度(360dp)下目标行与试音行各四钮单行不溢出', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await pumpPage(tester);
    expect(tester.takeException(), isNull);
  });
}
