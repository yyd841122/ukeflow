import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/backup/backup_doc.dart';
import 'package:ukeflow/core/model/checkin.dart';
import 'package:ukeflow/data/backup_service.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/settings_dao.dart';

/// 工单 21 库往返缝:BackupService 是纯数据变换的落库口——
/// 导出→(清数据)→导入=状态完整还原(id 保留=曲库入库序保留);
/// 坏文件 fail-closed(解析先行,库不动)。
/// 文件落盘/分享/选文件的真机链路由 UI 层承担,内存库管变换正确性。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  /// 种子一份非空数据:两打卡(含补卡)、两自建谱、一图片谱、两设置。
  Future<void> seed(AppDatabase target) async {
    await target.checkInsDao.checkIn(
      day: 1,
      kind: CheckInKind.completed,
      checkedOnDay: 20650,
    );
    await target.checkInsDao.checkIn(
      day: 3,
      kind: CheckInKind.madeUp,
      checkedOnDay: 20655,
    );
    await target.customChartsDao.add(title: 'Beat It', source: '{title: Beat It}');
    await target.customChartsDao.add(title: '小草', source: '[C]没有花香');
    await target.imageChartsDao.add(
      title: '手写谱',
      image: Uint8List.fromList([1, 2, 3, 255, 0]),
    );
    await target.settingsDao.setInt(SettingsKeys.referenceA4, 432);
    await target.settingsDao.setInt(SettingsKeys.defaultBpm, 96);
  }

  /// 状态读出面:四表当前内容(与种子/文档对表用)。
  Future<BackupDoc> readState(AppDatabase target) async {
    final settings = {
      for (final row in await target.settingsDao.getAll()) row.key: row.value,
    };
    return BackupDoc(
      settings: settings,
      checkIns: [
        for (final row in await target.checkInsDao.getAll())
          BackupCheckIn(
            day: row.day,
            kind: row.kind,
            checkedOnDay: row.checkedOnDay,
          ),
      ],
      customCharts: [
        for (final row in await target.customChartsDao.getAll())
          BackupCustomChart(id: row.id, title: row.title, source: row.source),
      ],
      imageCharts: [
        for (final row in await target.imageChartsDao.getAll())
          BackupImageChart(
            id: row.id,
            title: row.title,
            image: row.image,
          ),
      ],
    );
  }

  test('导出文档与库一致(四表全量、设置原样)', () async {
    await seed(db);
    final service = BackupService(db);

    final doc = parseBackupJson(await service.collectJson());
    final expected = await readState(db);

    expect(doc.settings, expected.settings);
    expect(doc.checkIns, expected.checkIns);
    expect(doc.customCharts, expected.customCharts);
    expect(doc.imageCharts, expected.imageCharts);
  });

  test('导出→清数据→导入:新库状态完整还原(id 保留)', () async {
    await seed(db);
    final service = BackupService(db);
    final json = await service.collectJson();
    final expected = await readState(db);

    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    await BackupService(fresh).restoreJson(json);

    expect(await readState(fresh), isNot(BackupDoc(settings: const {}, checkIns: const [], customCharts: const [], imageCharts: const [])));
    // 逐面断言:id 保留(=入库序=曲库展示序)、字节原样、设置原样。
    expect(await readState(fresh), expected);
    final charts = await fresh.customChartsDao.getAll();
    expect(charts.map((c) => c.id).toList(), [1, 2]);
    final images = await fresh.imageChartsDao.getAll();
    expect(images.single.id, 1);
    expect(images.single.image, Uint8List.fromList([1, 2, 3, 255, 0]));
  });

  test('导入即覆盖:非空库旧数据清零,换成备份状态', () async {
    final service = BackupService(db);
    await seed(db);
    final json = await service.collectJson();
    final expected = await readState(db);

    // 另一台「机器」:有自己的不同数据。
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.checkInsDao.checkIn(
      day: 2,
      kind: CheckInKind.completed,
      checkedOnDay: 20652,
    );
    await other.customChartsDao.add(title: '别的谱', source: '[Am]别的');

    await BackupService(other).restoreJson(json);

    final state = await readState(other);
    expect(state, expected);
    expect(state.checkIns.map((c) => c.day), [1, 3]); // 旧 day2 已清
    expect(state.customCharts.map((c) => c.title), ['Beat It', '小草']);
  });

  test('坏文件 fail-closed:解析失败库原样,不崩溃', () async {
    await seed(db);
    final service = BackupService(db);
    final before = await readState(db);

    expect(
      () => service.restoreJson('这不是 JSON{{{'),
      throwsA(isA<BackupFormatException>()),
    );
    // 异步抛错后状态不被事务碰过。
    await service.restoreJson(await service.collectJson()); // 库仍可用
    expect(await readState(db), before);
  });

  test('restoreJson 接受合法串:collect→restore 原库自恢复一致', () async {
    await seed(db);
    final service = BackupService(db);
    final json = await service.collectJson();
    final expected = await readState(db);

    await service.restoreJson(json);

    expect(await readState(db), expected);
  });

  test('restoreDoc:已解析文档直连落库(页面从流程层拿到 doc 后不再编码回串)', () async {
    final service = BackupService(db);
    await seed(db);
    final json = await service.collectJson();
    final expected = await readState(db);
    final doc = parseBackupJson(json);

    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await BackupService(other).restoreDoc(doc);

    expect(await readState(other), expected);
  });
}
