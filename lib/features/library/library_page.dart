import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/strum_chart.dart';
import '../../data/chart_providers.dart';
import '../play/chart_meta.dart';
import '../play/practice_page.dart';
import '../play/tab_chart_page.dart';

/// 曲库页(工单 15):统一曲目列表,分区即曲谱类型——弹唱谱
/// (内置+自建,GLOSSARY「自建谱」导入后自动入列)与指弹谱(内置);
/// 点弹唱谱/指弹谱直达对应跟练。图片谱区归工单 18。
/// 三类曲目合流为一个 provider,加载/错误/空态在一处呈现。
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        ...libraryAsync.when(
          loading: () => [
            _sectionHeader(context, '弹唱谱'),
            const _SectionLoading(),
            _sectionHeader(context, '指弹谱'),
          ],
          error: (error, _) => [
            _sectionHeader(context, '弹唱谱'),
            _LibraryErrorView(error: error),
            _sectionHeader(context, '指弹谱'),
          ],
          data: (library) => [
            _sectionHeader(context, '弹唱谱'),
            const SizedBox(height: 8),
            for (final entry in library.builtinStrum)
              _StrumChartCard(
                cardKey: 'chart-${entry.id}',
                title: entry.chart.title,
                chart: entry.chart,
              ),
            for (final entry in library.customStrum)
              _StrumChartCard(
                cardKey: 'custom-chart-${entry.id}',
                title: entry.title,
                chart: entry.chart,
              ),
            if (library.customStrum.isEmpty) const _CustomEmptyHint(),
            const SizedBox(height: 24),
            _sectionHeader(context, '指弹谱'),
            const SizedBox(height: 8),
            for (final entry in library.tab) _TabChartCard(entry: entry),
          ],
        ),
      ],
    );
  }
}

Widget _sectionHeader(BuildContext context, String text) {
  return Text(text, style: Theme.of(context).textTheme.titleMedium);
}

/// 弹唱谱卡片:曲名 + 元信息行,点按进入跟练会话页。内置与自建同一待遇
/// (数据源接通后「同一列表」);自建的展示名来自入库命名,元信息取自源文本。
class _StrumChartCard extends StatelessWidget {
  const _StrumChartCard({
    required this.cardKey,
    required this.title,
    required this.chart,
  });

  final String cardKey;
  final String title;
  final StrumChart chart;

  @override
  Widget build(BuildContext context) {
    final meta = chartMetaLine(chart);
    return Card(
      key: Key(cardKey),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title),
        subtitle: meta != null ? Text(meta) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PracticePage(chart: chart)),
        ),
      ),
    );
  }
}

/// 指弹谱卡片:曲名 + 元信息行,点按进入指弹跟练会话页。
class _TabChartCard extends StatelessWidget {
  const _TabChartCard({required this.entry});

  final BuiltInTabChart entry;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('tab-chart-${entry.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(entry.chart.title),
        subtitle: Text(tabChartMetaLine(entry.chart)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TabChartPage(chart: entry.chart),
          ),
        ),
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
