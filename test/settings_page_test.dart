import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/data/settings_dao.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';
import 'package:ukeflow/features/settings/settings_page.dart';

/// 设置页(工单 20):两行设置(A4 参考音/默认 BPM)的渲染与写透。
/// 库一律内存注入(关库纪律见 settings_providers_test);写透经 DAO
/// 回读验证,不查库内部表。
/// 工单 32 起设置页订阅隐藏集流,建库走 closeStreamsSynchronously
/// (widget 测试 drift 流关库纪律,见 MEMORY/dev-env)。
void main() {
  late AppDatabase db;

  Future<void> pumpPage(WidgetTester tester) async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle(); // 设置异步加载落定
  }

  /// 带内置谱 fixture 的 pump(隐藏区曲名解析用;Override 类型随
  /// Riverpod 3 不导出,内联展开——chord_fixtures 同款注释纪律)。
  Future<void> pumpPageWithFixture(WidgetTester tester) async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          chordLibraryFixtureOverride(),
          builtinChartsFixtureOverride([
            (id: 'test-chart-a', chart: practiceFixtureChart),
          ]),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
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
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
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

  // ── 工单 32:隐藏的内置谱管理区(曲库删除的恢复口)──

  testWidgets('无隐藏谱:管理区不出卡', (tester) async {
    await pumpPage(tester);
    expect(find.byKey(const Key('hidden-charts-card')), findsNothing);
  });

  testWidgets('隐藏区逐条呈现并恢复:恢复后行消失,settings 行同步', (tester) async {
    await pumpPageWithFixture(tester);
    await db.settingsDao.setString(SettingsKeys.hiddenBuiltinStrums, 'test-chart-a');
    await db.settingsDao.setString(SettingsKeys.hiddenBuiltinTabs, 'xiao-xing-xing');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hidden-charts-card')), findsOneWidget);
    expect(find.text('弹唱谱 · 测试曲'), findsOneWidget,
        reason: '曲名经目录解析(非裸 id)');
    expect(find.text('指弹谱 · 小星星'), findsOneWidget,
        reason: '指弹谱来自真目录常量,无需注入');

    await tester.scrollUntilVisible(
      find.byKey(const Key('restore-strum-test-chart-a')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('restore-strum-test-chart-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restore-strum-test-chart-a')));
    await tester.pumpAndSettle();
    expect(find.text('弹唱谱 · 测试曲'), findsNothing, reason: '恢复后行退场');
    expect(
      await db.settingsDao.getString(SettingsKeys.hiddenBuiltinStrums),
      '',
    );
    expect(find.text('指弹谱 · 小星星'), findsOneWidget,
        reason: '指弹谱条目不受牵连');

    await tester.scrollUntilVisible(
      find.byKey(const Key('restore-tab-xiao-xing-xing')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('restore-tab-xiao-xing-xing')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restore-tab-xiao-xing-xing')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hidden-charts-card')), findsNothing,
        reason: '集全空,管理区退场');
  });
}
