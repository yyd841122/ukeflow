import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chart/score_sheet_defs.dart';
import '../../core/model/strum_chart.dart';
import '../../core/model/tab_chart.dart';
import '../../core/ui/load_error_view.dart';
import '../../core/ui/centered_hint.dart';
import '../../data/chart_providers.dart';
import '../../data/providers.dart';
import '../play/chart_meta.dart';
import '../play/flowing/flowing_gate_page.dart';
import '../play/practice_page.dart';
import '../play/score_sheet_page.dart';
import '../play/tab_chart_page.dart';
import 'cifraclub_search_page.dart';
import 'score_source_import_flow.dart';
import 'score_source_import_page.dart';
import 'text_import_page.dart';

/// 一条独奏谱:组合定义 × 两层谱卡(主轴自曲库列表取=已滤隐藏集;
/// 旋律层自内置目录直取,是组合内部数据源不受列表可见性影响)。
typedef SoloChartEntry = ({
  ScoreSheetDef def,
  BuiltInTabChart tab,
  ({String id, TabChart chart}) melody,
});

/// 独奏谱列表:组合定义驱动,主轴谱卡被隐藏即整条出列。
List<SoloChartEntry> _soloEntries(List<BuiltInTabChart> tabCharts) => [
  for (final def in scoreSheetCatalog)
    for (final tab in tabCharts)
      if (tab.id == def.tabChartId)
        (
          def: def,
          tab: tab,
          melody: builtinTabChartCatalog.firstWhere(
            (entry) => entry.id == def.melodyChartId,
          ),
        ),
];

/// 曲库类型目录:增加类型时在此添加一项,目录自动跟进。
enum LibraryCategory {
  strum('弹唱谱', Icons.queue_music),
  tab('指弹谱', Icons.music_note),
  solo('独奏谱', Icons.piano);

