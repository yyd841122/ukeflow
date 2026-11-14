import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/strum_chart.dart';
import '../../core/ui/load_error_view.dart';
import '../../core/ui/centered_hint.dart';
import '../../data/chart_providers.dart';
import '../../data/providers.dart';
import '../play/chart_meta.dart';
import '../play/flowing/flowing_gate_page.dart';
import '../play/practice_page.dart';
import '../play/tab_chart_page.dart';
import 'cifraclub_search_page.dart';
import 'text_import_page.dart';

/// 曲库类型目录:增加类型时在此添加一项,目录自动跟进。
enum LibraryCategory {
  strum('弹唱谱', Icons.queue_music),
  tab('指弹谱', Icons.music_note);

  const LibraryCategory(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// 各类型歌曲列表:入口与管理行为留在所属类型内,数据层保持原样。
class LibraryChartListPage extends ConsumerWidget {
  const LibraryChartListPage({
    super.key,
    required this.category,
  });

  final LibraryCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryProvider);
    // 独奏谱解析一次(卡片与空态共用,不重复扫曲库);导入谱与内置
    // 组合并列同列(工单 43,内置在前导入尾随)。
    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (category == LibraryCategory.strum) _strumActions(context),
          ...libraryAsync.when(
            loading: () => [const _SectionLoading()],
            error: (error, _) => [LoadErrorView(title: '曲库加载失败', error: error)],
            data: (library) => [
              if (category == LibraryCategory.strum) ...[
                for (final entry in library.builtinStrum)
                  _ChartCard(
                    cardKey: 'chart-${entry.id}',
                    title: entry.chart.title,
                    subtitle: chartMetaLine(entry.chart),
                    onTap: () => _openStrumPractice(context, entry.chart),
                    onDelete: () => _hideBuiltin(
                      context,
                      ref,
                      title: entry.chart.title,
                      hide: () => ref
                          .read(builtinChartVisibilityProvider)
                          .hideStrum(entry.id),
                    ),
                  ),
                for (final entry in library.customStrum)
                  switch (entry) {
                    ReadyCustomStrum() => _ChartCard(
                      cardKey: 'custom-chart-${entry.id}',
                      title: entry.title,
                      subtitle: _customSubtitle(entry.chart),
                      onTap: () => _openStrumPractice(context, entry.chart),
                      onDelete: () => _deleteCustom(context, ref, entry),
                    ),
                    BrokenCustomStrum() => _ChartCard(
                      cardKey: 'custom-chart-${entry.id}',
                      title: entry.title,
                      subtitle: '自建 · 谱面读不出,暂不可跟练',
                      enabled: false,
                      onDelete: () => _deleteCustom(context, ref, entry),
                    ),
                  },
                if (library.customStrum.isEmpty) const _CustomEmptyHint(),
              ],
              if (category == LibraryCategory.tab) ...[
                // 天空之城流水谱(ADR-0012 一手数据 MVP):器乐独奏编配,
                // 按实际曲谱归指弹谱类;入口过换歌体检闸(票08)。
                _ChartCard(
                  cardKey: 'flowing-sky-city',
                  title: '天空之城 · 流水谱',
                  subtitle: '一手数据 · 固定红线跟滚 + 示范声',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const FlowingScoreGatePage(),
                    ),
                  ),
                ),
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
                    onDelete: () => _hideBuiltin(
                      context,
                      ref,
                      title: entry.chart.title,
                      hide: () => ref
                          .read(builtinChartVisibilityProvider)
                          .hideTab(entry.id),
                    ),
                  ),

                // 体检自检:坏谱样例的三态报告演示(仅 debug,票08 真机
                // 回归口;release 不出现)。
                if (kDebugMode)
                  _ChartCard(
                    cardKey: 'flowing-selftest-broken',
                    title: '体检自检 · 坏谱样例',
                    subtitle: '换歌体检报告演示(仅调试)',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const FlowingScoreGatePage(
                          assetKey: 'assets/scores/selftest-broken.json',
                          selftest: true,
                        ),
                      ),
                    ),
                  ),

                if (library.tab.isEmpty)
                  const CenteredHint(
                    message: '暂无指弹谱',
                    detail: '隐藏的内置谱可在设置页恢复。',
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _openStrumPractice(BuildContext context, StrumChart chart) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => PracticePage(chart: chart)));
  }


  /// 删除确认框(工单 32):[confirmLabel] 定按钮词(真删「删除」/
  /// 隐藏「隐藏」),[dialogText] 讲清语义。返回 true = 用户确认。
  Future<bool> _confirmDelete(
    BuildContext context, {
    required String title,
    required String dialogText,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(dialogText),
        actions: [
          TextButton(
            key: const Key('delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// 内置谱删除 = 隐藏出曲库(工单 32):确认文案讲清「可恢复」,
  /// 恢复口在设置页。失败给可读 SnackBar,不静默。
  Future<void> _hideBuiltin(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required Future<void> Function() hide,
  }) async {
    final confirmed = await _confirmDelete(
      context,
      title: '把「$title」移出曲库?',
      dialogText: '内置谱只是从曲库隐藏,不删内容;可随时在设置页恢复。',
      confirmLabel: '隐藏',
    );
    if (!confirmed) return;
    try {
      await hide();
    } on Object catch (error) {
      debugPrint('UkeFlow: 内置谱隐藏失败 $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没移成——请再试一次')));
    }
  }

  /// 自建谱删除 = 数据库行硬删(工单 32;损坏条目同口,补齐工单 16
  /// 留下的自救路径)。确认文案明示不可恢复。
  Future<void> _deleteCustom(
    BuildContext context,
    WidgetRef ref,
    CustomStrumEntry entry,
  ) async {
    final confirmed = await _confirmDelete(
      context,
      title: '删除「${entry.title}」?',
      dialogText: '自建谱删除后不可恢复;备份文件里如有,可导入找回。',
      confirmLabel: '删除',
    );
    if (!confirmed) return;
    try {
      await ref.read(customChartsDaoProvider).deleteById(entry.id);
    } on Object catch (error) {
      debugPrint('UkeFlow: 自建谱删除失败 $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没删成——请再试一次')));
    }
  }

}

