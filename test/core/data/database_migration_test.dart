import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:ukeflow/data/database.dart';

/// 票05 schema v6→v7 迁移: ImportedSoloCharts 加 sourceHtml 列。
/// 用真 SQLite 文件手工建 v6 形状(无该列)旧行,user_version=6,再开
/// AppDatabase 触发 onUpgrade——升级后旧行保留、新列可写读。
/// (sqlite3 包经 drift_native 传递在依赖图内,dev_dependencies 显式钉住
/// 仅为测试直开旧库。)
void main() {
  late Directory tmp;
  late String dbPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ukeflow-mig-test');
    dbPath = '${tmp.path}/ukeflow.sqlite';
    addTearDown(() async => tmp.delete(recursive: true));
  });

  test('v6→v7:旧行保留,新列可写读', () async {
    // 手工建 v6 形状(源 schemaVersion 6 的表,无 source_html)+ 一行。
    // created_at/updated_at = drift 默认 unix 时间戳整数。
    final raw = sqlite3.open(dbPath);
    raw.execute('''
      CREATE TABLE IF NOT EXISTS imported_solo_charts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        schema_version INTEGER NOT NULL,
        source_json TEXT NOT NULL,
        content_sha TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        reviewed_at TEXT NULL
      );
    ''');
    raw.execute('PRAGMA user_version = 6');
    raw.execute("INSERT INTO imported_solo_charts "
        "(title, schema_version, source_json, content_sha, created_at, "
        "updated_at, reviewed_at) VALUES ('旧谱', 1, '{}', 'abc', "
        "1700000000000, 1700000000000, NULL)");
    raw.close();

    final db = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(db.close);

    // 升级后:旧行保留且新列可空。
    final oldRows = await db.importedSoloChartsDao.getAll();
    expect(oldRows, hasLength(1));
    expect(oldRows.single.title, '旧谱');
    expect(oldRows.single.sourceHtml, isNull);

    // 新列可写读(带原谱入库)。
    await db.importedSoloChartsDao.add(
      title: '带原谱',
      sourceJson: '{"id":"x"}',
      schemaVersion: 1,
      sourceHtml: '<html>原谱</html>',
    );
    final rows = await db.importedSoloChartsDao.getAll();
    final added = rows.where((r) => r.title == '带原谱').single;
    expect(added.sourceHtml, '<html>原谱</html>');

    // 票06:真删除(removeAt)整行移除,不可恢复(与隐藏不同语义)。
    final removed = await db.importedSoloChartsDao.removeAt(added.id);
    expect(removed, 1);
    expect(
      (await db.importedSoloChartsDao.getAll())
          .where((r) => r.title == '带原谱'),
      isEmpty,
    );
  });
}
