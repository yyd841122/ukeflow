import 'package:flutter/material.dart';

import '../../core/audio/beat_scheduling.dart' show beatsPerBar;

import '../../core/model/tab_chart.dart';
import 'tab_chart_layout.dart';

/// 四线谱(GLOSSARY「指弹谱」的显示形式):四条弦线 + 小节线/拍位栅 +
/// 品位点(数字),音的横坐标即时值——全部几何出自 [TabChartLayout]
/// (纯函数),本组件与画笔只做笔画与滚动。
///
/// 工单 12 交付「能看」:静态读谱视图(横向滚动);逐音高亮与跟练
/// 归工单 13,届时复用本布局(高亮 = 换音点配色,几何不动)。
class TabChartView extends StatelessWidget {
  const TabChartView({super.key, required this.chart, this.pxPerBeat = 44});

  final TabChart chart;

  /// 一档拍位的像素宽(缩放系数;缺省 44,半拍音位留 22px 不粘连)。
  final double pxPerBeat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final layout = TabChartLayout(chart, pxPerBeat: pxPerBeat);
    return SizedBox(
      height: TabChartLayout.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧弦号列固定,横向滚动时读谱不失参照。
          CustomPaint(
            key: const Key('tab-chart-labels'),
            size: const Size(_labelWidth, TabChartLayout.height),
            painter: _StringLabelsPainter(scheme),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: CustomPaint(
                key: const Key('tab-chart-canvas'),
                size: Size(layout.chartWidth, TabChartLayout.height),
                painter: _TabChartPainter(layout, scheme),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 弦号标注列宽(①A…④G 紧凑排布)。
const _labelWidth = 40.0;

/// 弦号列:顶线 ①A 至底线 ④G(GLOSSARY「弦号」),y 与谱面弦线同一布局。
class _StringLabelsPainter extends CustomPainter {
  _StringLabelsPainter(this.scheme);

  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    const labels = ['①A', '②E', '③C', '④G'];
    for (var i = 0; i < labels.length; i++) {
      _text(
        canvas,
        labels[i],
        Offset(_labelWidth / 2, TabChartLayout.stringY(i + 1)),
        11,
        scheme.onSurfaceVariant,
      );
    }
  }

  @override
  bool shouldRepaint(_StringLabelsPainter oldDelegate) =>
      oldDelegate.scheme != scheme;
}

/// 谱面画笔:弦线、小节线(含小节号)、拍位栅、品位点。
class _TabChartPainter extends CustomPainter {
  _TabChartPainter(this.layout, this.scheme);

  final TabChartLayout layout;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final top = TabChartLayout.stringY(1);
    final bottom = TabChartLayout.stringY(4);

    // 弦线:贯穿画布的四条横线。
    final stringPaint = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    for (var s = 1; s <= 4; s++) {
      final y = TabChartLayout.stringY(s);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), stringPaint);
    }

    // 拍位栅:每拍一档的浅竖线(时值横向刻度),小节线位置让给强线。
    final tickPaint = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.10)
      ..strokeWidth = 1.0;
    for (var beat = 0; beat <= layout.totalBeats; beat++) {
      if (beat % beatsPerBar == 0) continue;
      final x = layout.noteX(beat.toDouble());
      canvas.drawLine(Offset(x, top), Offset(x, bottom), tickPaint);
    }

    // 小节线:每小节一条强竖线(0..barCount 共 barCount+1 条,末条是
    // 收束线),上方标小节号(1 起);收束线不是小节头,不标号。
    final barPaint = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.45)
      ..strokeWidth = 1.4;
    for (var bar = 0; bar <= layout.barCount; bar++) {
      final x = layout.barX(bar);
      canvas.drawLine(Offset(x, top - 6), Offset(x, bottom + 6), barPaint);
      if (bar < layout.barCount) {
        _text(
          canvas,
          '${bar + 1}',
          Offset(x, top - 11),
          10,
          scheme.onSurfaceVariant,
        );
      }
    }

    // 品位点:落在弦线上的实心圆,数字为品位(0 = 空弦)。
    for (final note in layout.notes) {
      final center = Offset(
        layout.noteX(note.beat),
        TabChartLayout.stringY(note.string),
      );
      canvas.drawCircle(
        center,
        TabChartLayout.noteRadius,
        Paint()..color = scheme.primary,
      );
      _text(
        canvas,
        '${note.fret}',
        center,
        TabChartLayout.noteRadius * 1.15,
        scheme.onPrimary,
      );
    }
  }

  @override
  bool shouldRepaint(_TabChartPainter oldDelegate) =>
      oldDelegate.layout != layout || oldDelegate.scheme != scheme;
}

void _text(
  Canvas canvas,
  String text,
  Offset center,
  double fontSize,
  Color color,
) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize, color: color, height: 1),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}
