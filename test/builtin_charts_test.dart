import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_charts.dart';

/// 工单 07 seam：内置曲库清单 → 弹唱谱列表（纯加载器，资产读取注入）。
/// 真实资产的加载在 builtin_charts_asset_test 用普通 test() 走 rootBundle。
void main() {
  const allowed = {'C', 'G', 'Am', 'F'};

  test('清单按序产出弹唱谱，id 与歌名对应', () async {
    final charts = await BuiltInCharts.load(
      readAsset: (asset) async =>
          '{title: 测试歌 $asset}\n{start_of_chorus}\n[C]啦 [G]啦\n{end_of_chorus}\n',
      allowedChords: allowed,
    );

    expect(charts, hasLength(builtinChartCatalog.length));
    for (var i = 0; i < charts.length; i++) {
      expect(charts[i].id, builtinChartCatalog[i].id);
      expect(charts[i].chart.title, startsWith('测试歌 assets/charts/'));
    }
  });

  test('任一资产坏谱：当场抛错并指明是哪个资产', () {
    expect(
      () => BuiltInCharts.load(
        readAsset: (asset) async => asset.contains('cang-hai')
            ? '{start_of_verse}\n[C]没闭合\n'
            : '{title: ok}\n[C]啦\n',
        allowedChords: allowed,
      ),
      throwsA(
        isA<StateError>()
            .having((e) => e.message, 'message', contains('cang-hai'))
            .having((e) => e.message, 'message', contains('没有闭合')),
      ),
    );
  });
}
