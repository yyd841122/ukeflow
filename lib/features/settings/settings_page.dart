import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_doc.dart';
import '../../core/ui/step_slider_control.dart';
import '../../data/chart_providers.dart';
import '../../data/providers.dart';
import '../../data/settings_providers.dart';
import 'backup_flow.dart';

/// 设置页(工单 20):A4 参考音(调音器消费)与默认 BPM(节拍器初始值/
/// 跟练无 tempo 谱回退)。后续设置的统一存放处——新设置在此加行,
/// 键与缺省值归 data/settings_providers。
///
/// 改动即时写透(状态+DAO,见 [AppSettingsController]):无保存钮,
/// 重启仍在。滑动连发即多次单行 upsert,量级无害。
///
/// 备份与恢复(工单 21):全量数据导出为单个 JSON 文件(系统保存框
/// 选目录落盘),导入恢复(导入即覆盖,确认对话框明示不可撤销)。
/// 流程编排与平台交互在 [BackupFlow](picker/save 注入缝,同工单 18 相册选图模式)。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, this.backupFlow});

  /// 备份流程注入缝(测试给假 picker/save;生产走系统选择器/保存框)。
  final BackupFlow? backupFlow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return ListView(
      // 页签页无 AppBar:顶部留白放宽,内容不贴状态栏(与调音器页同纪律)。
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        const SizedBox(height: 32),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('A4 参考音', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '调音的基准音;目标弦频率与判准随之换算',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                StepSliderControl(
                  value: settings.referenceA4,
                  min: minReferenceA4,
                  max: maxReferenceA4,
                  label: 'Hz',
                  keyPrefix: 'a4',
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setReferenceA4(v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('默认 BPM', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '节拍器的起始速度;无速度标记的谱进跟练时也用它',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                StepSliderControl(
                  value: settings.defaultBpm,
                  min: minDefaultBpm,
                  max: maxDefaultBpm,
                  label: 'BPM',
                  keyPrefix: 'default-bpm',
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setDefaultBpm(v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('备份与恢复', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '全部数据(曲谱/打卡/设置)导出为一个备份文件;导入会覆盖当前全部数据',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _exportBackup(context, ref),
                        icon: const Icon(Icons.save_alt),
                        label: const Text('导出备份'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () => _importBackup(context, ref),
                        icon: const Icon(Icons.restore),
                        label: const Text('导入备份'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const _HiddenChartsCard(),
      ],
    );
  }

  /// 导出:库全量 → JSON → 系统保存框由用户选目录落盘(SAF,免存储
  /// 权限)。await 期间不碰 ref/context——
  /// 服务与 messenger 在等待前取定,反馈走 messenger(异步回调纪律)。
  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final flow = backupFlow ?? BackupFlow();
    final service = ref.read(backupServiceProvider);
    try {
      final json = await service.collectJson();
      final outcome = await flow.export(json);
      switch (outcome) {
        case BackupSaved():
          _show(messenger, '备份已导出,可在文件管理器中查看');
        case BackupSaveCancelled():
          break; // 用户在保存框取消:静默。
        case BackupSaveFailed(:final message):
          _show(messenger, message);
      }
    } on Object catch (error, stackTrace) {
      debugPrint('UkeFlow: 备份导出失败 $error\n$stackTrace');
      _show(messenger, '备份导出失败——请再试一次');
    }
  }

  /// 导入:选文件→解析→确认对话框(导入即覆盖)→落库→设置行内值刷新。
  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final flow = backupFlow ?? BackupFlow();
    final service = ref.read(backupServiceProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final outcome = await flow.pickAndParse();
    BackupDoc? readyDoc;
    switch (outcome) {
      case BackupImportCancelled():
        return; // 用户取消:静默。
      case BackupImportFailed(:final message):
        _show(messenger, message);
        return;
      case BackupReadyToRestore(:final doc):
        readyDoc = doc;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入备份?'),
        content: const Text('导入会覆盖当前全部数据(曲谱/打卡/设置),此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('覆盖导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await service.restoreDoc(readyDoc);
      await settingsNotifier.reload();
      _show(messenger, '已导入备份,数据已覆盖');
    } on Object catch (error, stackTrace) {
      debugPrint('UkeFlow: 备份导入落库失败 $error\n$stackTrace');
      _show(messenger, '导入没成功——请再试一次');
    }
  }

  void _show(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}


/// 隐藏谱管理区(工单 32 内置三类 + 工单 43 导入独奏谱):曲库页删除
/// = 隐藏,恢复口在此。各隐藏集非空才出卡;每条给曲名(目录解析,
/// 目录里已删的陈年 id 以原样 id 呈现,恢复即清)与「恢复」钮,写回
/// 即曲库页回流。
class _HiddenChartsCard extends ConsumerWidget {
  const _HiddenChartsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Riverpod 3 AsyncValue.value 在 error 态返回 null:隐藏集读不到
    // 按空集呈现(恢复区退场,曲库页照旧),不在设置页顶错误。
    final hiddenStrums =
        ref.watch(hiddenBuiltinStrumsProvider).value ?? const <String>{};
    final hiddenTabs =
        ref.watch(hiddenBuiltinTabsProvider).value ?? const <String>{};
    final hiddenImages =
        ref.watch(hiddenBuiltinImagesProvider).value ?? const <String>{};
    final hiddenImported =
        ref.watch(hiddenImportedSolosProvider).value ?? const <String>{};
    if (hiddenStrums.isEmpty &&
        hiddenTabs.isEmpty &&
        hiddenImages.isEmpty &&
        hiddenImported.isEmpty) {
      return const SizedBox.shrink();
    }

    final strumTitles = {
      for (final c in ref.watch(builtinChartsProvider).value ?? const [])
        c.id: c.chart.title,
    };
    final tabTitles = {
      for (final t in ref.watch(builtinTabChartsProvider).value ?? const [])
        t.id: t.chart.title,
    };
    final imageTitles = {
      for (final c in builtinImageChartCatalog) c.id: c.title,
    };
    // 导入独奏谱曲名按行 id 解析(隐藏集存 id 十进制串;行已不存在的
    // 陈年 id 以原样 id 呈现)。
    final importedTitles = {
      for (final e in ref.watch(importedSoloChartsProvider).value
          ?? const <ImportedSoloEntry>[])
        e.id: e.title,
    };
    final visibility = ref.read(builtinChartVisibilityProvider);
    final importedVisibility = ref.read(importedSoloVisibilityProvider);

    final rows = <Widget>[
      for (final id in hiddenStrums)
        _HiddenRow(
          key: Key('hidden-strum-$id'),
          restoreKey: Key('restore-strum-$id'),
          title: strumTitles[id] ?? id,
          kind: '弹唱谱',
          onRestore: () => visibility.restoreStrum(id),
        ),
      for (final id in hiddenTabs)
        _HiddenRow(
          key: Key('hidden-tab-$id'),
          restoreKey: Key('restore-tab-$id'),
          title: tabTitles[id] ?? id,
          kind: '指弹谱',
          onRestore: () => visibility.restoreTab(id),
        ),
      for (final id in hiddenImages)
        _HiddenRow(
          key: Key('hidden-image-$id'),
          restoreKey: Key('restore-image-$id'),
          title: imageTitles[id] ?? id,
          kind: '图片谱',
          onRestore: () => visibility.restoreImage(id),
        ),
      for (final id in hiddenImported)
        _HiddenRow(
          key: Key('hidden-imported-solo-$id'),
          restoreKey: Key('restore-imported-solo-$id'),
          title: importedTitles[int.tryParse(id)] ?? id,
          kind: '导入独奏谱',
          onRestore: () => importedVisibility.restore(int.parse(id)),
        ),
    ];

    return Card(
      key: const Key('hidden-charts-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('隐藏的谱', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '在曲库页点删除移出的谱都在这里,点「恢复」回到曲库',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            ...rows,
          ],
        ),
      ),
    );
  }
}

/// 隐藏条目行:类型前缀 + 曲名 + 恢复钮。
class _HiddenRow extends StatelessWidget {
  const _HiddenRow({
    super.key,
    required this.restoreKey,
    required this.title,
    required this.kind,
    required this.onRestore,
  });

  /// 恢复钮 key(与行 key 分开,测试与机检定位用)。
  final Key restoreKey;
  final String title;
  final String kind;
  final Future<void> Function() onRestore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text('$kind · $title', overflow: TextOverflow.ellipsis),
        ),
        TextButton(
          key: restoreKey,
          onPressed: onRestore,
          child: const Text('恢复'),
        ),
      ],
    );
  }
}
