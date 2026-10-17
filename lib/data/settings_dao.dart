import 'package:drift/drift.dart';

import 'database.dart';

part 'settings_dao.g.dart';

/// 设置键(工单 20 起设置的统一存放处;新设置加键常量,勿散落字符串字面量)。
abstract final class SettingsKeys {
  /// A4 参考音 Hz(调音器消费,GLOSSARY「参考音」)。
  static const referenceA4 = 'reference_a4';

  /// 默认 BPM(节拍器初始值/跟练无 tempo 谱的回退值消费)。
  static const defaultBpm = 'default_bpm';
}

/// 设置表(工单 20):键值对,key 主键——每键至多一行,重写即覆盖
/// (CODING_STANDARDS 单行查询重复策略:key 是主键,重复不可能)。
/// 值以文本存放:整数之外的类型(字符串等后续设置)留位不迁表。
class Settings extends Table {
  /// 设置键([SettingsKeys])。
  TextColumn get key => text()();

  /// 设置值(整数以十进制串存放;读出侧按需解析,解析失败返回 null)。
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 设置数据访问(工单 20):键值存取。缺省值/钳制等域规则在
/// data/settings_providers.dart,DAO 只管存取。
@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  /// 读整数设置;缺行或内容非整数(其他类型设置的行)返回 null。
  Future<int?> getInt(String key) async {
    final row = await (select(
      settings,
    )..where((r) => r.key.equals(key))).getSingleOrNull();
    if (row == null) return null;
    return int.tryParse(row.value);
  }

  /// 写整数设置(key 主键,存在即覆盖)。
  Future<void> setInt(String key, int value) {
    return into(settings).insertOnConflictUpdate(
      SettingsCompanion.insert(key: key, value: '$value'),
    );
  }

  /// 全部设置行原样读出(工单 21 备份导出:全量搬运,不筛已知键)。
  Future<List<Setting>> getAll() {
    return (select(settings)..orderBy([(row) => OrderingTerm.asc(row.key)]))
        .get();
  }
}
