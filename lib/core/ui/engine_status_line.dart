import 'package:flutter/material.dart';

/// 引擎状态行:错误文案(可带原地重试钮)或就绪/初始化中一行(工单 19
/// 评审提取:节奏型训练页与两跟练会话页的三份同形收拢)。
class EngineStatusLine extends StatelessWidget {
  const EngineStatusLine({
    super.key,
    required this.ready,
    this.error,
    this.onRetry,
  });

  /// 引擎是否就绪(false 且无错误 = 初始化中)。
  final bool ready;

  /// 引擎错误文案(初始化失败/运行中引擎异常);null = 正常。
  final String? error;

  /// 错误态的重试回调(原地重试,不必重进页面);null = 不给重试钮。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (error != null) {
      return Column(
        children: [
          Text(
            error!,
            style: TextStyle(color: colorScheme.error),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('warmup-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ],
      );
    }
    return Text(
      ready ? '引擎就绪' : '引擎初始化中…',
      style: TextStyle(color: colorScheme.outline),
      textAlign: TextAlign.center,
    );
  }
}
