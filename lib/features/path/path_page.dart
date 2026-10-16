import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/builtin_learning_path.dart';
import '../../core/model/checkin.dart';
import '../../core/model/learning_path.dart';
import '../../data/database.dart' show CheckIn;
import '../../data/providers.dart';

/// 路径页：30 天练习路径全貌 + 今日任务 + 打卡（工单 14）。
/// 路径推进按完成顺序（spec 故事 37）：今日任务 = 第一个未打卡天；
/// 任务目标以文字呈现，一键直达归工单 22。
class PathPage extends ConsumerStatefulWidget {
  const PathPage({super.key});

  @override
  ConsumerState<PathPage> createState() => _PathPageState();
}

class _PathPageState extends ConsumerState<PathPage>
    with WidgetsBindingObserver {
  /// 写入进行中:打卡钮禁用。
  bool _checking = false;

  /// 打卡失败的可读说明(数据库错误等);重试成功即清。
  String? _checkInError;

  /// 连击吸收窗:打卡推进页面当天,快速第二击会落在**新一天**的任务卡上,
  /// 仿佛用户连打两天——900ms 内的后续打卡静默忽略(无 Timer,fake zone 安全)。
  static const _tapAbsorbWindow = Duration(milliseconds: 900);
  DateTime _lastCheckInTap = DateTime.fromMillisecondsSinceEpoch(0);

  /// 连击/今日任务是「当日值」,只在重建时算——常驻页跨午夜、或隔日
  /// 从后台恢复会显示过期连击(审计 2026-10-16 #32)。定时到下个本地
  /// 午夜重算一次,应用从后台回前台也重算。
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _armMidnightRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDayBoundValues();
      _armMidnightRefresh();
    }
  }

  /// 挂一个到下个本地午夜的定时器,到点重算当日值并重挂。
  void _armMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(nextMidnight.difference(now), () {
      if (!mounted) return;
      _refreshDayBoundValues();
      _armMidnightRefresh();
    });
  }

  void _refreshDayBoundValues() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final checkInsAsync = ref.watch(checkInsProvider);
    return checkInsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorView(error: error),
      data: (checkIns) => _PathView(
        checkIns: checkIns,
        onCheckIn: _checkInToday,
        checking: _checking,
        error: _checkInError,
      ),
    );
  }

  /// 打今日任务：完成顺序推进与种类判定都是 core/model 纯函数，
  /// 页面只做编排（读现状→定目标→落库），画面刷新由打卡流驱动。
  Future<void> _checkInToday() async {
    final now = DateTime.now();
    if (_checking || now.difference(_lastCheckInTap) < _tapAbsorbWindow) {
      return;
    }
    _lastCheckInTap = now;
    setState(() => _checking = true);
    try {
      final dao = ref.read(checkInsDaoProvider);
      final rows = await dao.getAll();
      final today = epochDayOf(DateTime.now());
      final next = builtinLearningPath.nextTaskDay({
        for (final row in rows) row.day,
      });
      if (next == null) {
        return;
      }
      await dao.checkIn(
        day: next,
        kind: checkInKindFor(
          checkedOnDays: {for (final row in rows) row.checkedOnDay},
          today: today,
        ),
        checkedOnDay: today,
      );
    } on Object catch (error) {
      // 数据库读/打卡失败不得逃逸异步按钮回调:按钮恢复可用却不说明
      // 进度未保存(审计 2026-10-16 #31,与文本导入 #30 同型同修)。
      if (mounted) {
        setState(() => _checkInError = '打卡没有存上,请重试:$error');
      }
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }
}

/// 打卡现状驱动的整页视图。
class _PathView extends StatelessWidget {
  const _PathView({
    required this.checkIns,
    required this.onCheckIn,
    required this.checking,
    this.error,
  });

  final List<CheckIn> checkIns;
  final VoidCallback onCheckIn;

  /// 写入进行中:打卡钮禁用。
  final bool checking;

  /// 打卡失败的可读说明(null = 没失败)。
  final String? error;

  @override
  Widget build(BuildContext context) {
    final checkedDays = {for (final row in checkIns) row.day};
    final kindByDay = {for (final row in checkIns) row.day: row.kind};
    final checkedOnDayByDay = {
      for (final row in checkIns) row.day: row.checkedOnDay,
    };
    final nextDay = builtinLearningPath.nextTaskDay(checkedDays);
    final streak = streakDays(
      checkedOnDays: {for (final row in checkIns) row.checkedOnDay},
      today: epochDayOf(DateTime.now()),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        _ProgressHeader(checked: checkedDays.length, streak: streak),
        const SizedBox(height: 16),
        if (error != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (nextDay != null)
          _TodayTaskCard(
            task: builtinLearningPath.tasks[nextDay - 1],
            onCheckIn: onCheckIn,
            checking: checking,
          )
        else
          _GraduatedCard(streak: streak),
        const SizedBox(height: 24),
        Text('路径全貌', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (index, task)
                  in builtinLearningPath.tasks.indexed) ...[
                if (index == 0 ||
                    task.phase != builtinLearningPath.tasks[index - 1].phase)
                  _PhaseHeader(task.phase),
                _DayTile(
                  task: task,
                  state: _stateOf(task, checkedDays, nextDay),
                  kind: kindByDay[task.day],
                  checkedOnDay: checkedOnDayByDay[task.day],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  _DayState _stateOf(DailyTask task, Set<int> checkedDays, int? nextDay) {
    if (checkedDays.contains(task.day)) {
      return _DayState.checked;
    }
    if (task.day == nextDay) {
      return _DayState.today;
    }
    return _DayState.upcoming;
  }
}

/// 总进度与连续打卡天数（工单 14 验收两项）。
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.checked, required this.streak});

  final int checked;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '总进度',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Icon(Icons.local_fire_department, color: scheme.primary),
                const SizedBox(width: 4),
                Text(
                  '连续 $streak 天',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('$checked/30', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: checked / builtinLearningPath.tasks.length,
            ),
          ],
        ),
      ),
    );
  }
}

