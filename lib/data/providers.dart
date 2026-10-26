import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backup_service.dart';
import 'database.dart';
import 'checkins_dao.dart';
import 'custom_charts_dao.dart';
import 'image_charts_dao.dart';
import 'imported_solo_charts_dao.dart';
import 'settings_dao.dart';

/// 全局唯一数据库实例：首次读取时创建，容器销毁时关闭。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 打卡数据访问（打卡/补卡/进度查询，工单 14）。
final checkInsDaoProvider = Provider<CheckInsDao>(
  (ref) => ref.watch(appDatabaseProvider).checkInsDao,
);

/// 自建谱数据访问（曲库数据源，工单 15）。
final customChartsDaoProvider = Provider<CustomChartsDao>(
  (ref) => ref.watch(appDatabaseProvider).customChartsDao,
);

/// 图片谱数据访问(相册图片谱数据源,工单 18)。
final imageChartsDaoProvider = Provider<ImageChartsDao>(
  (ref) => ref.watch(appDatabaseProvider).imageChartsDao,
);

/// 导入独奏谱数据访问(曲库独奏谱类目数据源,工单 43)。
final importedSoloChartsDaoProvider = Provider<ImportedSoloChartsDao>(
  (ref) => ref.watch(appDatabaseProvider).importedSoloChartsDao,
);

/// 设置数据访问(工单 20:键值读写,加载/写透纪律见 settings_providers)。
final settingsDaoProvider = Provider<SettingsDao>(
  (ref) => ref.watch(appDatabaseProvider).settingsDao,
);

/// 备份服务(工单 21:四表全量与单个 JSON 文档互转的落库口)。
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(appDatabaseProvider)),
);

/// 打卡流：路径页订阅，打卡写入即刷新（drift watch 响应式）。
final checkInsProvider = StreamProvider((ref) {
  return ref.watch(checkInsDaoProvider).watchAll();
});

/// 启动预热：触碰一次数据库，让空库在真机上当场打开。
/// 失败只记日志不阻塞壳——问题会在 logcat 暴露，不等后续工单第一次查询才炸。
final databaseWarmupProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  try {
    await db.customSelect('SELECT 1 AS ok').getSingle();
  } catch (error, stackTrace) {
    debugPrint('UkeFlow: 数据库打开失败 $error\n$stackTrace');
  }
});
