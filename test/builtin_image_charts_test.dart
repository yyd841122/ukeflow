import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_image_charts.dart';
import 'package:ukeflow/core/chart/image_ingest.dart';

/// 工单 18 内置图片谱目录:资产真实存在、可解码、元数据齐全——
/// 「内置资产入库」这条腿的验收面(缩放平移的 UI 面在 viewer 测试)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('目录非空,id 不重复,元数据齐全', () {
    expect(builtinImageChartCatalog, isNotEmpty);
    expect(
      builtinImageChartCatalog.map((c) => c.id).toSet(),
      hasLength(builtinImageChartCatalog.length),
      reason: '曲目 id 不得重复',
    );
    for (final chart in builtinImageChartCatalog) {
      expect(chart.title, isNotEmpty);
      expect(chart.assetPath, startsWith('assets/image_charts/'));
    }
  });

  test('每张内置图片谱资产真实存在且可解码(真实资产,非 fixture)', () async {
    for (final chart in builtinImageChartCatalog) {
      final bytes = await rootBundle.load(chart.assetPath);
      final size = await validateImageBytes(bytes.buffer.asUint8List());
      expect(size.width, greaterThan(0), reason: '${chart.assetPath} 宽度');
      expect(size.height, greaterThan(0), reason: '${chart.assetPath} 高度');
    }
  });
}
