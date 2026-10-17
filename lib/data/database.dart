import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/model/checkin.dart';
import 'checkins_dao.dart';
import 'custom_charts_dao.dart';
import 'settings_dao.dart';

part 'database.g.dart';

/// 打卡表:一行 = 一个每日任务的打卡(GLOSSARY「打卡」)。
/// 天数是主键——路径按完成顺序推进,一天至多一条打卡。
class CheckIns extends Table {
  /// 每日任务天数(1..30)。
  IntColumn get day => integer()();

  /// 完成/补卡(种类判定是域规则,见 core/model/checkin.dart)。
  IntColumn get kind => intEnum<CheckInKind>()();

  /// 打卡发生的本地日历日(epoch 天数):连续天数按它算;
  /// 补卡时它就是「补练日期」(spec 故事 36)。
  IntColumn get checkedOnDay => integer()();

  @override
  Set<Column> get primaryKey => {day};
}

/// 自建谱表(工单 15,GLOSSARY「自建谱」):一行 = 一首导入/录入的谱。
/// 存 ChordPro 源文本(唯一真源),读出再过解析校验层
/// (core/chart/custom_charts.dart)——入库时已验(工单 16),读出再验
/// 是不信任存储的最后一道闸。
class CustomCharts extends Table {
  /// 自增主键:入库序即曲库展示序,亦是曲目稳定标识。
  IntColumn get id => integer().autoIncrement()();

  /// 入库时的命名(工单 16 命名入库)——展示名以它为准,
  /// 可与源文本内嵌的 {title} 不同。
  TextColumn get title => text()();

  /// ChordPro 源文本全文。
  TextColumn get source => text()();
}

/// UkeFlow 本地数据库(drift/SQLite)。
/// 加表时 schemaVersion 递增并写迁移。
@DriftDatabase(
  tables: [CheckIns, CustomCharts, Settings],
  daos: [CheckInsDao, CustomChartsDao, SettingsDao],
)
class AppDatabase extends _$AppDatabase {
  /// 默认连接设备上的 ukeflow.sqlite;测试注入内存执行器。
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'ukeflow'));

  @override
  int get schemaVersion => 4;

  // v1 前期 schema 只加不改:建库与升级都 createAll(生成 IF NOT EXISTS,幂等),
  // 后续工单加表只需建表 + 递增 schemaVersion,升级安装也能拿到新表;
  // 出现破坏性变更时再替换为专门的迁移步骤。
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) => m.createAll(),
  );
}
