import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/backup/backup_doc.dart';
import 'database.dart';

/// 备份服务(工单 21):四表全量与单个 JSON 文档互转的落库口。
/// 纯数据变换——读出侧经各 DAO/表直查,写入侧一个事务内「清四表+插回」,
/// 事务原子性保证坏文档半途失败不落半截状态。
///
/// 冲突策略(票面已定):**导入即覆盖**——restore 先清后插,旧数据全量
/// 换成备份状态;文件带版本号(BackupDoc.formatVersion)为格式演进留门。
///
/// fail-closed 契约:解析失败([BackupFormatException])在碰库之前抛出,
/// 库原样不动;「导入坏文件给可读错误,不崩溃」由本层与编解码层共同保证。
class BackupService {
  final AppDatabase _db;

  BackupService(this._db);

  /// 四表全量导出为备份 JSON 串(版本号在文档顶层)。
  /// 四读包进一个事务:拼出一致快照,导出中途的写入不产生撕裂文档
  /// (单用户按键面几乎不可触发,结构上免费就不省)。
  Future<String> collectJson() {
    return _db.transaction(() async {
      final settings = await _db.settingsDao.getAll();
      final checkIns = await _db.checkInsDao.getAll();
      final customCharts = await _db.customChartsDao.getAll();
      final imageCharts = await _db.imageChartsDao.getAll();

      return jsonEncode(
        BackupDoc(
          settings: {for (final row in settings) row.key: row.value},
          checkIns: [
            for (final row in checkIns)
              BackupCheckIn(
                day: row.day,
                kind: row.kind,
                checkedOnDay: row.checkedOnDay,
              ),
          ],
          customCharts: [
            for (final row in customCharts)
              BackupCustomChart(
                id: row.id,
                title: row.title,
                source: row.source,
              ),
          ],
          imageCharts: [
            for (final row in imageCharts)
              BackupImageChart(id: row.id, title: row.title, image: row.image),
          ],
        ).toJsonMap(),
      );
    });
  }

  /// 导入备份 JSON 串:解析(失败库不动)→ 单事务「清四表+插回」。
  /// 自建谱/图片谱带原 id 插入——id 即入库序即曲库展示序,还原后不变。
  Future<void> restoreJson(String json) {
    return restoreDoc(parseBackupJson(json));
  }

  /// 导入已解析的备份文档(流程层选文件解析后的直连口):同一事务
  /// 「清四表+插回」,文档已在编解码层验过形。
  Future<void> restoreDoc(BackupDoc doc) async {
    await _db.transaction(() async {
      await _db.batch((batch) {
        batch.deleteAll(_db.checkIns);
        batch.deleteAll(_db.customCharts);
        batch.deleteAll(_db.imageCharts);
        batch.deleteAll(_db.settings);
      });
      await _db.batch((batch) {
        batch.insertAll(_db.checkIns, [
          for (final e in doc.checkIns)
            CheckInsCompanion.insert(
              day: Value(e.day),
              kind: e.kind,
              checkedOnDay: e.checkedOnDay,
            ),
        ]);
        batch.insertAll(_db.customCharts, [
          for (final e in doc.customCharts)
            CustomChartsCompanion.insert(
              id: Value(e.id),
              title: e.title,
              source: e.source,
            ),
        ]);
        batch.insertAll(_db.imageCharts, [
          for (final e in doc.imageCharts)
            ImageChartsCompanion.insert(
              id: Value(e.id),
              title: e.title,
              image: e.image,
            ),
        ]);
        batch.insertAll(_db.settings, [
          for (final entry in doc.settings.entries)
            SettingsCompanion.insert(key: entry.key, value: entry.value),
        ]);
      });
    });
  }
}
