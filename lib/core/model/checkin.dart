// 打卡域规则(GLOSSARY「打卡」:标记某个每日任务已完成,是练习进度的
// 唯一记录方式)。纯函数,零引擎/数据库依赖——规格见 test/checkin_logic_test。
//
// 日历日一律用本地日期换算的 epoch 天数([epochDayOf]),不涉时区偏移。

/// 打卡种类:完成(按日续练)或补卡(隔日以上补上,标记补练日期,spec 故事 36)。
enum CheckInKind { completed, madeUp }

/// 本地日历日 → epoch 天数(以日期分界,同日任意时刻同值)。
int epochDayOf(DateTime local) {
  final day = DateTime.utc(local.year, local.month, local.day);
  return day.difference(DateTime.utc(1970, 1, 1)).inDays;
}

/// 本次打卡的种类:与最近一次打卡同日或紧邻日 = 完成;
/// 首次打卡 = 完成(没有「落后」可言);隔日以上才回来 = 补卡。
CheckInKind checkInKindFor({
  required Set<int> checkedOnDays,
  required int today,
}) {
  if (checkedOnDays.isEmpty) {
    return CheckInKind.completed;
  }
  final last = checkedOnDays.reduce((a, b) => a > b ? a : b);
  return today - last <= 1 ? CheckInKind.completed : CheckInKind.madeUp;
}

/// 连续打卡天数:从今天往回数连续有打卡的日历日;今天还没打时从昨天起数
/// (链子在今天结束前都算活着),昨天也没有则归零。中间缺一天即断段。
int streakDays({required Set<int> checkedOnDays, required int today}) {
  // 锚点:今天打了从今天起数,没打则从昨天起数(链子今天内还活着);
  // 两处都没有打卡 = 断了。
  var day = checkedOnDays.contains(today) ? today : today - 1;
  if (!checkedOnDays.contains(day)) {
    return 0;
  }
  var streak = 0;
  while (checkedOnDays.contains(day)) {
    streak++;
    day--;
  }
  return streak;
}