/// 命名对话框:控制器归 State 管(随路由销毁才 dispose——挂 whenComplete
/// 会在退场动画期把还在用的控制器收掉)。

/// 自建卡副标题:有元信息才带「 · 」;无元信息只标「自建」,
/// 不拿类型名凑数(页签与 AppBar 已是类型)。
String _customSubtitle(StrumChart chart) {
  final meta = chartMetaLine(chart);
  return meta == null ? '自建' : '自建 · $meta';
}


/// 弹唱谱列表操作:文本导入入口(工单 16)+ 搜索源入口(工单 27
/// 原生搜索页;原站浏览兜底在搜索页右上角)。入口不依赖曲库数据,加载/
/// 错误态也在——导入只需和弦库,不被列表问题挡路。
Widget _strumActions(BuildContext context) {
  return Row(
    children: [
      const Spacer(),
      TextButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CifraClubSearchPage()),
        ),
        icon: const Icon(Icons.travel_explore),
        label: const Text('Cifra Club'),
      ),
      TextButton.icon(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const TextImportPage())),
        icon: const Icon(Icons.post_add),
        label: const Text('导入'),
      ),
    ],
  );
}

/// 独奏谱列表操作:识谱源导入入口(工单 44)。入口不依赖曲库数据,
/// 加载/错误态也在。

/// 曲目卡片骨架:曲名 + 元信息行 + 尾标,弹唱/指弹/损坏降级三处共用。
/// [enabled] false = 坏谱条目:可见、标记、不可点(ListTile 无 onTap)。
class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.cardKey,
    required this.title,
    this.subtitle,
    this.enabled = true,
    this.onTap,
    this.onDelete,
  });

  final String cardKey;
  final String title;
  final String? subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  /// 删除入口(工单 32):非 null 才出删除钮——三类语义(真删/隐藏)
  /// 由调用方确认后处置,卡片只管呈现。key 取 delete-<卡片 key>,
  /// 机检/测试按同一前缀定位。
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key(cardKey),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onDelete != null)
              IconButton(
                key: Key('delete-$cardKey'),
                tooltip: '移出曲库',
                icon: const Icon(Icons.delete_outline),
                color: Theme.of(context).colorScheme.error,
                onPressed: onDelete,
              ),
            if (enabled)
              const Icon(Icons.chevron_right)
            else
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
          ],
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
