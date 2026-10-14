// 练习路径与每日任务(GLOSSARY:内置的从入门到弹唱的结构化课程序列)。
// 路径推进按完成顺序而非日历日(spec 用户故事 37):今日任务 =
// 第一个未打卡的每日任务,见 [PracticePath.nextTaskDay]。
// 内置内容坏数据当场抛 [PathDataError],不带病入库(同 ChordDataError 哲学)。

/// 每日任务:路径中一天的学习单元(学什么 + 练什么 + 打卡)。
// 任务目标 v1 以文字呈现,一键直达归工单 22。
class DailyTask {
  const DailyTask({
    required this.day,
    required this.phase,
    required this.title,
    required this.learn,
    required this.practice,
  });

  /// 天数,从 1 起连续递增。
  final int day;

  /// 所属阶段(如「认识和弦」),路径全貌按它分段。
  final String phase;

  /// 当日主题(一句话)。
  final String title;

  /// 学什么(知识点/要领)。
  final String learn;

  /// 练什么(今日练习动作,指向 App 内具体页面或曲目)。
  final String practice;
}

/// 一条练习路径:逐日任务序列。
class PracticePath {
  PracticePath.fromTasks(List<DailyTask> tasks)
    : tasks = List.unmodifiable(tasks) {
    if (tasks.isEmpty) {
      throw const PathDataError('练习路径不能为空');
    }
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      if (task.day != i + 1) {
        throw PathDataError('第 ${i + 1} 项任务天数应为 ${i + 1},实际 ${task.day}');
      }
      for (final (label, text) in [
        ('阶段', task.phase),
        ('主题', task.title),
        ('学什么', task.learn),
        ('练什么', task.practice),
      ]) {
        if (text.trim().isEmpty) {
          throw PathDataError('第 ${task.day} 天的$label文案为空');
        }
      }
    }
  }

  final List<DailyTask> tasks;

  /// 今日任务(完成顺序推进):第一个未打卡的天数;全部完成返回 null。
  int? nextTaskDay(Set<int> checkedDays) {
    for (final task in tasks) {
      if (!checkedDays.contains(task.day)) {
        return task.day;
      }
    }
    return null;
  }
}

/// 练习路径数据坏损(内置内容校验失败)。
class PathDataError implements Exception {
  const PathDataError(this.message);

  final String message;

  @override
  String toString() => '练习路径数据错误: $message';
}
