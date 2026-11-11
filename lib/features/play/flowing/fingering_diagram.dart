import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fingering_hint.dart';

/// 按法小图配色(跟流水谱画布同色系:网格灰绿/按位深绿)。
const _kGridColor = Color(0xFF8B9683);
const _kNoteColor = Color(0xFF374D3A);
const _kMutedColor = Color(0xFF617258);

/// 四线四品按法小图(票05;codex 同款几何,house style 跟画布和弦网格):
/// 左到右 = 4→1 弦,上粗线为琴枕,按位点实心、空弦圈悬在枕上,首按
/// 品位数字标行首;视框 150×105(按 [width] 等比缩放)。[notes] 空 =
/// 居中灰字「无法提示」——数据缺失显式标示,不猜测(票05 红线)。
class FingeringDiagram extends StatelessWidget {
  const FingeringDiagram({super.key, required this.notes, this.width = 150});

  final List<FingeringNote> notes;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 105 / 150;
    if (notes.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: Text('无法提示',
              style: TextStyle(color: _kMutedColor, fontSize: 13)),
        ),
      );
    }
    return CustomPaint(
      size: Size(width, height),
      painter: _FingeringPainter(notes: notes),
    );
  }
}

class _FingeringPainter extends CustomPainter {
  _FingeringPainter({required this.notes});

  final List<FingeringNote> notes;

  static const _viewW = 150.0;
  static const _viewH = 105.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _viewW, size.height / _viewH);
    final grid = Paint()
      ..color = _kGridColor
      ..strokeWidth = 0.8;
    // 横线 5 条(第一线琴枕加粗),纵弦 4 条(x=35,60,85,110;左=4弦)。
    for (var line = 0; line <= 4; line++) {
      final y = 25.0 + line * 17.5;
      if (line == 0) grid.strokeWidth = 1.6;
      canvas.drawLine(Offset(30, y), Offset(115, y), grid);
      if (line == 0) grid.strokeWidth = 0.8;
    }
    for (var i = 0; i < 4; i++) {
      final x = 35.0 + i * 25.0;
      canvas.drawLine(Offset(x, 25), Offset(x, 95), grid);
      _text(canvas, '${4 - i}弦', x, 13, _kMutedColor, 9,
          align: TextAlign.center);
    }
    // 首按品位(无按品则不标);行首数字。
    final pressed = notes.where((n) => n.fret > 0).toList();
    final first =
        pressed.isEmpty ? 1 : pressed.map((n) => n.fret).reduce(math.min);
    if (pressed.isNotEmpty) {
      _text(canvas, '$first', 5, 25 + 0.5 * 17.5, _kNoteColor, 10);
    }
    // 按位点:品位差 >3 出视框的照 codex 跳过(视框只显 4 品窗);
    // 空弦圈悬在枕上(白心描边)。
    final notePaint = Paint()..color = _kNoteColor;
    final openPaint = Paint()
      ..color = _kMutedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (final n in notes) {
      final x = 35.0 + (4 - n.stringNo) * 25.0;
      if (n.fret == 0) {
        canvas.drawCircle(Offset(x, 20), 4.5, openPaint);
      } else if (n.fret - first <= 3) {
        // 泛音不在图上另作标记(文本行按画面数字样式带 `<12>`)。
        canvas.drawCircle(
          Offset(x, 25 + (n.fret - first + 0.5) * 17.5),
          5,
          notePaint,
        );
      }
    }
  }

  void _text(Canvas canvas, String text, double x, double y, Color color,
      double fontSize,
      {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text, style: TextStyle(color: color, fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = align == TextAlign.center ? x - tp.width / 2 : x;
    tp.paint(canvas, Offset(dx, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(_FingeringPainter old) => true;
}
