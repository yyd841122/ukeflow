import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/strum_chart.dart';
import '../../core/ui/load_error_view.dart';
import '../../data/chart_providers.dart';
import '../../data/providers.dart';
import '../play/chart_meta.dart';
import '../play/practice_page.dart';
import '../play/tab_chart_page.dart';
import '../rhythm/metronome_page.dart';
import '../rhythm/rhythm_trainer_page.dart';
import 'cifraclub_search_page.dart';
import 'image_chart_viewer_page.dart';
import 'image_pick_flow.dart';
import 'text_import_page.dart';

/// 曲库页(工单 15):练琴入口的唯一家——顶部练琴工具行(节拍器/节奏型
/// 训练,工单 15 后续自用户决策裁撤跟练页签并入于此),下方统一曲目列表,
/// 分区即曲谱类型:弹唱谱(内置+自建,GLOSSARY「自建谱」导入后自动入列)、
/// 指弹谱(内置)与图片谱(内置资产+相册入库,GLOSSARY「用户图片谱」,
/// 工单 18,只读见 ADR-0002);点弹唱谱/指弹谱直达对应跟练,点图片谱进
/// 只读查看器。四类曲目合流为一个 provider,加载/错误/空态在一处呈现;
/// 自建谱坏一条只标记一条,不牵连整库(见 chart_providers.dart)。
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key, this.imagePickFlow});

  /// 相册选图流程注入缝:默认生产实现(系统照片选择器+解码验真);
  /// UI 链测试注入打桩(引擎解码在测试 FakeAsync 区不走真异步,
  /// 选图+验真本身由 image_pick_flow_test 在真异步下覆盖)。
  final ImagePickFlow? imagePickFlow;

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
            LoadErrorView(title: '曲库加载失败', error: error),
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
            const SizedBox(height: 24),
            _imageSectionHeader(
              context,
              onPick: () => _pickImageChart(context, ref),
            ),
            const SizedBox(height: 8),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没存进曲库——请再试一次')),
          );
        }
    }
  }

  /// 命名入库(与文本导入同一纪律:展示名 = 入库命名)。预填选图器
  /// 给的文件名;留空确认则按当日日期给默认名。返回 null = 取消。
  Future<String?> _promptImageTitle(
    BuildContext context,
    String? suggested,
  ) {
    final now = DateTime.now();
    return showDialog<String>(
      context: context,
      builder:
          (_) => _ImageChartTitleDialog(
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
  });

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
      title: const Text('给这张图片谱起个名'),
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
        FilledButton(onPressed: _confirm, child: const Text('存入曲库')),
      ],
    );
  }
}

/// 图片谱区头:区名 + 相册选图入口。入口不依赖曲库数据,加载/错误态
/// 也在(选图只需相册,不被列表问题挡路)。内置图片谱保证区非空,
/// 不设空态提示。
Widget _imageSectionHeader(
  BuildContext context, {
  required VoidCallback onPick,
}) {
  return Row(
    children: [
      _sectionHeader(context, '图片谱'),
      const Spacer(),
      TextButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('相册选图'),
      ),
    ],
  );
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
