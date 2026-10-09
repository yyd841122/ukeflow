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

  // 尚无任何表；后续工单加表时改用 drift codegen 生成。
  @override
  Iterable<TableInfo> get allTables => const [];
}
