import 'package:drift/drift.dart';

import 'database.dart';

part 'flowing_sessions_dao.g.dart';

/// 流水谱练习会话数据访问(票06):一行 = 一次进页练琴会话。
/// 写路径两支:开新行([start])与随写随存快照([saveSnapshot]——只改
/// 时长/位置/速度三列,不碰自评,自评归 [setRating] 定点改)。
@DriftAccessor(tables: [FlowingSessions])
class FlowingSessionsDao extends DatabaseAccessor<AppDatabase>
    with _$FlowingSessionsDaoMixin {
  FlowingSessionsDao(super.db);

  /// 开新会话行(起始时刻 epoch ms),返回行 id;控制器此后对同一行
  /// 快照存续。时长/位置/速度初值即表默认。
  Future<int> start(int startedAtMs) {
    return into(flowingSessions).insert(
      FlowingSessionsCompanion.insert(startedAtMs: startedAtMs),
    );
  }

  /// 会话快照(时长/结束位置/速度)——只写这三列,id 定点 UPDATE,
  /// 自评列不受影响(暂停/曲末/退页的随写随存与自评改互不覆盖)。
  Future<void> saveSnapshot({
    required int id,
    required int durationMs,
    required double endPositionSeconds,
    required double speed,
  }) {
    return (update(flowingSessions)..where((r) => r.id.equals(id))).write(
      FlowingSessionsCompanion(
        durationMs: Value(durationMs),
        endPositionSeconds: Value(endPositionSeconds),
        speed: Value(speed),
      ),
    );
  }

  /// 自评定点改(列表页下拉;null = 回到未自评)。行不存在静默忽略
  /// (会话行只增不删,理论不可达,防御不炸)。
  Future<void> setRating(int id, int? rating) {
    return (update(flowingSessions)..where((r) => r.id.equals(id))).write(
      FlowingSessionsCompanion(rating: Value(rating)),
    );
  }

  /// 最近 n 条(起始时刻降序;票06 列表页,默认 20)。
  Future<List<FlowingSession>> recent({int limit = 20}) {
    return (select(flowingSessions)
          ..orderBy([(r) => OrderingTerm.desc(r.startedAtMs)])
          ..limit(limit))
        .get();
  }

  /// 最近 n 条流(列表页订阅:自评改动即刷新)。
  Stream<List<FlowingSession>> watchRecent({int limit = 20}) {
    return (select(flowingSessions)
          ..orderBy([(r) => OrderingTerm.desc(r.startedAtMs)])
          ..limit(limit))
        .watch();
  }
}
