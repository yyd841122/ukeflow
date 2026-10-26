import 'package:drift/drift.dart';

import 'database.dart';

part 'settings_dao.g.dart';

/// 设置键(工单 20 起设置的统一存放处;新设置加键常量,勿散落字符串字面量)。
abstract final class SettingsKeys {
  /// A4 参考音 Hz(调音器消费,GLOSSARY「参考音」)。
  static const referenceA4 = 'reference_a4';

  /// 默认 BPM(节拍器初始值/跟练无 tempo 谱的回退值消费)。
  static const defaultBpm = 'default_bpm';

  /// 隐藏的内置弹唱谱 id 集,逗号并(工单 32,GLOSSARY「隐藏内置谱」)。
  static const hiddenBuiltinStrums = 'hidden_builtin_strum_ids';

  /// 隐藏的内置指弹谱 id 集(工单 32)。
  static const hiddenBuiltinTabs = 'hidden_builtin_tab_ids';

  /// 隐藏的内置图片谱 id 集(工单 32)。
  static const hiddenBuiltinImages = 'hidden_builtin_image_ids';

  /// 隐藏的导入独奏谱 id 集(工单 43):数据库行 id 十进制串,逗号并。
  static const hiddenImportedSoloIds = 'hidden_imported_solo_ids';

  /// 跟练评分的链路延迟(毫秒,可负;工单 33,GLOSSARY「延迟校准」)。
  static const scoringLatencyMs = 'scoring_latency_ms';
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

  /// 读文本设置;缺行返回 null(工单 32:隐藏集等串值键)。
  Future<String?> getString(String key) async {
    final row = await (select(
      settings,
    )..where((r) => r.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// 写文本设置(key 主键,存在即覆盖)。
  Future<void> setString(String key, String value) {
    return into(
      settings,
    ).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
  }

  /// 文本设置流:该键行增删改即推送,无行推 null(工单 32:隐藏集
  /// 变化驱动曲库页/设置页同源刷新)。
  Stream<String?> watchString(String key) {
    return (select(settings)..where((r) => r.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }

  /// 全部设置行原样读出(工单 21 备份导出:全量搬运,不筛已知键)。
  Future<List<Setting>> getAll() {
    return (select(
      settings,
    )..orderBy([(row) => OrderingTerm.asc(row.key)])).get();
  }
}
