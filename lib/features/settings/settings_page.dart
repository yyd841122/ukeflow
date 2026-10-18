import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup/backup_doc.dart';
import '../../core/ui/step_slider_control.dart';
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
