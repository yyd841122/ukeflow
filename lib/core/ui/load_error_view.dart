import 'package:flutter/material.dart';

/// 数据加载失败的可见报错:错误原文直接展示,不带病进列表(工单 19
/// 评审提取:曲库页与和弦库页的两份同形收拢;标题各页自取)。
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({super.key, required this.title, required this.error});

  /// 一句话说明什么加载失败(如「曲库加载失败」)。
  final String title;

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: scheme.error),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('$error', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
