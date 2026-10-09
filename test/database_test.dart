import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/database.dart';

void main() {
  // 工单 01 验收：drift 空库可用——能打开、能执行查询、能正常关闭。
  test('AppDatabase 空库可打开并执行查询', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final row = await db.customSelect('SELECT 1 AS ok').getSingle();
    expect(row.data['ok'], 1);
    await db.close();
  });
}
