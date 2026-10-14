import 'package:drift/drift.dart';

import '../core/model/checkin.dart';
import 'database.dart';

part 'checkins_dao.g.dart';

/// 打卡数据访问(打卡/补卡/进度查询/响应式流)。
/// 种类判定等域规则在 core/model/checkin.dart,DAO 只管存取。
@DriftAccessor(tables: [CheckIns])
class CheckInsDao extends DatabaseAccessor<AppDatabase>
    with _$CheckInsDaoMixin {
  CheckInsDao(super.db);

  /// 打卡(完成/补卡同此入口)。一天至多一条:重复打卡撞主键被拒——
  /// 页面的打卡钮在写入期间禁用(双击防抖),完成顺序推进保证只有新目标天
  /// 会被写入;主键是最后防线。
  Future<void> checkIn({
    required int day,
    required CheckInKind kind,
    required int checkedOnDay,
  }) {
    return into(checkIns).insert(
      CheckInsCompanion.insert(
        day: Value(day),
        kind: kind,
        checkedOnDay: checkedOnDay,
      ),
    );
  }

  /// 全部打卡,按天数升序。
  Future<List<CheckIn>> getAll() {
    return (select(
      checkIns,
    )..orderBy([(row) => OrderingTerm.asc(row.day)])).get();
  }

  /// 进度查询:已打卡任务数(总进度 = 此数 / 30,补卡同计)。
  Future<int> completedCount() async {
    final count = checkIns.day.count();
    final query = selectOnly(checkIns)..addColumns([count]);
    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  /// 响应式打卡流:路径页订阅,打卡写入即刷新。
  Stream<List<CheckIn>> watchAll() {
    return (select(
      checkIns,
    )..orderBy([(row) => OrderingTerm.asc(row.day)])).watch();
  }
}
