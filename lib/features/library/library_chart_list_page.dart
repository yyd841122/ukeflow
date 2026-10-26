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
import '../play/practice_page.dart';
import '../play/score_sheet_page.dart';
import '../play/tab_chart_page.dart';
import 'cifraclub_search_page.dart';
import 'image_chart_viewer_page.dart';
import 'image_pick_flow.dart';
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
  solo('独奏谱', Icons.piano),
  image('图片谱', Icons.image_outlined);

  const LibraryCategory(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// 各类型歌曲列表:入口与管理行为留在所属类型内,数据层保持原样。
class LibraryChartListPage extends ConsumerWidget {
  const LibraryChartListPage({
    super.key,
    required this.category,
    this.imagePickFlow,
  });

  final LibraryCategory category;
  final ImagePickFlow? imagePickFlow;

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
          if (category == LibraryCategory.image)
            _imageActions(context, onPick: () => _pickImageChart(context, ref)),
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
                            builder: (_) =>
                                TabChartPage(chart: solo.tab.chart),
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
                      subtitle: '导入 · '
                          '${entry.def.subtitleLine(entry.accompaniment)}',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ScoreSheetPage(
                            def: entry.def,
                            tabChart: entry.accompaniment,
                            melodyChart: entry.melody,
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
                  const CenteredHint(
                    message: '暂无独奏谱',
                    detail: '隐藏的谱可在设置页恢复。',
                  ),
              ],
              if (category == LibraryCategory.tab) ...[
                // 「·独奏」版主轴归独奏谱类型(组合定义引用,工单 39),
                // 指弹谱列表只列旋律型。
                for (final entry in library.tab.where(
                  (entry) =>
                      !scoreSheetCatalog.any(
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

                if (library.tab.isEmpty)
                  const CenteredHint(
                    message: '暂无指弹谱',
                    detail: '隐藏的内置谱可在设置页恢复。',
                  ),
              ],
              if (category == LibraryCategory.image) ...[
                for (final entry in library.imageCharts)
                  _ChartCard(
                    cardKey: entry.cardKey,
                    title: entry.title,
                    subtitle: '图片谱 · 只读',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ImageChartViewerPage(
                          title: entry.title,
                          imageProvider: entry.imageProvider,
                        ),
                      ),
                    ),
                    onRename: entry is UserImageChartEntry
                        ? () => _renameUserImage(context, ref, entry)
                        : null,
                    onDelete: switch (entry) {
                      BuiltinImageChartEntry() => () => _hideBuiltin(
                        context,
                        ref,
                        title: entry.title,
                        hide: () => ref
                            .read(builtinChartVisibilityProvider)
                            .hideImage(entry.id),
                      ),
                      UserImageChartEntry() => () => _deleteUserImage(
                        context,
                        ref,
                        entry,
                      ),
                    },
                  ),

                if (library.imageCharts.isEmpty)
                  const CenteredHint(
                    message: '暂无图片谱',
                    detail: '可从相册选图入库,或在设置页恢复内置谱。',
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

  /// 相册选图入口(工单 18):选图 → 验真 → 命名 → 落库,曲库流
  /// 自动入列。取消静默、选图失败可读引导、坏图不入库(选图流程的
  /// 权限姿态见 image_pick_flow.dart:系统照片选择器按次授权,
  /// App 全程不申请存储权限);落库失败同样给可读引导,不静默。
  Future<void> _pickImageChart(BuildContext context, WidgetRef ref) async {
    final flow = imagePickFlow ?? ImagePickFlow();
    final outcome = await flow.pickAndValidate();
    if (!context.mounted) return;
    switch (outcome) {
      case ImagePickCancelled():
        break;
      case ImagePickFailed(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      case ImagePicked(:final bytes, :final suggestedTitle):
        final title = await _promptImageTitle(context, suggestedTitle);
        if (title == null || !context.mounted) return;
        try {
          await ref
              .read(imageChartsDaoProvider)
              .add(title: title, image: bytes);
        } on Object catch (error) {
          debugPrint('UkeFlow: 图片谱入库失败 $error');
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('没存进曲库——请再试一次')));
        }
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

  /// 用户图片谱删除 = 数据库行硬删(工单 32)。
  Future<void> _deleteUserImage(
    BuildContext context,
    WidgetRef ref,
    UserImageChartEntry entry,
  ) async {
    final confirmed = await _confirmDelete(
      context,
      title: '删除「${entry.title}」?',
      dialogText: '图片谱删除后不可恢复;备份文件里如有,可导入找回。',
      confirmLabel: '删除',
    );
    if (!confirmed) return;
    try {
      await ref.read(imageChartsDaoProvider).deleteById(entry.id);
    } on Object catch (error) {
      debugPrint('UkeFlow: 图片谱删除失败 $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没删成——请再试一次')));
    }
  }

  /// 已存图片谱改名只更新标题,保留原图与记录 id。
  Future<void> _renameUserImage(
    BuildContext context,
    WidgetRef ref,
    UserImageChartEntry entry,
  ) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _ImageChartTitleDialog(
        suggested: entry.title,
        fallbackTitle: entry.title,
        renaming: true,
      ),
    );
    if (title == null || !context.mounted) return;
    try {
      await ref.read(imageChartsDaoProvider).renameTitle(entry.id, title);
    } on Object catch (error) {
      debugPrint('UkeFlow: 图片谱改名失败 $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没改成——请再试一次')));
    }
  }

  /// 命名入库(与文本导入同一纪律:展示名 = 入库命名)。预填选图器
  /// 给的文件名;留空确认则按当日日期给默认名。返回 null = 取消。
  Future<String?> _promptImageTitle(BuildContext context, String? suggested) {
    final now = DateTime.now();
    return showDialog<String>(
      context: context,
      builder: (_) => _ImageChartTitleDialog(
        suggested: suggested,
        fallbackTitle: '图片谱 ${now.month}月${now.day}日',
      ),
    );
  }
}

