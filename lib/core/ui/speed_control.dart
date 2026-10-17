import 'package:flutter/material.dart';

/// 变速控制:原速百分比的滑杆,50%–100%、5% 一档(工单 13/19 评审提取:
/// 弹唱跟练页与指弹跟练会话页的两份逐字重复收拢;空闲与运行共用)。
class SpeedControl extends StatelessWidget {
  const SpeedControl({
    super.key,
    required this.speed,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  /// 变速比(1.0 = 原速)。
  final double speed;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final percent = (speed * 100).round();
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            '$percent%',
            key: const Key('speed-value'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: Slider(
            key: const Key('speed-slider'),
            value: speed,
            min: min,
            max: max,
            // 档位由本控件文档的「5% 一档」对范围推导,不靠调用方记数字。
            divisions: (((max - min) * 100) / 5).round(),
            label: '$percent%',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
