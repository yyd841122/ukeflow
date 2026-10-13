import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chart_providers.dart';
import '../rhythm/metronome_page.dart';
import '../rhythm/rhythm_trainer_page.dart';
import 'chart_meta.dart';
import 'practice_page.dart';

/// 跟练页签:内置曲库点曲进入跟练会话;节拍器与节奏型训练先行入驻
/// (练稳定右手不依赖跟练引擎,工单 06/09 迁移保留)。
class PlayPage extends ConsumerWidget {
  const PlayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chartsAsync = ref.watch(builtinChartsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MetronomePage(),
                  ),
                ),
                icon: const Icon(Icons.av_timer),
                label: const Text('节拍器'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RhythmTrainerPage(),
                  ),
                ),
                icon: const Icon(Icons.swap_vert),
                label: const Text('节奏型训练'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          '内置曲库',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...chartsAsync.when(
          loading: () => const [
            Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            ),
          ],
          error: (error, _) => [_LibraryErrorView(error: error)],
          data: (charts) => [
            for (final entry in charts) _ChartCard(entry: entry),
          ],
        ),
      ],
    );
  }
}

/// 曲库卡片:曲名 + 元信息行,点按进入跟练会话页。
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.entry});

  final BuiltInChart entry;

  @override
  Widget build(BuildContext context) {
    final chart = entry.chart;
    final meta = chartMetaLine(chart);
    return Card(
      key: Key('chart-${entry.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(chart.title),
        subtitle: meta != null ? Text(meta) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PracticePage(chart: chart),
          ),
        ),
      ),
    );
  }
}

/// 曲库加载失败的可见报错:原文直接展示,不带病进列表(与和弦库页同一哲学)。
class _LibraryErrorView extends StatelessWidget {
  const _LibraryErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: scheme.error),
          const SizedBox(height: 12),
          Text('内置曲库加载失败', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('$error', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
