import 'package:flutter/material.dart';

/// BPM 控件:步进(−/+)一行 + 滑杆一行(工单 19 评审提取:节奏型训练页
/// 与两跟练会话页的三份逐字重复收拢)。
///
/// [enabled] = false 时四件全部禁用(引擎未就绪不可定速);运行中是否
/// 可调由回调自己决定(控制器 setBpm 自带「运行中空操作」语义时,滑杆
/// 回弹原值,与提取前各页行为一致)。
class BpmControl extends StatelessWidget {
  const BpmControl({
    super.key,
    required this.bpm,
    required this.min,
    required this.max,
    required this.onChanged,
    this.enabled = true,
  });

  final int bpm;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const Key('bpm-minus'),
              onPressed: enabled ? () => onChanged(bpm - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 96,
              child: Text(
                '$bpm',
                key: const Key('bpm-value'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              key: const Key('bpm-plus'),
              onPressed: enabled ? () => onChanged(bpm + 1) : null,
              icon: const Icon(Icons.add),
            ),
            Text('BPM', style: TextStyle(color: outline)),
          ],
        ),
        Slider(
          key: const Key('bpm-slider'),
          value: bpm.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: '$bpm',
          onChanged: enabled ? (v) => onChanged(v.round()) : null,
        ),
      ],
    );
  }
}
