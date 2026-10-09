import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// UkeFlow 本地数据库（drift/SQLite）。
/// 表结构随后续工单逐个加入（打卡 / 自建谱 / 设置），当前为空库骨架；
/// 加表时 schemaVersion 递增并写迁移。
class AppDatabase extends GeneratedDatabase {
  /// 默认连接设备上的 ukeflow.sqlite；测试注入内存执行器。
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'ukeflow'));

  @override
  int get schemaVersion => 1;

  // v1 前期 schema 只加不改：建库与升级都 createAll（生成 IF NOT EXISTS，幂等），
  // 后续工单加表只需建表 + 递增 schemaVersion，升级安装也能拿到新表；
  // 出现破坏性变更时再替换为专门的迁移步骤。
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) => m.createAll(),
  );

  // 尚无任何表；后续工单加表时改用 drift codegen 生成。
  @override
  Iterable<TableInfo> get allTables => const [];
}
