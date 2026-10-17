import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

/// 图片谱查看器(工单 18,GLOSSARY「图片谱」):photo_view 缩放平移,
/// 只读——图片谱不能跟练是 v1 物理边界(ADR-0002),本页不设任何跟练
/// 发起件,标题旁「只读」徽标把这个边界摆在明处。
class ImageChartViewerPage extends StatelessWidget {
  const ImageChartViewerPage({
    super.key,
    required this.title,
    required this.imageProvider,
  });

  final String title;
  final ImageProvider imageProvider;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            const _ReadOnlyBadge(),
          ],
        ),
      ),
      body: PhotoView(
        imageProvider: imageProvider,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        initialScale: PhotoViewComputedScale.contained,
        minScale: PhotoViewComputedScale.contained * 0.5,
        maxScale: PhotoViewComputedScale.contained * 8,
        loadingBuilder: (context, progress) =>
            const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, error, stackTrace) {
          // 入库前验过真,此处坏 = 存储损坏:原始报错落 logcat(缺陷
          // 可见,同自建谱坏条目的姿态),界面给可读文案,不白屏。
          debugPrint('UkeFlow: 图片谱加载失败 $error');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '图片加载失败——文件可能已损坏',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 只读徽标:小号描边章,一眼「能看不能跟练」。
class _ReadOnlyBadge extends StatelessWidget {
  const _ReadOnlyBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('image-chart-readonly-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: scheme.outline)),
      ),
      child: Text(
        '只读',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