  const LibraryCategory(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// 各类型歌曲列表:入口与管理行为留在所属类型内,数据层保持原样。
class LibraryChartListPage extends ConsumerWidget {
  const LibraryChartListPage({
    super.key,
    required this.category,
    this.scoreSourceImportFlow,
  });

  final LibraryCategory category;
  /// 识谱源导入流程(工单 44),注入缝同上。
  final ScoreSourceImportFlow? scoreSourceImportFlow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAsync = ref.watch(libraryProvider);
    // 独奏谱解析一次(卡片与空态共用,不重复扫曲库);导入谱与内置
    // 组合并列同列(工单 43,内置在前导入尾随)。
    final soloEntries = libraryAsync.maybeWhen(
      data: (library) => _soloEntries(library.tab),
      orElse: () => const <SoloChartEntry>[],
    );
    final importedSolos = libraryAsync.maybeWhen(
      data: (library) => library.importedSolos,
      orElse: () => const <ImportedSoloEntry>[],
    );
    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (category == LibraryCategory.strum) _strumActions(context),
          if (category == LibraryCategory.solo)
            _soloActions(
              context,
              onImport: () => _importScoreSource(context, ref),
            ),
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
              if (category == LibraryCategory.solo) ...[
                // 独奏谱(工单 39):组合定义驱动,点开默认进谱面视图;
                // 卡内次入口保留四线谱跟练(功能不砍)。可见性随主轴谱卡
                // 的隐藏集走,简谱旋律层是组合内部数据源,不受列表影响。
                for (final solo in soloEntries)
                  _ChartCard(
                    cardKey: 'solo-chart-${solo.def.id}',
                    title: solo.def.title,
                    subtitle: solo.def.subtitleLine(solo.tab.chart),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ScoreSheetPage(
                          def: solo.def,
                          tabChart: solo.tab.chart,
                          melodyChart: solo.melody.chart,
                        ),
                      ),
                    ),
                    actions: [
                      IconButton(
                        key: Key('solo-tab-entry-${solo.def.id}'),
                        tooltip: '四线谱跟练',
                        icon: const Icon(Icons.grid_on),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TabChartPage(chart: solo.tab.chart),
                          ),
                        ),
                      ),
                    ],
                    onDelete: () => _hideBuiltin(
                      context,
                      ref,
                      title: solo.def.title,
                      hide: () => ref
                          .read(builtinChartVisibilityProvider)
                          .hideTab(solo.def.tabChartId),
                    ),
                  ),
                // 导入独奏谱(工单 43):识谱源读出物化后与内置组合同等
                // 跟练(spec 故事 61/62);坏源降级为损坏条目(spec 故事
                // 65)——可见、不可跟练、源保留可重试。删除 = 隐藏,
                // 恢复口同在设置页。
                for (final entry in importedSolos)
                  switch (entry) {
                    ReadyImportedSolo() => _ChartCard(
                      cardKey: 'imported-solo-${entry.id}',
                      title: entry.title,
                      subtitle:
                          '导入 · '
                          '${entry.def.subtitleLine(entry.accompaniment)}',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ScoreSheetPage(
                            def: entry.def,
                            tabChart: entry.accompaniment,
                            melodyChart: entry.melody,
                            // 轻改入口随行 id 进页(工单 45)。
                            importedSoloRowId: entry.id,
                          ),
                        ),
                      ),
                      actions: [
                        IconButton(
                          key: Key('imported-solo-tab-entry-${entry.id}'),
                          tooltip: '四线谱跟练',
                          icon: const Icon(Icons.grid_on),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TabChartPage(
                                chart: entry.accompaniment,
                                importedSoloRowId: entry.id,
                              ),
                            ),
                          ),
                        ),
                      ],
                      onDelete: () => _hideImportedSolo(context, ref, entry),
                    ),
                    BrokenImportedSolo() => _ChartCard(
                      cardKey: 'imported-solo-${entry.id}',
                      title: entry.title,
                      subtitle: '导入 · 已损坏,暂不可跟练',
                      enabled: false,
                      onDelete: () => _hideImportedSolo(context, ref, entry),
                    ),
                  },

                if (soloEntries.isEmpty && importedSolos.isEmpty)
                  const CenteredHint(message: '暂无独奏谱', detail: '隐藏的谱可在设置页恢复。'),
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
                for (final entry in library.tab.where(
                  (entry) => !scoreSheetCatalog.any(
                    (def) => def.tabChartId == entry.id,
                  ),
                ))
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


  /// 识谱源导入入口(工单 44):选 JSON → 校验/查重 → 预览命名入库。
  /// 取消静默、坏源逐条人话对话框(可「重新选择」闭环——修源在电脑端
  /// 工作台,重选即重验)、同内容提示已有;合法源进预览页,落库后曲库
  /// 流自动入列。选文件环节的权限姿态见 score_source_import_flow.dart。
  Future<void> _importScoreSource(BuildContext context, WidgetRef ref) async {
    final flow =
        scoreSourceImportFlow ??
        ScoreSourceImportFlow(
          findDuplicateTitle: (sha) async =>
              (await ref
                      .read(importedSoloChartsDaoProvider)
                      .getByContentSha(sha))
                  ?.title,
        );
    final outcome = await flow.pickAndValidate();
    if (!context.mounted) return;
    switch (outcome) {
      case ScoreSourceCancelled():
        break;
      case ScoreSourceFailed(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case ScoreSourceDuplicate(:final existingTitle):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('曲库已有内容相同的谱「$existingTitle」,不用重复导入')),
        );
      case ScoreSourceInvalid(:final errors):
        await _showSourceErrors(context, ref, errors);
      case ScoreSourceReady ready:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ImportScoreSourcePage(ready: ready),
          ),
        );
    }
  }

  /// 校验阻塞清单(工单 44):逐条人话整屏列出。「重新选择」闭环回选
  /// 文件(修源在电脑端,源好了直接换);关闭退回列表。库无变动。
  Future<void> _showSourceErrors(
    BuildContext context,
    WidgetRef ref,
    List<String> errors,
  ) async {
    final retry = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('这份识谱源还进不了曲库'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final error in errors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('· $error'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('source-errors-close'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('关闭'),
          ),
          FilledButton(
            key: const Key('source-errors-retry'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('重新选择'),
          ),
        ],
      ),
    );
    if (retry == true && context.mounted) {
      await _importScoreSource(context, ref);
    }
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

  /// 导入独奏谱删除 = 隐藏出曲库(工单 43:校对成果不轻弃,源永久
  /// 保留在库,恢复口在设置页;损坏条目同口——隐藏不销毁,修源重导
  /// 入或管线演进后恢复即重试)。失败给可读 SnackBar,不静默。
  Future<void> _hideImportedSolo(
    BuildContext context,
    WidgetRef ref,
    ImportedSoloEntry entry,
  ) async {
    final confirmed = await _confirmDelete(
      context,
      title: '把「${entry.title}」移出曲库?',
      dialogText: '导入谱只是从曲库隐藏,不删内容;可随时在设置页恢复。',
      confirmLabel: '隐藏',
    );
    if (!confirmed) return;
    try {
      await ref.read(importedSoloVisibilityProvider).hide(entry.id);
    } on Object catch (error) {
      debugPrint('UkeFlow: 导入独奏谱隐藏失败 $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没移成——请再试一次')));
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
Widget _soloActions(BuildContext context, {required VoidCallback onImport}) {
  return Row(
    children: [
      const Spacer(),
      TextButton.icon(
        key: const Key('import-score-source'),
        onPressed: onImport,
        icon: const Icon(Icons.file_open_outlined),
        label: const Text('导入识谱源'),
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
    this.onDelete,
    this.actions = const <Widget>[],
  });

  final String cardKey;
  final String title;
  final String? subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  /// 卡内次操作(独奏谱的四线谱跟练次入口),排在删除钮之前。
  final List<Widget> actions;

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
            ...actions,
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
