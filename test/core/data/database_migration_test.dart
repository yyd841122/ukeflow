import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:ukeflow/data/database.dart';

/// 终止线表下线迁移(ADR-0013):v9 drop image_charts(图片谱线)、
/// v10 drop imported_solo_charts(独奏谱/识谱源导入面,票64)。
/// 用真 SQLite 文件手工建 v8 形状(两表带行),user_version=8,再开
/// AppDatabase 触发 onUpgrade——升到 v10 后两表消失、其余表不受牵连。
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

  test('v8→v10:终止线两表下线,其余数据不受牵连', () async {
    // 手工建 v9 形状(两表仍在)+ 各一行 + 一行活表数据。
    final raw = sqlite3.open(dbPath);
    raw.execute('''
      CREATE TABLE IF NOT EXISTS image_charts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        image BLOB NOT NULL
      );
    ''');
    raw.execute('''
      CREATE TABLE IF NOT EXISTS imported_solo_charts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        schema_version INTEGER NOT NULL,
        source_json TEXT NOT NULL,
        content_sha TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        reviewed_at TEXT NULL,
        source_html TEXT NULL
      );
    ''');
    raw.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');
    raw.execute('PRAGMA user_version = 8');
    raw.execute("INSERT INTO image_charts (title, image) VALUES ('图片谱', x'00')");
    raw.execute("INSERT INTO imported_solo_charts "
        "(title, schema_version, source_json, content_sha, created_at, "
        "updated_at, reviewed_at, source_html) VALUES ('旧独奏', 1, '{}', "
        "'abc', 1700000000000, 1700000000000, NULL, NULL)");
    raw.execute("INSERT INTO settings (key, value) VALUES ('k', 'v')");
    raw.close();

    final db = AppDatabase(NativeDatabase(File(dbPath)));
    addTearDown(db.close);

    // 升级后:两终止线表已下线(查询报错 = 表不存在),活表数据原样。
    final tablesNow = [
      for (final row in await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get())
      row.data['name'] as String,
    ];
    expect(tablesNow, isNot(contains('image_charts')));
    expect(tablesNow, isNot(contains('imported_solo_charts')));
    expect(tablesNow, contains('settings'));
    expect(
      (await db.settingsDao.getAll()).single.value,
      'v',
      reason: '升级只下终止线表,活表行不丢',
    );
  });
}
