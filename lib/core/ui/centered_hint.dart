import 'package:flutter/material.dart';

/// 居中提示:空态与轻量失败态共用的可读中文提示(工单 23 收拢:
/// 和弦搜索空态与 Cifra 搜索 idle/零结果/失败的四份同形)。整段居中、
/// 弱化色,不弹窗不打断——重操作(重试/换路径)由调用方另行给出。
class CenteredHint extends StatelessWidget {
  const CenteredHint({super.key, required this.message, this.detail});

  /// 一句话主提示(如「没有找到「x」」)。
  final String message;

  /// 可选的后续建议,换行缀在主提示后(如「换个歌名试试」);null = 无。
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          detail == null ? message : '$message\n$detail',
          textAlign: TextAlign.center,
          style: style,
        ),
      ),
    );
  }
}
