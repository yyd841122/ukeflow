import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/backup/backup_doc.dart';
import 'package:ukeflow/core/model/checkin.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/data/settings_dao.dart';
import 'package:ukeflow/features/settings/backup_flow.dart';
import 'package:ukeflow/features/settings/settings_page.dart';

/// 工单 21 设置页备份卡(导出/导入)UI 缝:flow 注入(测试不碰平台
/// 通道),导入确认对话框(导入即覆盖,明示不可撤销)与结果反馈;
/// 落库后设置行内值刷新。全链路落库面由 backup_service_test 保证。
void main() {
  late AppDatabase db;

  BackupFlow fakeFlow({
    Future<Uint8List?> Function()? pick,
    Future<BackupSaveOutcome> Function(String, Uint8List)? save,
  }) => BackupFlow(
    pick: pick ??
        () async => throw StateError('测试未预期选文件'),
    save: save ?? (name, bytes) async => const BackupSaved(),
  );

  /// 种子:「另一台设备」的旧数据——A4=440、一条打卡、一首谱。
  Future<void> seedOld() async {
    await db.settingsDao.setInt(SettingsKeys.referenceA4, 440);
    await db.checkInsDao.checkIn(
      day: 1,
      kind: CheckInKind.completed,
      checkedOnDay: 20650,
    );
    await db.customChartsDao.add(title: 'Beat It', source: '{title: Beat It}');
  }

  /// 备份内容:来自「旧手机」——A4=432、BPM=96、无打卡、一首「小草」。
  Uint8List backupBytes() => Uint8List.fromList(
    utf8.encode(
      jsonEncode(
        BackupDoc(
          settings: const {'reference_a4': '432', 'default_bpm': '96'},
          checkIns: const [],
          customCharts: const [
            BackupCustomChart(id: 1, title: '小草', source: '[C]没有花香'),
          ],
          imageCharts: const [],
        ).toJsonMap(),
      ),
    ),
  );

  Future<void> pumpPage(WidgetTester tester, {BackupFlow? flow}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: Scaffold(body: SettingsPage(backupFlow: flow))),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    // 工单 32 起设置页订阅隐藏集流:widget 测试走 closeStreamsSynchronously
    // 关库纪律(见 settings_page_test 同批注释)。
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
  });

  testWidgets('备份卡:标题与导出/导入两钮在', (tester) async {
    await pumpPage(tester);

    expect(find.text('备份与恢复'), findsOneWidget);
    expect(find.text('导出备份'), findsOneWidget);
    expect(find.text('导入备份'), findsOneWidget);
  });

  testWidgets('导出:save 缝(系统保存框)收到含全量数据的 JSON,给成功反馈', (
    tester,
  ) async {
    await seedOld();
    String? exportedJson;
    await pumpPage(
      tester,
      flow: fakeFlow(
        save: (name, bytes) async {
          exportedJson = utf8.decode(bytes);
          return const BackupSaved();
        },
      ),
    );

    await tester.ensureVisible(find.text('导出备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出备份'));
    await tester.pumpAndSettle();

    expect(exportedJson, isNotNull);
    expect(exportedJson, contains('Beat It'));
    expect(find.textContaining('备份已导出'), findsOneWidget);
  });

  testWidgets('导入全链路:确认对话框明示覆盖→确认→库换成备份内容,设置行内值刷新', (
    tester,
  ) async {
    await seedOld();
    await pumpPage(
      tester,
      flow: fakeFlow(pick: () async => backupBytes()),
    );

    await tester.ensureVisible(find.text('导入备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入备份'));
    await tester.pumpAndSettle();
    // 确认对话框:覆盖警示与不可撤销都在明面上。
    expect(find.textContaining('覆盖'), findsWidgets);
    await tester.tap(find.text('覆盖导入'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已导入'), findsOneWidget);
    // 设置行内值跟着备份走(重读落库值,不是停留旧值)。
    expect(
      tester.widget<Text>(find.byKey(const Key('a4-value'))).data,
      '432',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('default-bpm-value'))).data,
      '96',
    );
    // 库面:旧打卡清零、谱换成备份里的。
    expect(await db.checkInsDao.getAll(), isEmpty);
    final charts = await db.customChartsDao.getAll();
    expect(charts.single.title, '小草');
  });

  testWidgets('确认对话框取消:库原样', (tester) async {
    await seedOld();
    await pumpPage(
      tester,
      flow: fakeFlow(pick: () async => backupBytes()),
    );

    await tester.ensureVisible(find.text('导入备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect((await db.checkInsDao.getAll()), hasLength(1));
    expect((await db.customChartsDao.getAll()).single.title, 'Beat It');
  });

  testWidgets('坏文件:可读错误反馈,库原样', (tester) async {
    await seedOld();
    await pumpPage(
      tester,
      flow: fakeFlow(
        pick: () async => Uint8List.fromList(utf8.encode('这不是 JSON{{{')),
      ),
    );

    await tester.ensureVisible(find.text('导入备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入备份'));
    await tester.pumpAndSettle();

    expect(find.textContaining('JSON'), findsOneWidget);
    expect((await db.checkInsDao.getAll()), hasLength(1));
    // 坏文件不进确认对话框(没得恢复,谈不上确认)。
    expect(find.text('覆盖导入'), findsNothing);
  });

  testWidgets('导出:用户在保存框取消,静默', (tester) async {
    await pumpPage(
      tester,
      flow: fakeFlow(save: (name, bytes) async => const BackupSaveCancelled()),
    );

    await tester.ensureVisible(find.text('导出备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出备份'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已导出'), findsNothing);
    expect(find.textContaining('失败'), findsNothing);
  });

  testWidgets('导出:失败给可读反馈', (tester) async {
    await pumpPage(
      tester,
      flow: fakeFlow(
        save: (name, bytes) async => const BackupSaveFailed('导出没成功——请再试一次'),
      ),
    );

    await tester.ensureVisible(find.text('导出备份'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出备份'));
    await tester.pumpAndSettle();

    expect(find.text('导出没成功——请再试一次'), findsOneWidget);
  });
}
