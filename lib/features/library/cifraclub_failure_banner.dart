import 'package:flutter/material.dart';

/// 提取/导入失败的可见横幅:原文直接展示,指路文本导入(与曲库错误同
/// 一哲学)。导入页/搜索页共用(工单 27 从 cifraclub_page 提出)。
class FailureBanner extends StatelessWidget {
  const FailureBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
