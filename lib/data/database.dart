import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/model/checkin.dart';
import 'checkins_dao.dart';
import 'custom_charts_dao.dart';
import 'flowing_sessions_dao.dart';
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

/// 图片谱表(工单 18):一行 = 一张从相册入库的图片谱(GLOSSARY
/// 流水谱练习会话表(票06):一行 = 一次进页练琴会话。时长只累计
/// 播放中的墙钟段(预备数拍/暂停不计,测试锁定);暂停/曲末/退页随写
/// 随存同一行(id upsert),曲末后再播新起一行(codex 同款)。
class FlowingSessions extends Table {
  /// 自增主键:会话标识,自评按 id 定点改。
  IntColumn get id => integer().autoIncrement()();

  /// 会话起始时刻(epoch ms;列表展示与排序)。
  IntColumn get startedAtMs => integer()();

  /// 实际练习时长(ms):播放中的引擎钟差值累计。
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  /// 结束位置(曲谱秒):暂停/退页时刻,曲末 = 曲长。
  RealColumn get endPositionSeconds => real().withDefault(const Constant(0))();

  /// 会话内速度(最后使用值;三档 0.5/0.75/1.0)。
  RealColumn get speed => real().withDefault(const Constant(1.0))();

  /// 自评:null 未自评 / 1 还要练 / 2 逐渐熟 / 3 比较顺(codex 三档)。
  IntColumn get rating => integer().nullable()();
}

/// UkeFlow 本地数据库(drift/SQLite)。
/// 加表时 schemaVersion 递增并写迁移。
@DriftDatabase(
  tables: [
    CheckIns,
    CustomCharts,
    Settings,
    FlowingSessions,
  ],
  daos: [
    CheckInsDao,
    CustomChartsDao,
    SettingsDao,
    FlowingSessionsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 默认连接设备上的 ukeflow.sqlite;测试注入内存执行器。
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'ukeflow'));

  @override
  int get schemaVersion => 10;

  // v1 前期 schema 只加不改:建库与升级都 createAll(生成 IF NOT EXISTS,幂等),
  // 后续工单加表只需建表 + 递增 schemaVersion,升级安装也能拿到新表;
  // v7 起出现加列(票05 sourceHtml),加列走 addColumn 补齐(createAll
  // 不改既有表),更破坏性变更再写专门迁移。
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      await m.createAll();
      // v7 前的加列迁移随表类移除失去引用对象;被终止线的表用裸语句
      // 兜底(IF NOT EXISTS 幂等,老库才真有表)。
      // v9:图片谱线终止,image_charts 下线(ADR-0013)。
      // v10:独奏谱/识谱源导入面拆除,imported_solo_charts 下线(票64)。
      if (from < 9) {
        await customStatement('DROP TABLE IF EXISTS image_charts');
      }
      if (from < 10) {
        await customStatement('DROP TABLE IF EXISTS imported_solo_charts');
      }
    },
  );
}
