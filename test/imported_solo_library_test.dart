import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/import/score_ir.dart';
import 'package:ukeflow/data/chart_providers.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/data/settings_dao.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';
import 'helpers/score_ir_fixtures.dart';

/// 工单 43 曲库数据面:导入独奏谱的读出管线与曲库合并。
/// Ready/Broken 逐行降级、libraryProvider 合流(内置组合+导入尾随)、
/// 隐藏集过滤(设置集合模式)。真内存库,非 widget 测试不走
/// closeStreamsSynchronously(仓库纪律)。
void main() {
  // libraryProvider 合流要读内置指弹目录(资产经 rootBundle),先起绑定。
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  /// 合法源 JSON(工单 42 夹具的最小可物化源)。
  final validSource = jsonEncode(validTinyIr().toJson());

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        chordLibraryFixtureOverride(),
        // 内置弹唱谱 fixture 化(真资产要全量和弦库;本组测试不消费它,
        // 只需曲库合流不炸——chart_visibility_test 同款)。
        builtinChartsFixtureOverride([
          (id: 'test-chart-a', chart: practiceFixtureChart),
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
    // 裸读首帧永远不来。挂常驻听众保持存活(生产里曲库页 watch)。
    container.listen(importedSoloChartsProvider, (_, _) {});
    container.listen(hiddenImportedSolosProvider, (_, _) {});
    container.listen(libraryProvider, (_, _) {});
  });

  /// 轮询到 [test] 为真:drift 流推送与读取存在竞速,.future 落地态读
  /// 当前帧而非下一帧,以空转让步消除(chart_visibility_test 同款)。
  Future<void> pollUntil(bool Function() test, String what) async {
    for (var i = 0; i < 100; i++) {
      if (test()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('轮询超时:$what');
  }

  Future<ImportedSoloEntry> addAndWait(String title, String sourceJson) async {
    final id = await db.importedSoloChartsDao.add(
      title: title,
      sourceJson: sourceJson,
      schemaVersion: scoreIrSchemaVersion,
      reviewedAt: '2026-10-26T10:00:00.000',
    );
    await pollUntil(
      () => container
          .read(importedSoloChartsProvider)
          .value
          ?.any((e) => e.id == id) ??
          false,
      '导入独奏谱流未落地:$title',
    );
    return container
        .read(importedSoloChartsProvider)
        .value!
        .singleWhere((e) => e.id == id);
  }

  group('读出管线(解码→解析→校验→物化,逐行降级)', () {
    test('合法源 → Ready:弹练三源齐备,展示名以入库名为准', () async {
      final entry = await addAndWait('入库名', validSource) as ReadyImportedSolo;

      expect(entry.title, '入库名');
      expect(entry.def.id, 'test-tiny-solo', reason: 'def.id 照录识谱源');
      expect(entry.def.title, '入库名');
      expect(entry.accompaniment.notes, hasLength(2));
      expect(entry.melody.notes, hasLength(3));
      expect(entry.accompaniment.title, '入库名');
      expect(entry.melody.title, '入库名');
    });

    test('坏源 → Broken:条目保留报错,合法行不受牵连', () async {
      final ok = await addAndWait('好谱', validSource);
      final bad = await addAndWait('坏谱', '{bad') as BrokenImportedSolo;

      expect(ok, isA<ReadyImportedSolo>());
      expect(bad.error, isA<ScoreIrFormatException>());
      final entries = container.read(importedSoloChartsProvider).value!;
      expect(entries, hasLength(2), reason: '坏源不消失,源保留在库可重试');
      expect(entries.map((e) => e.title), ['好谱', '坏谱']);
    });

    test('校验阻塞(不支持记号)同样降级 Broken', () async {
      final blocked = jsonEncode(tinyScoreIr().toJson());
      final entry = await addAndWait('未消解', blocked);
      expect(entry, isA<BrokenImportedSolo>());
    });
  });

  group('libraryProvider 合流与隐藏过滤', () {
    test('导入独奏谱入列(含 Broken),与内置组合并列', () async {
      await addAndWait('好谱', validSource);
      await addAndWait('坏谱', '{bad');

      final library = await container.read(libraryProvider.future);
      expect(library.importedSolos, hasLength(2));
      expect(
        library.importedSolos.map((e) => e.title),
        ['好谱', '坏谱'],
        reason: '内置组合在独奏谱类目自成一段,导入谱尾随其后',
      );
    });

    Future<void> setHiddenImported(String raw) async {
      final want = parseHiddenIds(raw);
      await db.settingsDao.setString(SettingsKeys.hiddenImportedSoloIds, raw);
      await pollUntil(
        () => setEquals(
          container.read(hiddenImportedSolosProvider).value,
          want,
        ),
        '隐藏集流未落地:$raw',
      );
    }

    test('隐藏集内的导入独奏谱出列,恢复后回流', () async {
      final entry = await addAndWait('好谱', validSource) as ReadyImportedSolo;

      await setHiddenImported('${entry.id}');
      var library = await container.read(libraryProvider.future);
      expect(library.importedSolos, isEmpty);

      await container
          .read(importedSoloVisibilityProvider)
          .restore(entry.id);
      await pollUntil(
        () => !container
            .read(hiddenImportedSolosProvider)
            .value!
            .contains('${entry.id}'),
        '恢复集移除未落地',
      );
      library = await container.read(libraryProvider.future);
      expect(library.importedSolos.single.title, '好谱');
    });

    test('隐藏集写口:hide 落行,重复 hide 幂等免写', () async {
      final visibility = container.read(importedSoloVisibilityProvider);
      await visibility.hide(7);
      expect(
        await db.settingsDao.getString(SettingsKeys.hiddenImportedSoloIds),
        '7',
      );
      await visibility.hide(7);
      expect(
        await db.settingsDao.getString(SettingsKeys.hiddenImportedSoloIds),
        '7',
        reason: '二次 hide 不改写(集内已含)',
      );
    });

    test('导入独奏谱隐藏集与内置谱集合互不串键', () async {
      await container.read(importedSoloVisibilityProvider).hide(3);
      await db.settingsDao.setString(SettingsKeys.hiddenBuiltinTabs, 'x');
      expect(
        await db.settingsDao.getString(SettingsKeys.hiddenImportedSoloIds),
        '3',
      );
      expect(
        await db.settingsDao.getString(SettingsKeys.hiddenBuiltinTabs),
        'x',
      );
    });
  });
}
