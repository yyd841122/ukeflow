import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/tuner/tuner_recorder.dart';
import 'package:ukeflow/data/settings_providers.dart';
import 'package:ukeflow/features/tuner/tuner_page.dart';

import 'tuner_controller_test.dart' show FakeRecorder;

/// 空弦试音(调音器页常驻功能的回归;麦克风调音链路归
/// tuner_page_formal_test):引擎与录音器一律注入假件。
/// 页面有目标行与试音行两组 GCEA,行内定位一律经行 key 限定。
void main() {
  late FakeAudioEngine engine;
  late FakeRecorder recorder;

  Future<void> pumpPage(WidgetTester tester) async {
    engine = FakeAudioEngine();
    recorder = FakeRecorder();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEngineProvider.overrideWithValue(engine),
          tunerRecorderProvider.overrideWithValue(recorder),
          // A4 参考音走派生 provider(设置消费缝,工单 20):override 隔离,
          // 不让页面链路触到真库。
          referenceA4Provider.overrideWithValue(440.0),
        ],
        child: const MaterialApp(home: Scaffold(body: TunerPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder pluckLabel(String label) => find.descendant(
    of: find.byKey(const Key('pluck-row')),
    matching: find.text(label),
  );

  testWidgets('四根弦名可点,点即拨响对应空弦标准音', (tester) async {
    await pumpPage(tester);

    for (final label in ['G', 'C', 'E', 'A']) {
      expect(pluckLabel(label), findsOneWidget, reason: '弦钮 $label 可见');
    }
    for (final number in ['4弦', '3弦', '2弦', '1弦']) {
      expect(find.text(number), findsOneWidget, reason: '弦号 $number 可见');
    }

    await tester.tap(pluckLabel('G'));
    await tester.pumpAndSettle();
    // 键为精确频率串,这里锁前缀(音高对)与「预定即所载」一致性。
    expect(engine.loadedKeys, hasLength(1));
    expect(engine.loadedKeys.single, startsWith('pluck_391.99'));
    expect(engine.scheduleLog.single.key, engine.loadedKeys.single);

    await tester.tap(pluckLabel('A'));
    await tester.pumpAndSettle();
    expect(engine.loadedKeys, hasLength(2));
    expect(engine.scheduleLog, hasLength(2), reason: '同页反复拨响各自预定');
  });

  testWidgets('手机宽度(360dp)下试音四钮单行不溢出', (tester) async {
    // 默认测试面 800×600 逻辑像素,卡不住窄屏溢出;按真机 OPPO 360dp 宽重设。
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await pumpPage(tester);

    // 溢出会在布局期抛异常使测试失败;这里再验四钮文字都还完整渲染。
    for (final label in ['G', 'C', 'E', 'A']) {
      expect(tester.takeException(), isNull);
      expect(pluckLabel(label), findsOneWidget);
    }
  });

  testWidgets('引擎初始化失败:错误以 SnackBar 呈现,不崩页', (tester) async {
    engine = FakeAudioEngine()..failInitialization = true;
    recorder = FakeRecorder();
    // 页签页由导航壳的 Scaffold 承载(SnackBar 落点),测试同构包裹。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEngineProvider.overrideWithValue(engine),
          tunerRecorderProvider.overrideWithValue(recorder),
        ],
        child: MaterialApp(home: Scaffold(body: const TunerPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(pluckLabel('G'));
    await tester.pumpAndSettle();
    expect(find.textContaining('试音失败'), findsOneWidget);
  });
}
