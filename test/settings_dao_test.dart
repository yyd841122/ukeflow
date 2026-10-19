import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/settings_dao.dart';

/// 工单 20 设置持久化:设置 DAO 内存库测试(键值读写、覆盖、类型防御)。
/// 「设置随重启仍在」的存储面在这验证;消费方接线在 settings_providers_test。
void main() {
  late AppDatabase db;
  late SettingsDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.settingsDao;
  });
  tearDown(() async => db.close());

  test('set 后 get 回读同值', () async {
    await dao.setInt(SettingsKeys.referenceA4, 432);
    expect(await dao.getInt(SettingsKeys.referenceA4), 432);
  });

  test('未设置的键返回 null(消费方取默认值的依据)', () async {
    expect(await dao.getInt(SettingsKeys.referenceA4), isNull);
    expect(await dao.getInt(SettingsKeys.defaultBpm), isNull);
  });

  test('同键重写覆盖:key 是主键,不产生第二行', () async {
    // 重复策略声明(CODING_STANDARDS):key 主键天然防重复,覆盖写即
    // 语义;此测钉住「覆盖而非报错、不留旧行」。
    await dao.setInt(SettingsKeys.referenceA4, 440);
    await dao.setInt(SettingsKeys.referenceA4, 432);
    expect(await dao.getInt(SettingsKeys.referenceA4), 432);
    final rows = await db.select(db.settings).get();
    expect(rows, hasLength(1));
  });

  test('非整数内容的行返回 null(为后续字符串/其他类型设置留位,不炸读取)', () async {
    await db
        .into(db.settings)
        .insert(SettingsCompanion.insert(key: 'future_str', value: 'hello'));
    expect(await dao.getInt('future_str'), isNull);
  });


  // ── 工单 32:字符串设置(隐藏内置谱 id 集的存放面)──

  test('字符串 set 后 get 回读同值,重写覆盖', () async {
    expect(await dao.getString(SettingsKeys.hiddenBuiltinStrums), isNull);
    await dao.setString(SettingsKeys.hiddenBuiltinStrums, 'a,b');
    expect(await dao.getString(SettingsKeys.hiddenBuiltinStrums), 'a,b');
    await dao.setString(SettingsKeys.hiddenBuiltinStrums, 'a');
    expect(await dao.getString(SettingsKeys.hiddenBuiltinStrums), 'a');
  });

  test('watchString:写库即推送,清空(空串)也推送', () async {
    // drift distinct 流抑制与内部初值相同的 null 首帧:订阅先于写入,
    // 只断言两次写入的两帧(无行→null 的面由 parseHiddenIds 测兜)。
    final expectation = expectLater(
      dao.watchString(SettingsKeys.hiddenBuiltinStrums),
      emitsInOrder(['a', '']),
    );
    await dao.setString(SettingsKeys.hiddenBuiltinStrums, 'a');
    await dao.setString(SettingsKeys.hiddenBuiltinStrums, '');
    await expectation;
  });
}
