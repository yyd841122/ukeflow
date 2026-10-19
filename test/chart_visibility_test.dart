import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/chart_providers.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/data/settings_dao.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';

/// 工单 32:内置谱隐藏/恢复(曲库删除的内置语义)。
/// 数据面在真内存库上走:可见性写入口改 settings 行 → 隐藏集流推送 →
/// libraryProvider 过滤。UI 呈现(确认框/卡片退场)在 library_page_test,
/// 恢复区在 settings_page_test。
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    // 纯 provider 测试(非 widget/FakeAsync):普通内存库即可,无需
    // closeStreamsSynchronously(仓库纪律:那笔是 widget 测试的关库口)。
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        chordLibraryFixtureOverride(),
        builtinChartsFixtureOverride([
          (id: 'test-chart-a', chart: practiceFixtureChart),
          (
            id: 'test-chart-b',
            chart: parseChart('{title: 第二首}\n{tempo: 96}\n[C]词\n'),
          ),
        ]),
      ],
    );
    // 先 dispose 容器(取消流订阅),排空一拍事件循环让取消落地,
    // 再关库——紧跟着关会撞 drift StreamQueryStore.close 的遍历竞态。
    addTearDown(() async {
      container.dispose();
      await Future<void>.delayed(Duration.zero);
      await db.close();
    });
    // Riverpod 3:无听众的 provider 即回收,流订阅随之取消——.future
    // 裸读首帧永远不来(超时假死)。挂常驻听众保持存活;生产里曲库页
    // watch 这些 provider,天然有听众,不受此影响。
    container.listen(hiddenBuiltinStrumsProvider, (_, _) {});
    container.listen(hiddenBuiltinTabsProvider, (_, _) {});
    container.listen(hiddenBuiltinImagesProvider, (_, _) {});
    container.listen(libraryProvider, (_, _) {});
  });

  group('parseHiddenIds(逗号并 id 集的存放格式)', () {
    test('缺行/空串 = 空集', () {
      expect(parseHiddenIds(null), isEmpty);
      expect(parseHiddenIds(''), isEmpty);
    });

    test('逗号并拆集,重复并集去重', () {
      expect(parseHiddenIds('a,b'), {'a', 'b'});
      expect(parseHiddenIds('a,a'), {'a'});
    });
  });

  group('BuiltinChartVisibility(隐藏/恢复的写入口)', () {
    test('hide 落 settings 行,restore 移除;两类谱各走各键', () async {
      final visibility = container.read(builtinChartVisibilityProvider);
      await visibility.hideStrum('test-chart-a');
      await visibility.hideTab('xiao-xing-xing');
      expect(
        await db.settingsDao.getString(SettingsKeys.hiddenBuiltinStrums),
        'test-chart-a',
      );
      expect(
        await db.settingsDao.getString(SettingsKeys.hiddenBuiltinTabs),
        'xiao-xing-xing',
      );

      await visibility.restoreStrum('test-chart-a');
      await visibility.restoreTab('xiao-xing-xing');
      expect(
        await db.settingsDao.getString(SettingsKeys.hiddenBuiltinStrums),
        '',
      );
      expect(
        await db.settingsDao.getString(SettingsKeys.hiddenBuiltinTabs),
        '',
      );
    });

    test('重复 hide 集不变化(幂等,免写)', () async {
      final visibility = container.read(builtinChartVisibilityProvider);
      await visibility.hideStrum('test-chart-a');
      await visibility.hideStrum('test-chart-a');
      expect(
        await db.settingsDao.getString(SettingsKeys.hiddenBuiltinStrums),
        'test-chart-a',
        reason: '二次 hide 不改写(集内已含)',
      );
    });

    test('两类谱互不串键:隐藏弹唱谱不动指弹谱集合', () async {
      final visibility = container.read(builtinChartVisibilityProvider);
      await visibility.hideStrum('test-chart-a');
      await visibility.hideTab('xiao-xing-xing');
      await visibility.restoreStrum('test-chart-a');
      expect(
        await db.settingsDao.getString(SettingsKeys.hiddenBuiltinTabs),
        'xiao-xing-xing',
      );
    });
  });

  group('libraryProvider 的隐藏过滤', () {
    /// 写隐藏行并**轮询到 provider 状态落地**:.future 在 AsyncData 态
    /// 返回当前值而非下一帧,直接读会拿到旧值,以轮询消除推送竞速。
    Future<void> setHiddenStrums(String raw) async {
      final want = parseHiddenIds(raw);
      await db.settingsDao.setString(SettingsKeys.hiddenBuiltinStrums, raw);
      for (var i = 0; i < 100; i++) {
        if (setEquals(container.read(hiddenBuiltinStrumsProvider).value, want)) {
          return;
        }
        await Future<void>.delayed(Duration.zero);
      }
      fail('隐藏集流未落地:$raw');
    }

    test('隐藏集内的内置弹唱谱出列,其余照旧', () async {
      var library = await container.read(libraryProvider.future);
      expect(library.builtinStrum.map((c) => c.id), hasLength(2));

      await setHiddenStrums('test-chart-a');
      library = await container.read(libraryProvider.future);
      expect(library.builtinStrum.map((c) => c.id), ['test-chart-b']);
    });

    test('隐藏内置指弹谱出列(真目录,不走 fixture)', () async {
      await db.settingsDao.setString(
        SettingsKeys.hiddenBuiltinTabs,
        'xiao-xing-xing',
      );
      while (true) {
        final value = container.read(hiddenBuiltinTabsProvider).value;
        if (value != null && value.contains('xiao-xing-xing')) break;
        await Future<void>.delayed(Duration.zero);
      }
      final library = await container.read(libraryProvider.future);
      expect(
        library.tab.map((t) => t.id),
        isNot(contains('xiao-xing-xing')),
      );
      expect(library.tab, isNotEmpty, reason: '只隐藏一首,其余指弹曲仍在');
    });

    test('恢复(集清空)后回流', () async {
      await setHiddenStrums('test-chart-a');
      await setHiddenStrums('');
      final library = await container.read(libraryProvider.future);
      expect(library.builtinStrum.map((c) => c.id), hasLength(2));
    });
  });
}
