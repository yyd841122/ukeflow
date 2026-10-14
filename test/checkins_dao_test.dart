import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/checkin.dart';
import 'package:ukeflow/data/checkins_dao.dart';
import 'package:ukeflow/data/database.dart';

/// 工单 14 验收:DAO 内存库测试(打卡、补卡、进度查询)。
/// 「杀 App 重启仍在」由真机验收承担,内存库管行为正确性。
void main() {
  late AppDatabase db;
  late CheckInsDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.checkInsDao;
  });
  tearDown(() async => db.close());

  test('打卡:当天完成,天数/种类/日期原样落库', () async {
    await dao.checkIn(day: 1, kind: CheckInKind.completed, checkedOnDay: 100);
    final rows = await dao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.day, 1);
    expect(rows.single.kind, CheckInKind.completed);
    expect(rows.single.checkedOnDay, 100);
  });

  test('补卡:种类与补练日期原样落库', () async {
    await dao.checkIn(day: 3, kind: CheckInKind.madeUp, checkedOnDay: 105);
    final row = (await dao.getAll()).single;
    expect(row.kind, CheckInKind.madeUp);
    expect(row.checkedOnDay, 105);
  });

  test('一天至多一条打卡:重复打卡撞主键被拒', () async {
    await dao.checkIn(day: 1, kind: CheckInKind.completed, checkedOnDay: 100);
    await expectLater(
      dao.checkIn(day: 1, kind: CheckInKind.completed, checkedOnDay: 101),
      throwsA(anything),
    );
    expect(await dao.completedCount(), 1);
  });

  test('进度查询:completedCount(补卡同计进度)', () async {
    expect(await dao.completedCount(), 0);
    await dao.checkIn(day: 2, kind: CheckInKind.madeUp, checkedOnDay: 103);
    await dao.checkIn(day: 1, kind: CheckInKind.completed, checkedOnDay: 100);
    expect(await dao.completedCount(), 2);
  });

  test('watchAll 响应式:写入后自动推送,按天数升序', () async {
    await dao.checkIn(day: 2, kind: CheckInKind.completed, checkedOnDay: 101);
    final expectation = expectLater(
      dao.watchAll(),
      emitsInOrder([
        predicate<List<CheckIn>>((rows) => rows.single.day == 2, '初态:仅 day2'),
        predicate<List<CheckIn>>(
          (rows) => rows.length == 2 && rows[0].day == 1 && rows[1].day == 2,
          '写入 day1 后两条升序',
        ),
      ]),
    );
    await pumpEventQueue(); // 等初态查询落地,避免与写入竞态
    await dao.checkIn(day: 1, kind: CheckInKind.completed, checkedOnDay: 102);
    await expectation;
  });
}
