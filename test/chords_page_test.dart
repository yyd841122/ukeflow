import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/chord_library.dart';
import 'package:ukeflow/features/chords/chord_diagram.dart';
import 'package:ukeflow/features/chords/chords_page.dart';

import 'helpers/chord_fixtures.dart';

/// 工单 02 seam 3：和弦库页 —— 分组浏览、搜索直达、详情导航。
/// fixture 与 provider 覆盖见 helpers/chord_fixtures.dart。
Widget _app() => ProviderScope(
  overrides: [chordLibraryFixtureOverride()],
  child: const MaterialApp(home: Scaffold(body: ChordsPage())),
);

Widget _errorApp() => ProviderScope(
  overrides: [
    chordLibraryProvider.overrideWith(
      (ref) async => throw ChordDataError('和弦 Bx7 第 0 个指法：品位越界 9'),
    ),
  ],
  child: const MaterialApp(home: Scaffold(body: ChordsPage())),
);

void main() {
  testWidgets('常用分组置顶渲染，字母分组含各和弦瓦片', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('常用'), findsOneWidget);
    // Am、Bm 属于常用套件：瓦片含指法小图。
    expect(find.byType(ChordTile), findsWidgets);
    expect(find.text('Am'), findsOneWidget);
    expect(find.text('Bm'), findsOneWidget);
  });

  testWidgets('搜索"g7"只留 G7，搜索无结果有提示', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'g7');
    await tester.pumpAndSettle();
    expect(find.text('G7'), findsOneWidget);
    expect(find.text('Am'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zz');
    await tester.pumpAndSettle();
    expect(find.textContaining('没有匹配'), findsOneWidget);
  });

  testWidgets('点瓦片进详情：标题/指法图/按法要点/常见错误齐全', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Am'));
    await tester.pumpAndSettle();

    expect(find.text('Am'), findsWidgets); // AppBar 标题 + 详情内容
    expect(find.byType(ChordDiagram), findsWidgets);
    expect(find.text('按法要点'), findsOneWidget);
    expect(find.text('常见错误'), findsOneWidget);
    // 详情默认展示主指法（2000）。
    final diagram =
        find.byType(ChordDiagram).evaluate().first.widget as ChordDiagram;
    expect(diagram.fingering.frets, [2, 0, 0, 0]);
  });

  testWidgets('多指法和弦可在按法间切换', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Am'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按法 2'));
    await tester.pumpAndSettle();

    final diagram =
        find.byType(ChordDiagram).evaluate().first.widget as ChordDiagram;
    expect(diagram.fingering.frets, [2, 4, 4, 3]);
  });

  testWidgets('坏数据加载失败时页面可见报错', (tester) async {
    await tester.pumpWidget(_errorApp());
    await tester.pump(); // 第一帧：AsyncLoading
    await tester.pump(); // 第二帧：future reject 后渲染 AsyncError

    expect(find.textContaining('和弦库加载失败'), findsOneWidget);
    expect(find.textContaining('品位越界'), findsOneWidget);
  });
}
