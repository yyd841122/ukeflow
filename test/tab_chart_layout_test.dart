import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/model/tab_chart.dart';
import 'package:ukeflow/features/play/tab_chart_layout.dart';

/// 工单 12 渲染缝(纯几何):四线谱布局「对照谱面数据」——弦序、音的
/// 横向位置(时值)、小节线全部从谱面数据推导,绘制层只做笔画。
void main() {
  test('弦序:1 弦(A)在最上、4 弦(G)在最下,与外部教学材料一致', () {
    // 纵向几何是常量,不随谱与缩放变。
    expect(TabChartLayout.stringY(1), lessThan(TabChartLayout.stringY(2)));
    expect(TabChartLayout.stringY(2), lessThan(TabChartLayout.stringY(3)));
    expect(TabChartLayout.stringY(3), lessThan(TabChartLayout.stringY(4)));
  });

  test('横向位置:音按拍位推进;小节线在每 4 拍整,恰与该拍音位重合', () {
    final layout = TabChartLayout(
      const TabChart(
        title: 't',
        tempo: 80,
        notes: [
          TabNote(string: 1, fret: 0, beat: 0),
          TabNote(string: 2, fret: 1, beat: 1),
          TabNote(string: 3, fret: 2, beat: 2.5),
        ],
      ),
      pxPerBeat: 40,
    );

    final x = [
      for (final beat in [0.0, 1.0, 2.5]) layout.noteX(beat),
    ];
    expect(x[1] - x[0], 40.0); // 一拍一档
    expect(x[2] - x[0], 100.0); // 半拍档

    // 小节线 0..n 共 n+1 条:第 k 条在拍 4k,与该拍音位同一 x(时值对读)。
    expect(layout.barX(0), layout.noteX(0));
    expect(layout.barX(1), layout.noteX(4));
    expect(layout.barX(2) - layout.barX(1), 4 * 40.0);
  });

  test('画布宽度覆盖整曲小节(末小节线可见),随 pxPerBeat 伸缩', () {
    final layout = TabChartLayout(
      loadBuiltinTabCharts().first.chart, // 小星星:12 小节
      pxPerBeat: 40,
    );
    expect(layout.totalBeats, 48);
    expect(layout.chartWidth, greaterThan(layout.barX(12)));
    // 同谱 pxPerBeat 减半 → 拍位跨度等比收窄(留白是常量),末线仍可见。
    final half = TabChartLayout(
      loadBuiltinTabCharts().first.chart,
      pxPerBeat: 20,
    );
    expect(
      (half.barX(12) - half.barX(0)) * 2,
      closeTo(layout.barX(12) - layout.barX(0), 0.01),
    );
    expect(half.chartWidth, greaterThan(half.barX(12)));
  });
}