/// 今日任务卡：学什么 + 练什么 + 打卡钮。
class _TodayTaskCard extends StatelessWidget {
  const _TodayTaskCard({
    required this.task,
    required this.onCheckIn,
    required this.checking,
  });

  final DailyTask task;
  final VoidCallback onCheckIn;

  /// 写入进行中:打卡钮禁用(双击防抖)。
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('今日任务', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Text(
                  '第 ${task.day} 天 · ${task.phase}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(task.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _LabeledText(label: '学', text: task.learn),
            const SizedBox(height: 8),
            _LabeledText(label: '练', text: task.practice),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('path-checkin'),
                onPressed: checking ? null : onCheckIn,
                icon: const Icon(Icons.flag),
                label: const Text('打卡'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「学」「练」标签行。
class _LabeledText extends StatelessWidget {
  const _LabeledText({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}

/// 30 天全部完成的毕业卡。
class _GraduatedCard extends StatelessWidget {
  const _GraduatedCard({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.celebration, size: 48, color: scheme.primary),
            const SizedBox(height: 8),
            Text('30 天路径全部完成！', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '连续 $streak 天 · 继续练第 29 天开的目标曲',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// 全貌分段头（阶段名）。
class _PhaseHeader extends StatelessWidget {
  const _PhaseHeader(this.phase);

  final String phase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(phase, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

/// 全貌里一天的状态。
enum _DayState { checked, today, upcoming }

/// 全貌的一天：天数圆标 + 主题 + 状态徽章（完成/补卡/今日任务/未到）。
/// 已打卡的天可点进详情回看内容（打卡只打一次,回看不限次）。
class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.task,
    required this.state,
    required this.kind,
    required this.checkedOnDay,
  });

  final DailyTask task;
  final _DayState state;
  final CheckInKind? kind;

  /// 打卡发生的日历日(epoch 天数),仅已打卡天非空,进详情显示。
  final int? checkedOnDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (circleColor, badgeText, badgeColor) = switch (state) {
      _DayState.checked when kind == CheckInKind.madeUp => (
        scheme.tertiary,
        '补卡',
        scheme.tertiary,
      ),
      _DayState.checked => (scheme.primary, '完成', scheme.primary),
      _DayState.today => (scheme.secondaryContainer, '今日任务', scheme.secondary),
      _DayState.upcoming => (
        scheme.surfaceContainerHighest,
        '未到',
        scheme.outline,
      ),
    };
    final tile = ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: circleColor,
        foregroundColor: state == _DayState.upcoming
            ? scheme.onSurfaceVariant
            : scheme.onPrimary,
        child: Text('${task.day}', style: const TextStyle(fontSize: 12)),
      ),
      title: Text(
        task.title,
        style: TextStyle(
          color: state == _DayState.upcoming ? scheme.onSurfaceVariant : null,
        ),
      ),
      trailing: Text(
        badgeText,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: badgeColor),
      ),
    );
    if (state != _DayState.checked || kind == null || checkedOnDay == null) {
      return tile;
    }
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _DayDetailPage(
            task: task,
            kind: kind!,
            checkedOnDay: checkedOnDay!,
          ),
        ),
      ),
      child: tile,
    );
  }
}

/// 已打卡天的内容回看页:学/练全文 + 已打卡标记与打卡日期。
class _DayDetailPage extends StatelessWidget {
  const _DayDetailPage({
    required this.task,
    required this.kind,
    required this.checkedOnDay,
  });

  final DailyTask task;
  final CheckInKind kind;
  final int checkedOnDay;

  String get _dateLabel {
    final date = epochDayToDate(checkedOnDay);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kindLabel = kind == CheckInKind.madeUp ? '补卡' : '完成';
    return Scaffold(
      appBar: AppBar(title: Text('第 ${task.day} 天')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            color: scheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      // Expanded:窄屏放不下时标记换行,不横向溢出。
                      Expanded(
                        child: Text(
                          '已打卡 · $kindLabel',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: scheme.primary),
                        ),
                      ),
                      Text(
                        '打卡日期 $_dateLabel',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: scheme.onPrimaryContainer),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '学什么',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 4),
          Text(task.learn),
          const SizedBox(height: 16),
          Text(
            '练什么',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 4),
          Text(task.practice),
        ],
      ),
    );
  }
}

/// 打卡流失败的可见报错：原文直接展示，不带病进路径页。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text('打卡数据加载失败', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
