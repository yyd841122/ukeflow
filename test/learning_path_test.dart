import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/learning_path.dart';

DailyTask _task(int day, {String phase = '认识和弦'}) => DailyTask(
  day: day,
  phase: phase,
  title: '第 $day 天主题',
  learn: '学什么',
  practice: '练什么',
);

void main() {
  test('PracticePath 接受天数连续、文案齐全的任务序列', () {
    final path = PracticePath.fromTasks([_task(1), _task(2), _task(3)]);
    expect(path.tasks, hasLength(3));
    expect(path.tasks[1].day, 2);
  });

  test('PracticePath 拒绝天数断档(内置内容不带病入库)', () {
    expect(
      () => PracticePath.fromTasks([_task(1), _task(3)]),
      throwsA(isA<PathDataError>()),
    );
  });

  test('今日任务按完成顺序推进:第一个未打卡天;全部完成则无', () {
    final path = PracticePath.fromTasks([_task(1), _task(2), _task(3)]);
    expect(path.nextTaskDay({}), 1);
    expect(path.nextTaskDay({1}), 2);
    expect(path.nextTaskDay({1, 2}), 3);
    expect(path.nextTaskDay({1, 2, 3}), isNull);
    // 与打卡先后无关:跳着补也算推进到下一个未打卡天。
    expect(path.nextTaskDay({3}), 1);
  });

  test('PracticePath 拒绝空文案(学/练/主题/阶段任一为空即坏数据)', () {
    expect(
      () => PracticePath.fromTasks([
        _task(1),
        DailyTask(day: 2, phase: '', title: 't', learn: 'l', practice: 'p'),
      ]),
      throwsA(isA<PathDataError>()),
    );
  });
}
