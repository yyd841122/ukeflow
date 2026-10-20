import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/tuner/pitch_math.dart' as pitch_math;
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/data/settings_dao.dart';
import 'package:ukeflow/data/settings_providers.dart';

/// 工单 20 设置供给:加载(空库缺省/种子库落库值)与写透(状态+DAO)。
/// 消费方测试 override 派生 provider(referenceA4Provider 等)即可隔离,
/// 不必建库;本文件经真 DAO 走完整加载/写透面。
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  Future<void> pumpContainer({Future<void> Function(AppDatabase)? seed}) async {
    db = AppDatabase(NativeDatabase.memory());
    await seed?.call(db);
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
    // 触发 build(惰性):读一次即启动异步加载。
    container.read(settingsProvider);
  }

  test('空库:初始与载入后均为缺省 440/80;缺省 A4 与 pitch_math 常量一致', () async {
    await pumpContainer();
    // 双源锚:设置缺省 A4 与全库换算常量(pitch_math)必须一致。
    expect(AppSettings.defaults().referenceA4, pitch_math.referenceA4.round());
    await container.read(settingsProvider.notifier).ready;
    expect(container.read(referenceA4Provider), 440.0);
    expect(container.read(defaultBpmProvider), 80);
  });

  test('种子库(A4=432、默认 BPM=96):载入后消费落库值', () async {
    await pumpContainer(
      seed: (db) async {
        await db.settingsDao.setInt(SettingsKeys.referenceA4, 432);
        await db.settingsDao.setInt(SettingsKeys.defaultBpm, 96);
      },
    );
    // 载入完成前是缺省(消费方先见缺省再换落库值,不阻塞首帧)。
    expect(container.read(referenceA4Provider), 440.0);
    await container.read(settingsProvider.notifier).ready;
    expect(container.read(referenceA4Provider), 432.0);
    expect(container.read(defaultBpmProvider), 96);
  });

  test('setReferenceA4:状态即时换、写透落库、越界钳制到 415–466', () async {
    await pumpContainer();
    final notifier = container.read(settingsProvider.notifier);
    await notifier.ready;

    await notifier.setReferenceA4(432);
    expect(container.read(referenceA4Provider), 432.0);
    expect(await db.settingsDao.getInt(SettingsKeys.referenceA4), 432);

    await notifier.setReferenceA4(999);
    expect(container.read(referenceA4Provider), 466.0);
    await notifier.setReferenceA4(400);
    expect(container.read(referenceA4Provider), 415.0);
    expect(await db.settingsDao.getInt(SettingsKeys.referenceA4), 415);
  });

  test('setDefaultBpm:钳制 40–208,写透落库', () async {
    await pumpContainer();
    final notifier = container.read(settingsProvider.notifier);
    await notifier.ready;

    await notifier.setDefaultBpm(300);
    expect(container.read(defaultBpmProvider), 208);
    await notifier.setDefaultBpm(10);
    expect(container.read(defaultBpmProvider), 40);
    await notifier.setDefaultBpm(96);
    expect(container.read(defaultBpmProvider), 96);
    expect(await db.settingsDao.getInt(SettingsKeys.defaultBpm), 96);
  });

  test('写透与初载竞速:载入期间的写入不被迟到加载回滚(评审钉竞态契约)', () async {
    // 场景:种子库 432;同一同步轮里触发 build(启动在途加载)并立刻写
    // 435——加载 getInt 与写透 setInt 都在途,真实竞速。契约:setter 先等
    // 初载落地再动状态,终态 435;无定序的实现里迟到的加载(432)会最后
    // 落盘覆盖秒改。红验证:对删掉 setter `await ready` 的实现跑,终态
    // 断言必红(回滚成 432)。
    db = AppDatabase(NativeDatabase.memory());
    await db.settingsDao.setInt(SettingsKeys.referenceA4, 432);
    addTearDown(db.close);
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    // 同一同步轮:读一次触发 build+在途加载,随即写入,不等 ready。
    container.read(settingsProvider);
    await container.read(settingsProvider.notifier).setReferenceA4(435);
    // 再让一拍:破序实现下迟到的加载在这一拍落地。
    await Future<void>.delayed(Duration.zero);
    expect(container.read(referenceA4Provider), 435.0, reason: '秒改不被初载回滚');
    expect(await db.settingsDao.getInt(SettingsKeys.referenceA4), 435);
  });

  test('reload:导入备份换掉设置行后,重读落库值(工单 21)', () async {
    await pumpContainer(
      seed: (db) async {
        await db.settingsDao.setInt(SettingsKeys.referenceA4, 440);
      },
    );
    final notifier = container.read(settingsProvider.notifier);
    await notifier.ready;
    expect(container.read(referenceA4Provider), 440.0);

    // 模拟导入备份:库里行被换成备份内容(不经控制器,直达库)。
    await db.settingsDao.setInt(SettingsKeys.referenceA4, 432);
    await db.settingsDao.setInt(SettingsKeys.defaultBpm, 96);

    await notifier.reload();

    expect(container.read(referenceA4Provider), 432.0);
    expect(container.read(defaultBpmProvider), 96);
  });

  test('评分延迟(工单 33):空库缺省 100ms,种子库落库值', () async {
    await pumpContainer();
    await container.read(settingsProvider.notifier).ready;
    expect(container.read(scoringLatencyMsProvider), 100,
        reason: '真机链路常见量级 ~0.1s');

    await pumpContainer(
      seed: (db) async =>
          db.settingsDao.setInt(SettingsKeys.scoringLatencyMs, 130),
    );
    await container.read(settingsProvider.notifier).ready;
    expect(container.read(scoringLatencyMsProvider), 130);
  });

  test('setScoringLatencyMs:状态即时换、写透落库、钳制 ±200', () async {
    await pumpContainer();
    final notifier = container.read(settingsProvider.notifier);
    await notifier.ready;

    await notifier.setScoringLatencyMs(150);
    expect(container.read(scoringLatencyMsProvider), 150);
    expect(await db.settingsDao.getInt(SettingsKeys.scoringLatencyMs), 150,
        reason: '重启仍在(跨会话生效)');

    await notifier.setScoringLatencyMs(500);
    expect(container.read(scoringLatencyMsProvider), 200);
    await notifier.setScoringLatencyMs(-999);
    expect(container.read(scoringLatencyMsProvider), -200);
  });
}
