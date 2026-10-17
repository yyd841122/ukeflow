import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/data/settings_dao.dart';
import 'package:ukeflow/features/settings/settings_page.dart';

/// 设置页(工单 20):两行设置(A4 参考音/默认 BPM)的渲染与写透。
/// 库一律内存注入(关库纪律见 settings_providers_test);写透经 DAO
/// 回读验证,不查库内部表。
void main() {
  late AppDatabase db;

  Future<void> pumpPage(WidgetTester tester) async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle(); // 设置异步加载落定
  }

  Finder rowValue(String keyPrefix) => find.byKey(Key('$keyPrefix-value'));

  String textOf(WidgetTester tester, String keyPrefix) =>
      tester.widget<Text>(rowValue(keyPrefix)).data!;

  testWidgets('渲染:缺省 A4=440、默认 BPM=80,两行各带单位', (tester) async {
    await pumpPage(tester);

    expect(find.text('A4 参考音'), findsOneWidget);
    expect(find.text('默认 BPM'), findsOneWidget);
    expect(textOf(tester, 'a4'), '440');
    expect(find.text('Hz'), findsOneWidget);
    expect(textOf(tester, 'default-bpm'), '80');
    expect(find.text('BPM'), findsOneWidget);
  });

  testWidgets('种子库 A4=432:载入后显示落库值(重启仍在的读出面)', (tester) async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.settingsDao.setInt(SettingsKeys.referenceA4, 432);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(textOf(tester, 'a4'), '432');
  });

  testWidgets('A4 步进:即时换值并写透落库', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('a4-plus')));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'a4'), '441');
    expect(
      await db.settingsDao.getInt(SettingsKeys.referenceA4),
      441,
      reason: '改动写透,重启后仍在这',
    );

    await tester.tap(find.byKey(const Key('a4-minus')));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'a4'), '440');
    expect(await db.settingsDao.getInt(SettingsKeys.referenceA4), 440);
  });

  testWidgets('默认 BPM 步进:即时换值并写透落库', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('default-bpm-plus')));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'default-bpm'), '81');
    expect(await db.settingsDao.getInt(SettingsKeys.defaultBpm), 81);
  });
}
