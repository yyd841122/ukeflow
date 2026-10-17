import 'package:flutter/material.dart';

/// 步进(−/+)+滑杆控件:一行步进带值与单位、一行滑杆(工单 19 评审提取
/// 的 BPM 控件,工单 20 参数化通用化:设置页 A4/默认 BPM 同形复用)。
///
/// [enabled] = false 时四件全部禁用(引擎未就绪不可定速);运行中是否
/// 可调由回调自己决定(控制器 setBpm 自带「运行中空操作」语义时,滑杆
/// 回弹原值,与提取前各页行为一致)。
class StepSliderControl extends StatelessWidget {
  const StepSliderControl({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.label = '',
    this.keyPrefix = 'value',
    this.enabled = true,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  /// 单位标注(如 'BPM'/'Hz');空串不显示。
  final String label;

  /// 测试 key 前缀:`<keyPrefix>-minus/-plus/-value/-slider`。同页多行
  /// (设置页 A4/默认 BPM)各用各的前缀,防跨行误定位。
  final String keyPrefix;

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
              key: Key('$keyPrefix-minus'),
              onPressed: enabled ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 96,
              child: Text(
                '$value',
                key: Key('$keyPrefix-value'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              key: Key('$keyPrefix-plus'),
              onPressed: enabled ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add),
            ),
            if (label.isNotEmpty) Text(label, style: TextStyle(color: outline)),
          ],
        ),
        Slider(
          key: Key('$keyPrefix-slider'),
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          label: '$value',
          onChanged: enabled ? (v) => onChanged(v.round()) : null,
        ),
      ],
    );
  }
}
