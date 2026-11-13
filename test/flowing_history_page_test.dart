import 'package:drift/drift.dart' hide isNull, Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/features/play/flowing_history_page.dart';

/// 票06 练习记录页:列表渲染 + 自评改即刷(内存库,closeStreamsSynchronously
/// 收流防挂起计时器)。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
  });
  tearDown(() => db.close());

  testWidgets('空库显示引导文案;有行显示记录与自评,改自评即回写', (tester) async {
    final container = ProviderContainer(
      overrides: [
        flowingSessionsDaoProvider.overrideWithValue(db.flowingSessionsDao),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FlowingHistoryPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有练习记录'), findsOneWidget);

    final id = await db.flowingSessionsDao.start(
        DateTime(2026, 11, 13, 19, 5).millisecondsSinceEpoch);
    await db.flowingSessionsDao.saveSnapshot(
      id: id,
      durationMs: 192000,
      endPositionSeconds: 64.4,
      speed: 0.75,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('3分12秒'), findsOneWidget);
    expect(find.textContaining('0.75倍'), findsOneWidget);
    expect(find.textContaining('位置 1:04'), findsOneWidget);
    expect(find.text('未自评'), findsOneWidget);

    await tester.tap(find.text('未自评'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('比较顺').last);
    await tester.pumpAndSettle();
    final row = (await db.flowingSessionsDao.recent()).single;
    expect(row.rating, 3);
    expect(find.text('比较顺'), findsOneWidget);
  });
}
