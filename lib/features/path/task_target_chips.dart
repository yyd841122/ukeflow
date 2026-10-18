import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/builtin_strum_patterns.dart';
import '../../core/model/task_target.dart';
import '../../data/chart_providers.dart';
import '../../data/chord_library.dart';
import '../chords/chord_detail_page.dart';
import '../play/practice_page.dart';
import '../rhythm/rhythm_trainer_page.dart';

/// 任务目标直达 chips(工单 22):学/练文案点名的和弦/节奏型/曲目按类
/// 直达——和弦→和弦详情、节奏型→节奏型训练器(带型预选)、曲目→跟练页
/// (带谱上下文)。降级口径:仅对**真缺失**(库/曲库已加载且查不到,或
/// 加载失败)出「暂不可直达」文字;provider 还在加载时该类目标静默不
/// 渲染,下一帧数据到了自然翻正,不闪降级文案。
class TaskTargetChips extends ConsumerWidget {
  const TaskTargetChips({super.key, required this.targets});

  final List<TaskTarget> targets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (targets.isEmpty) return const SizedBox.shrink();
    final chordLibrary = ref.watch(chordLibraryProvider);
    final chordsByLabel = chordLibrary.isLoading
        ? null // 加载中:和弦目标挂起,不算缺失
        : {
          for (final chord in chordLibrary.value?.chords ?? const <Chord>[])
            chord.label: chord,
        };
    final builtinCharts = ref.watch(builtinChartsProvider);
    final chartsById = builtinCharts.isLoading
        ? null
        : {
          for (final built
              in builtinCharts.value ?? const <BuiltInChart>[])
            built.id: built.chart,
        };
    final patternsById = {
      for (final pattern in builtinStrumPatterns) pattern.id: pattern,
    };

    final chips = <Widget>[];
    final missing = <String>[];
    for (final target in targets) {
      final resolution = switch (target) {
        // 挂起(来源表还没加载好):跳过渲染,也不算缺失。
        ChordTarget() when chordsByLabel == null => null,
        SongTarget() when chartsById == null => null,
        _ => resolveTaskTarget(
          target,
          chordsByLabel: chordsByLabel ?? const {},
          patternsById: patternsById,
          chartsById: chartsById ?? const {},
        ),
      };
      switch (resolution) {
        case null:
          break;
        case ChordTargetResolved(:final chord):
          chips.add(_chip(
            context,
            key: 'task-target-${target.label}',
            icon: Icons.music_note,
            label: chord.label,
            page: ChordDetailPage(chord: chord),
          ));
        case PatternTargetResolved(:final pattern):
          chips.add(_chip(
            context,
            key: 'task-target-${target.label}',
            icon: Icons.swap_vert,
            label: pattern.name,
            page: RhythmTrainerPage(initialPattern: pattern),
          ));
        case SongTargetResolved(:final chart):
          chips.add(_chip(
            context,
            key: 'task-target-${target.label}',
            icon: Icons.play_circle_outline,
            label: target.label,
            page: PracticePage(chart: chart),
          ));
        case TargetMissing():
          missing.add(target.label);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: chips),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '「${missing.join('」「')}」暂不可直达',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
      ],
    );
  }

  /// 三类目标共用的 chip 形状:key + 图标 + 标签 + 压栈进目标页。
  Widget _chip(
    BuildContext context, {
    required String key,
    required IconData icon,
    required String label,
    required Widget page,
  }) => ActionChip(
    key: Key(key),
    avatar: Icon(icon, size: 18),
    label: Text(label),
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    ),
  );
}