/// 命名对话框:控制器归 State 管(随路由销毁才 dispose——挂 whenComplete
/// 会在退场动画期把还在用的控制器收掉)。
class _ImageChartTitleDialog extends StatefulWidget {
  const _ImageChartTitleDialog({
    required this.fallbackTitle,
    this.suggested,
    this.renaming = false,
  });

  final bool renaming;
  final String? suggested;
  final String fallbackTitle;

  @override
  State<_ImageChartTitleDialog> createState() => _ImageChartTitleDialogState();
}

class _ImageChartTitleDialogState extends State<_ImageChartTitleDialog> {
  late final _controller = TextEditingController(text: widget.suggested ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _controller.text.trim();
    Navigator.of(context).pop(text.isEmpty ? widget.fallbackTitle : text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.renaming ? '图片谱改名' : '给这张图片谱起个名'),
      content: TextField(
        key: const Key('image-chart-title-input'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: '如:歌名 / 来源页',
          labelText: '曲名',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('image-chart-title-save'),
          onPressed: _confirm,
          child: Text(widget.renaming ? '保存' : '存入曲库'),
        ),
      ],
    );
  }
}

/// 自建卡副标题:有元信息才带「 · 」;无元信息只标「自建」,
/// 不拿类型名凑数(页签与 AppBar 已是类型)。
String _customSubtitle(StrumChart chart) {
  final meta = chartMetaLine(chart);
  return meta == null ? '自建' : '自建 · $meta';
}

/// 图片谱列表操作:相册选图不依赖曲库数据,加载/错误态也可用。
Widget _imageActions(BuildContext context, {required VoidCallback onPick}) {
  return Row(
    children: [
      const Spacer(),
      TextButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('相册选图'),
      ),
    ],
  );
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
    this.onRename,
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
  final VoidCallback? onRename;

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
            if (onRename != null)
              IconButton(
                key: Key('rename-$cardKey'),
                tooltip: '改名',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onRename,
              ),
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
