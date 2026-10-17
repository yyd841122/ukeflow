import 'package:flutter/material.dart';

/// 一行 N 个子项宽度均分(工单 05/19 评审提取:调音器四弦钮与和弦详情
/// 按法 chips 的公共壳)。
///
/// 水平内边距必须收小:M3 默认 24dp 会把四等分按钮的内宽挤到 ~18dp,
/// 「4弦」「按法 1」这类短标签被迫折行(真机 360dp 曾两处翻车,各带
/// 360dp 回归测试)。
class EqualRow extends StatelessWidget {
  const EqualRow({
    super.key,
    required this.children,
    this.horizontalPadding = 4,
  });

  /// 等分占满一行的子项;数量即等分数(调用方保证 ≥ 1)。
  final List<Widget> children;

  /// 每个子项左右的水平内边距(收小防折行,见类注释)。
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final child in children)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: child,
            ),
          ),
      ],
    );
  }
}
