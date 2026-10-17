import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/step_slider_control.dart';
import '../../data/settings_providers.dart';

/// 设置页(工单 20):A4 参考音(调音器消费)与默认 BPM(节拍器初始值/
/// 跟练无 tempo 谱回退)。后续设置的统一存放处——新设置在此加行,
/// 键与缺省值归 data/settings_providers。
///
/// 改动即时写透(状态+DAO,见 [AppSettingsController]):无保存钮,
/// 重启仍在。滑动连发即多次单行 upsert,量级无害。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

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
      ],
    );
  }
}
