import 'package:flutter/material.dart';

import '../../data/chord_library.dart';
import 'chord_diagram_layout.dart';

/// 和弦图（GLOSSARY：和弦指法的可视化）：琴格网 + 品位点（含手指编号）+
/// 空弦 ○ / 闷音 × 标记 + 横按条 + 起始品位标签。
class ChordDiagram extends StatelessWidget {
  const ChordDiagram({
    super.key,
    required this.fingering,
    this.width = 88,
    this.showStringLabels = false,
  });

  final ChordFingering fingering;

  /// 图宽；高按比例 1.3 倍（含弦枕上方标记区）。
  final double width;

  /// 琴格下方标注弦号与音名（④G ③C ②E ①A，GLOSSARY「弦号」）。
  /// 大图开启，浏览小图空间不够不开。
  final bool showStringLabels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size(width, width * 1.3),
      painter: _ChordDiagramPainter(
        ChordDiagramLayout(fingering),
        scheme,
        showStringLabels: showStringLabels,
      ),
    );
  }
}

class _ChordDiagramPainter extends CustomPainter {
  _ChordDiagramPainter(this.layout, this.scheme, {this.showStringLabels = false});

  final ChordDiagramLayout layout;
  final ColorScheme scheme;
  final bool showStringLabels;

  static const _strings = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final margin = size.width * 0.10;
    final markerR = size.width * 0.055;
    final topPad = markerR * 2.6;
    final bottomPad = showStringLabels ? size.width * 0.16 : size.width * 0.04;
    final stringSpacing = (size.width - margin * 2) / (_strings - 1);
    final fretSpacing = (size.height - topPad - bottomPad) / layout.fretsOnChord;
    final dotR = fretSpacing * 0.40;

    double stringX(int i) => margin + i * stringSpacing;
    double fretY(int row) => topPad + (row - 0.5) * fretSpacing; // row 从 1 起

    final line = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // 琴格网：4 弦 5 横档。
    for (var i = 0; i < _strings; i++) {
      canvas.drawLine(
        Offset(stringX(i), topPad),
        Offset(stringX(i), topPad + layout.fretsOnChord * fretSpacing),
        line,
      );
    }
    for (var r = 0; r <= layout.fretsOnChord; r++) {
      final y = topPad + r * fretSpacing;
      canvas.drawLine(Offset(margin, y), Offset(size.width - margin, y), line);
    }

    // 琴枕（第一品窗口）或起始品位标签。
    if (layout.showsNut) {
      canvas.drawLine(
        Offset(margin, topPad),
        Offset(size.width - margin, topPad),
        Paint()
          ..color = scheme.onSurface
          ..strokeWidth = size.width * 0.032
          ..style = PaintingStyle.stroke,
      );
    } else {
      _text(canvas, '${layout.baseFret}品', Offset(0, topPad - fretSpacing * 0.1),
          size.width * 0.075, scheme.onSurfaceVariant);
    }

    // 弦枕上方标记：○ 空弦 / × 闷音。
    final markerPaint = Paint()
      ..color = scheme.onSurfaceVariant
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < _strings; i++) {
      switch (layout.marks[i]) {
        case StringMark.open:
          canvas.drawCircle(Offset(stringX(i), markerR * 1.2), markerR, markerPaint);
        case StringMark.mute:
          final c = Offset(stringX(i), markerR * 1.2);
          canvas.drawLine(c - Offset(markerR, markerR), c + Offset(markerR, markerR), markerPaint);
          canvas.drawLine(c + Offset(markerR, -markerR), c + Offset(-markerR, markerR), markerPaint);
        case null:
          break;
      }
    }

    // 横按条（画在品位点下层，可有多条）。
    for (final barre in layout.barres) {
      final y = fretY(barre.row);
      final rect = Rect.fromPoints(
        Offset(stringX(barre.from) - dotR * 0.85, y - dotR * 0.62),
        Offset(stringX(barre.to) + dotR * 0.85, y + dotR * 0.62),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(dotR * 0.6)),
        Paint()..color = scheme.primary.withValues(alpha: 0.85),
      );
    }

    // 品位点 + 手指编号。
    for (final dot in layout.dots) {
      final center = Offset(stringX(dot.string), fretY(dot.row));
      canvas.drawCircle(center, dotR, Paint()..color = scheme.primary);
      if (dot.finger > 0) {
        _text(canvas, '${dot.finger}', center, dotR * 1.15, scheme.onPrimary);
      }
    }

    // 弦号 + 音名标注（④G ③C ②E ①A）。
    if (showStringLabels) {
      const labels = ['④G', '③C', '②E', '①A'];
      final gridBottom = topPad + layout.fretsOnChord * fretSpacing;
      final labelY = gridBottom + (size.height - gridBottom) / 2;
      for (var i = 0; i < 4; i++) {
        _text(
          canvas,
          labels[i],
          Offset(stringX(i), labelY),
          size.width * 0.072,
          scheme.onSurfaceVariant,
        );
      }
    }
  }

  void _text(Canvas canvas, String text, Offset center, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: color, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_ChordDiagramPainter oldDelegate) =>
      oldDelegate.layout != layout || oldDelegate.scheme != scheme;
}
