/// 内置图片谱清单(工单 18,GLOSSARY「图片谱」):随 App 交付、开箱
/// 可看(只读,ADR-0002——图片谱不能跟练是 v1 物理边界)。新增内置
/// 图片谱在此登记 + 资产放 assets/image_charts/(重生成脚本
/// tool/gen_builtin_image_chart.py)。
class BuiltinImageChart {
  const BuiltinImageChart({
    required this.id,
    required this.title,
    required this.assetPath,
  });

  /// 条目 id(如 `big-big-world-image`),测试 key 与日后引用用。
  final String id;

  /// 展示名(曲名后缀「(图片版)」与同名文本谱区分)。
  final String title;

  /// 资产路径(pubspec 已挂 assets/image_charts/)。
  final String assetPath;
}

/// 内置图片谱:Big Big World(图片版)——与内置弹唱谱同曲同内容
/// (生成自 assets/charts/big-big-world-strum.pro),对照「同曲文本谱可跟练、
/// 图片谱只读」的边界最直观。
const builtinImageChartCatalog = [
  BuiltinImageChart(
    id: 'big-big-world-image',
    title: 'Big Big World(图片版)',
    assetPath: 'assets/image_charts/big-big-world.png',
  ),
];
