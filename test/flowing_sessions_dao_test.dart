import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/flowing_sessions_dao.dart';

/// 票06 会话 DAO 内存库测试:开行/快照存续/自评定点改/最近序。
/// 时长语义(扣除暂停/预备)是控制器域规则,在控制器测试锁定。
void main() {
  late AppDatabase db;
  late FlowingSessionsDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.flowingSessionsDao;
  });
  tearDown(() async => db.close());

  test('start 开行返回 id,快照只改时长/位置/速度三列', () async {
    final id = await dao.start(1000);
    await dao.saveSnapshot(
      id: id,
      durationMs: 95000,
      endPositionSeconds: 42.5,
      speed: 0.75,
    );
    final rows = await dao.recent();
    expect(rows, hasLength(1));
    expect(rows.single.id, id);
    expect(rows.single.startedAtMs, 1000);
    expect(rows.single.durationMs, 95000);
    expect(rows.single.endPositionSeconds, 42.5);
    expect(rows.single.speed, 0.75);
    expect(rows.single.rating, isNull, reason: '快照不碰自评列');
  });

  test('setRating 定点改,null 回未自评;不存在的行静默', () async {
    final id = await dao.start(2000);
    await dao.setRating(id, 2);
    expect((await dao.recent()).single.rating, 2);
    await dao.setRating(id, null);
    expect((await dao.recent()).single.rating, isNull);
    await dao.setRating(9999, 3);
    expect((await dao.recent()), hasLength(1));
  });

  test('recent 最近序降序 + limit 截断(列表页最近 20 的存储面)', () async {
    for (final startedAt in [300, 100, 200]) {
      final id = await dao.start(startedAt);
      await dao.saveSnapshot(id: id, durationMs: 1, endPositionSeconds: 0, speed: 1);
    }
    final top2 = await dao.recent(limit: 2);
    expect(top2.map((r) => r.startedAtMs), [300, 200]);
  });
}
