import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/strum_chart.dart';
import '../../data/chart_providers.dart';
import '../play/chart_meta.dart';
import '../play/practice_page.dart';
import '../play/tab_chart_page.dart';
import '../rhythm/metronome_page.dart';
import '../rhythm/rhythm_trainer_page.dart';
import 'cifraclub_search_page.dart';
import 'text_import_page.dart';

/// 曲库页(工单 15):练琴入口的唯一家——顶部练琴工具行(节拍器/节奏型
/// 训练,工单 15 后续自用户决策裁撤跟练页签并入于此),下方统一曲目列表,
/// 分区即曲谱类型:弹唱谱(内置+自建,GLOSSARY「自建谱」导入后自动入列)
/// 与指弹谱(内置);点弹唱谱/指弹谱直达对应跟练。图片谱区归工单 18。
/// 三类曲目合流为一个 provider,加载/错误/空态在一处呈现;
/// 自建谱坏一条只标记一条,不牵连整库(见 chart_providers.dart)。
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        // 工具行不依赖曲库数据:加载/错误态也在,练琴不被列表问题挡路。
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
        const SizedBox(height: 24),
        ...libraryAsync.when(
          loading: () => [
            _strumSectionHeader(context),
            const _SectionLoading(),
          ],
          error: (error, _) => [
            _strumSectionHeader(context),
            _LibraryErrorView(error: error),
          ],
          data: (library) => [
            _strumSectionHeader(context),
            const SizedBox(height: 8),
            for (final entry in library.builtinStrum)
              _ChartCard(
                cardKey: 'chart-${entry.id}',
                title: entry.chart.title,
                subtitle: chartMetaLine(entry.chart),
                onTap: () => _openStrumPractice(context, entry.chart),
              ),
            for (final entry in library.customStrum)
              switch (entry) {
                ReadyCustomStrum() => _ChartCard(
                  cardKey: 'custom-chart-${entry.id}',
                  title: entry.title,
                  subtitle: chartMetaLine(entry.chart),
                  onTap: () => _openStrumPractice(context, entry.chart),
                ),
                BrokenCustomStrum() => _ChartCard(
                  cardKey: 'custom-chart-${entry.id}',
                  title: entry.title,
                  subtitle: '谱面读不出,暂不可跟练',
                  enabled: false,
                ),
              },
            if (library.customStrum.isEmpty) const _CustomEmptyHint(),
            const SizedBox(height: 24),
            _sectionHeader(context, '指弹谱'),
            const SizedBox(height: 8),
            for (final entry in library.tab)
              _ChartCard(
                cardKey: 'tab-chart-${entry.id}',
                title: entry.chart.title,
                subtitle: tabChartMetaLine(entry.chart),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TabChartPage(chart: entry.chart),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _openStrumPractice(BuildContext context, StrumChart chart) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PracticePage(chart: chart)),
    );
  }
}

Widget _sectionHeader(BuildContext context, String text) {
  return Text(text, style: Theme.of(context).textTheme.titleMedium);
}

/// 弹唱谱区头:区名 + 文本导入入口(工单 16)+ 搜索源入口(工单 27
/// 原生搜索页;原站浏览兜底在搜索页右上角)。入口不依赖曲库数据,加载/
/// 错误态也在——导入只需和弦库,不被列表问题挡路。
Widget _strumSectionHeader(BuildContext context) {
  return Row(
    children: [
      _sectionHeader(context, '弹唱谱'),
      const Spacer(),
      TextButton.icon(
        onPressed:
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CifraClubSearchPage(),
              ),
            ),
        icon: const Icon(Icons.travel_explore),
        label: const Text('Cifra Club'),
      ),
      TextButton.icon(
        onPressed:
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TextImportPage()),
            ),
        icon: const Icon(Icons.post_add),
        label: const Text('导入'),
      ),
    ],
  );
}

/// 曲目卡片骨架:曲名 + 元信息行 + 尾标,弹唱/指弹/损坏降级三处共用。
/// [enabled] false = 坏谱条目:可见、标记、不可点(ListTile 无 onTap)。
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.cardKey,
    required this.title,
    this.subtitle,
    this.enabled = true,
    this.onTap,
  });

  final String cardKey;
  final String title;
  final String? subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key(cardKey),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing:
            enabled
                ? const Icon(Icons.chevron_right)
                : Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
        onTap: onTap,
      ),
    );
  }
}

/// 自建谱空态:还没有导入时的一行提示(工单 16 的导入入口落地后,
/// 导入完成即自动入列,提示退场)。
class _CustomEmptyHint extends StatelessWidget {
  const _CustomEmptyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(
        '还没有自建谱——文本导入后会自动出现在这里',
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
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
          Text('曲库加载失败', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('$error', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// 区段加载态:合流 provider 未就绪时的转圈。
class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      ),
    );
  }
}
