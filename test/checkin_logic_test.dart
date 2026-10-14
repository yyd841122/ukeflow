import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/checkin.dart';

void main() {
  group('epochDayOf(本地日历日 → epoch 天数)', () {
    test('同一天的不同时刻映射到同一个数', () {
      final a = epochDayOf(DateTime(2026, 10, 14, 8, 30));
      final b = epochDayOf(DateTime(2026, 10, 14, 23, 59));
      expect(a, b);
    });

    test('相邻日差 1,且与已知锚点一致(2026-10-14 = 20740)', () {
      // 独立锚点核对:1970→2026 年初 = 56×365+14 个闰日 = 20454,
      // 再加年内 286 天(非闰年) = 20740。手算过程留在报错里便于复核。
      expect(
        epochDayOf(DateTime(2026, 10, 14)),
        20740,
        reason: '20454 + 286 = 20740',
      );
      expect(epochDayOf(DateTime(2026, 10, 15)), 20741);
    });

    test('epochDayToDate 与 epochDayOf 往返一致', () {
      final date = DateTime(2026, 10, 14);
      final back = epochDayToDate(epochDayOf(date));
      expect(back.year, 2026);
      expect(back.month, 10);
      expect(back.day, 14);
    });
  });

  group('streakDays(连续打卡天数)', () {
    const today = 100;

    test('没有打卡 = 0 天', () {
      expect(streakDays(checkedOnDays: {}, today: today), 0);
    });

    test('今天打了,从今天往回数连续日历日', () {
      expect(streakDays(checkedOnDays: {100}, today: today), 1);
      expect(streakDays(checkedOnDays: {98, 99, 100}, today: today), 3);
    });

    test('今天还没打,昨天打了链子还活着(今天打上就续上)', () {
      expect(streakDays(checkedOnDays: {99}, today: today), 1);
      expect(streakDays(checkedOnDays: {97, 98, 99}, today: today), 3);
    });

    test('最近一次打卡停在前天 = 断了,归零', () {
      expect(streakDays(checkedOnDays: {98}, today: today), 0);
      expect(streakDays(checkedOnDays: {50}, today: today), 0);
    });

    test('中间缺一天,链子只数缺口之后的段', () {
      expect(streakDays(checkedOnDays: {97, 98, 100}, today: today), 1);
      expect(streakDays(checkedOnDays: {96, 97, 99}, today: today), 1);
      expect(streakDays(checkedOnDays: {96, 97, 98, 99}, today: today), 4);
    });
  });

  group('checkInKindFor(打卡种类:完成/补卡)', () {
    test('首次打卡=完成(没有「落后」可言)', () {
      expect(
        checkInKindFor(checkedOnDays: {}, today: 100),
        CheckInKind.completed,
      );
    });

    test('与最近一次打卡同日或紧邻日=完成', () {
      expect(
        checkInKindFor(checkedOnDays: {98, 99}, today: 99),
        CheckInKind.completed,
      );
      expect(
        checkInKindFor(checkedOnDays: {99}, today: 100),
        CheckInKind.completed,
      );
    });

    test('隔日以上才回来=补卡(标记补练日期,spec 故事 36)', () {
      expect(
        checkInKindFor(checkedOnDays: {96, 97}, today: 100),
        CheckInKind.madeUp,
      );
    });
  });
}
