import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/builtin_learning_path.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';

/// 内容守护(工单 14 验收「内容自评审」的机械半边):结构不变量与
/// 「练什么必落到 App 内具体页面」由测试永久看守;文案质量本身归人工评审。
void main() {
  test('内置路径整 30 天,天数连续(PracticePath 校验兜底)', () {
    expect(builtinLearningPath.tasks, hasLength(30));
  });

  test('弧线覆盖:四阶段依序走完「和弦→右手稳定→节奏型→跟练成曲」', () {
    // 阶段首现顺序即弧线:每段必须连续(不允许回头阶段),
    // PracticePath 校验已保证天数连续,这里锁「走什么线」。
    final phases = <String>[];
    for (final task in builtinLearningPath.tasks) {
      if (phases.isEmpty || phases.last != task.phase) {
        phases.add(task.phase);
      }
    }
    expect(phases, ['认识和弦', '右手稳定', '节奏型', '跟练成曲']);
  });

  test('每条「练什么」都指向 App 内具体页面(任务可执行,不悬空)', () {
    const appPages = ['调音器', '和弦库', '节拍器', '节奏型训练', '跟练', '示范试听', '曲库'];
    for (final task in builtinLearningPath.tasks) {
      expect(
        appPages.any(task.practice.contains),
        isTrue,
        reason: '第 ${task.day} 天「练什么」未指向任何 App 页面:${task.practice}',
      );
    }
  });

  test('四个内置节奏型全部入径(名称与 builtin_strum_patterns 逐字一致)', () {
    // 头注释宣称「节奏型名与内置模式同源」,此处机械守护:每个节奏型
    // 的 name 都在某天的学/练文案中出现(既锁覆盖,也锁拼写漂移)。
    for (final pattern in builtinStrumPatterns) {
      final covered = builtinLearningPath.tasks.any(
        (task) =>
            task.learn.contains(pattern.name) ||
            task.practice.contains(pattern.name),
      );
      expect(covered, isTrue, reason: '节奏型「${pattern.name}」未入径');
    }
  });

  test('每日任务文案长度有界(全貌列表可读,不塞长文)', () {
    for (final task in builtinLearningPath.tasks) {
      expect(
        task.learn.length,
        lessThanOrEqualTo(80),
        reason: '第 ${task.day} 天学什么过长',
      );
      expect(
        task.practice.length,
        lessThanOrEqualTo(90),
        reason: '第 ${task.day} 天练什么过长',
      );
      expect(
        task.title.length,
        lessThanOrEqualTo(16),
        reason: '第 ${task.day} 天主题过长',
      );
    }
  });

  test('Am 课程的衔接文案与 C/Am 真实指法一致(审计30 #18)', () {
    final day3 = builtinLearningPath.tasks.singleWhere((t) => t.day == 3);
    expect(day3.learn, contains('中指'), reason: 'Am 用中指');
    expect(day3.learn, isNot(contains('共用一根手指')),
        reason: 'C 无名指、Am 中指,不同弦不同指——「共用」是事实错误');
  });

}
