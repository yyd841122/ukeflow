import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database.dart';

/// 全局唯一数据库实例：首次读取时创建，容器销毁时关闭。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
