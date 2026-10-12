import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/data/chord_library.dart';
import 'package:ukeflow/features/chords/chord_detail_page.dart';

import 'helpers/chord_fixtures.dart';

/// 工单 05 seam 3:和弦详情页「试听」——点即按当前指法错峰拨响。
/// 引擎一律注入 FakeAudioEngine;和弦取自小型 fixture 库。
void main() {
  late FakeAudioEngine engine;

  Chord chordOf(String label) =>
      uiFixtureLibrary.chords.singleWhere((c) => c.label == label);

  Future<void> pumpPage(WidgetTester tester, Chord chord) async {
    engine = FakeAudioEngine()..now = const Duration(milliseconds: 700);
    // 页签页由导航壳的 Scaffold 承载(SnackBar 落点),测试同构包裹。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          home: Scaffold(body: ChordDetailPage(chord: chord)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('试听钮可见;点即按当前指法错峰拨响,空弦为标准音', (tester) async {
    await pumpPage(tester, chordOf('Am')); // 主指法 2000,fixture 无 midi 走品位换算

    expect(find.text('试听'), findsOneWidget);

    await tester.tap(find.text('试听'));
    await tester.pumpAndSettle();

    // 2000 → A4 C4 E4 A4:四声部各自占弦位时位,A4 同音只注入一份。
    expect(engine.scheduleLog, hasLength(4));
    expect(engine.scheduleLog.map((c) => c.time), [
      const Duration(milliseconds: 700),
      const Duration(milliseconds: 745),
      const Duration(milliseconds: 790),
      const Duration(milliseconds: 835),
    ]);
    expect(engine.loadedKeys, hasLength(3));
    expect(
      engine.loadedKeys,
      containsAll(<Matcher>[
        startsWith('pluck_261.62'),
        startsWith('pluck_329.62'),
      ]),
      reason: '空弦 C4/E4 按标准音拨响',
    );
    for (final call in engine.scheduleLog) {
      expect(engine.loadedKeys, contains(call.key), reason: '预定即所载');
    }
  });

  testWidgets('切换按法后试听当前按法', (tester) async {
    await pumpPage(tester, chordOf('Am'));

    await tester.tap(find.text('试听')); // 主指法 2000
    await tester.pumpAndSettle();
    await tester.tap(find.text('按法 2'));
    await tester.pumpAndSettle();
    engine.now = const Duration(seconds: 2);
    await tester.tap(find.text('试听')); // 按法 2 = 2443,四音互异
    await tester.pumpAndSettle();

    // 两次试听共 8 次预定;2443 的 A4、E4 与主指法同音应命中缓存,
    // 但 C 弦 4 品换算出的 E4 与空弦 E4 在双精度末位不同——精确串键近音高
    // 不碰撞(04 评审定案),故 6 种音源而非 5 种。
    expect(engine.scheduleLog, hasLength(8));
    expect(engine.scheduleLog.skip(4).map((c) => c.time), [
      const Duration(seconds: 2),
      const Duration(seconds: 2, milliseconds: 45),
      const Duration(seconds: 2, milliseconds: 90),
      const Duration(seconds: 2, milliseconds: 135),
    ]);
    expect(engine.loadedKeys, hasLength(6));
  });

  testWidgets('手机宽度(360dp)下四个按法 chip 一行均分,不溢出不折行', (tester) async {
    // 默认测试面 800×600 抓不到窄屏溢出;按真机 OPPO 360dp 宽重设(工单 04 教训)。
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await pumpPage(tester, chordOf('C')); // C 有 4 个按法,全库上限

    expect(tester.takeException(), isNull);
    final chips = find.byType(ChoiceChip);
    expect(chips, findsNWidgets(4));
    final rects = [
      for (var i = 0; i < 4; i++) tester.getRect(chips.at(i)),
    ];
    expect(
      rects.map((r) => r.top),
      everyElement(rects.first.top),
      reason: '四个按法同一行',
    );
    expect(
      rects.map((r) => r.width).toSet(),
      hasLength(1),
      reason: '宽度均分',
    );
  });

  testWidgets('引擎初始化失败:错误以 SnackBar 呈现,不崩页', (tester) async {
    engine = FakeAudioEngine()..failInitialization = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioEngineProvider.overrideWithValue(engine)],
        child: MaterialApp(
          home: Scaffold(body: ChordDetailPage(chord: chordOf('Am'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('试听'));
    await tester.pumpAndSettle();
    expect(find.textContaining('试听失败'), findsOneWidget);
  });
}
