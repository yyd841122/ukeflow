import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/chart/score_sheet_defs.dart';
import '../../core/model/tab_chart.dart';
import '../../core/practice/score_sheet_layout.dart';
import '../chords/chord_diagram.dart';

/// 谱面视图渲染(GLOSSARY「谱面视图」)的组件层:**连续横带**——四层
/// 纵带(和弦图+和弦名 / TAB 伴奏 / 简谱旋律 / 歌词)排成一条横向长带,
/// 时值即距离,和弦图照印张居中压在其拍位正上方(与带首留气口)。
/// 几何全部出自 [ScoreSheetLayout](纯函数内核)。
///
/// 流水展示(用户真机反馈 2026-10-24):弹过的向左滑出、后面的从右补上,
/// 播放头恒在视口左 1/3——页面按引擎时刻逐帧驱动滚动位移(ADR-0005:
/// 无第二时间源)。性能双层:静态带(全部笔画+和弦图组件)在
/// [RepaintBoundary] 里光栅缓存,滚动只是合成器搬纹理;当位点亮画在
/// 独立的覆盖层,只有当前几个元素每帧小重绘。
class ScoreStripView extends StatelessWidget {
  const ScoreStripView({
    super.key,
    required this.def,
    required this.tabChart,
    required this.melodyChart,
    this.cursor,
    this.scrollController,
    this.layout,
  });

  final ScoreSheetDef def;
  final TabChart tabChart;
  final TabChart melodyChart;

  /// 跟随高亮当位;null = 静态读谱。
  final ScoreCursor? cursor;

  /// 横向滚动接管口(跟练自动跟滚用);null = 用户手动拖。
  final ScrollController? scrollController;

  /// 预建布局(页缓存注入则不再重复构造;缺省自建)。
  final ScoreSheetLayout? layout;

  double get _bandHeight => ScoreSheetLayout.chordBandHeight +
      ScoreSheetLayout.chordTabGap +
      ScoreSheetLayout.tabBandHeight +
      ScoreSheetLayout.numBandHeight +
      ScoreSheetLayout.lyricBandHeight +
      8;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final layout = this.layout ??
        ScoreSheetLayout(def: def, tabChart: tabChart, melodyChart: melodyChart);
    return SingleChildScrollView(
      key: const Key('score-strip-scroll'),
      controller: scrollController,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        key: const Key('score-strip'),
        width: layout.stripWidth,
        height: _bandHeight,
        child: Stack(
          children: [
            RepaintBoundary(
              child: CustomPaint(
                size: Size(layout.stripWidth, _bandHeight),
                painter: _StripPainter(layout, scheme),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                size: Size(layout.stripWidth, _bandHeight),
                painter: _StripHighlightPainter(layout, scheme, cursor),
              ),
            ),
            // 谱角调号(真 Text 进语义树;带首留白里,与首和弦有距离)。
            Positioned(
              left: 4,
              top: 0,
              child: Text(
                def.keySignature,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
            ),
            // 和弦图+和弦名照印张居中压在锚拍上(x 已在内核算定)。
            for (final glyph in layout.chordGlyphs)
              Positioned(
                left: glyph.x,
                top: 0,
                width: ScoreSheetLayout.chordGlyphWidth,
                child: _ChordGlyph(anchor: glyph.anchor),
              ),
          ],
        ),
      ),
    );
  }
}

/// 和弦位:名 + 图(44px 窗),纯静态(当位点亮归覆盖层画笔)。
class _ChordGlyph extends StatelessWidget {
  const _ChordGlyph({required this.anchor});

  final ScoreChordAnchor anchor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        children: [
          Text(
            anchor.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          ChordDiagram(fingering: anchor.fingering, width: 40),
        ],
      ),
    );
  }
}

/// 静态带画笔:小节线+小节号+拍位浅栅、TAB 弦线与 ×/品位数字、简谱符号
/// (度数/八度点/时值线/延音线弧/休止 0)、歌词、谱角。无当位状态——
/// 光栅缓存一次,滚动期零重绘。
class _StripPainter extends CustomPainter {
  _StripPainter(this.layout, this.scheme);

  final ScoreSheetLayout layout;
  final ColorScheme scheme;

  static const _numFontSize = ScoreSheetLayout.numFontSize;
  static const _lyricFontSize = ScoreSheetLayout.lyricFontSize;
  static const _tabFontSize = ScoreSheetLayout.tabFontSize;

  double get _tabTop => ScoreSheetLayout.tabBandTop;
  double get _numCenterY => ScoreSheetLayout.numCenterY;
  double get _lyricY => ScoreSheetLayout.lyricCenterY;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);
    _paintTab(canvas);
    _paintNumbered(canvas);
    _paintLyrics(canvas);
    // 全休止小节:四层皆无,简谱带画全休止 0。
    for (final bar in layout.emptyBars) {
      _text(canvas, '0',
          Offset(layout.barX(bar) + ScoreSheetLayout.stripPxPerBeat, _numCenterY),
          _numFontSize, scheme.onSurface.withValues(alpha: 0.55));
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final top = ScoreSheetLayout.chordBandHeight;
    final bottom = _lyricY + ScoreSheetLayout.lyricBandHeight / 2;
    // 拍位浅栅(时间流参照,极淡)。
    final tickPaint = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.06)
      ..strokeWidth = 1.0;
    for (var beat = 0; beat <= layout.barCount * 4; beat++) {
      if (beat % 4 == 0) continue;
      final x = layout.stripX(beat.toDouble());
      canvas.drawLine(Offset(x, _tabTop), Offset(x, bottom), tickPaint);
    }
    // 小节线 + 小节号。
    final barPaint = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.45)
      ..strokeWidth = 1.4;
    for (var bar = 0; bar <= layout.barCount; bar++) {
      final x = layout.barX(bar);
      canvas.drawLine(Offset(x, top), Offset(x, bottom), barPaint);
      if (bar < layout.barCount) {
        _text(canvas, '${bar + 1}', Offset(x + 3, _tabTop - 7), 9,
            scheme.onSurfaceVariant);
      }
    }
    // TAB 弦线。
    final stringPaint = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    for (var st = 1; st <= 4; st++) {
      final y = _tabTop + (st - 1) * ScoreSheetLayout.tabLineGap;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), stringPaint);
    }
  }

  void _paintTab(Canvas canvas) {
    for (final point in layout.tabPoints) {
      // 被扫弦/卷弦覆盖的逐弦 × 不画(事件位画箭头/波浪,见下)。
      if (point.hiddenByStrum) continue;
      final y =
          _tabTop + (point.note.string - 1) * ScoreSheetLayout.tabLineGap;
      final center = Offset(point.x, y);
      // 印张 ×(品位按当前和弦指形,图在其上方)或旋律品位数字。
      _text(canvas, point.isChordPluck ? '×' : '${point.note.fret}', center,
          _tabFontSize, scheme.onSurface);
    }
    // 扫弦/卷弦记号:直杆+箭头(下/上)、波浪(卷弦),压在事件拍位上。
    for (final e in layout.def.strums) {
      _paintStrumGlyph(canvas, layout.stripX(e.beat), e.kind);
    }
  }

  /// 扫弦记号:纵杆贯穿四弦,箭头指发声方向;卷弦画波浪(慢扫)。
  void _paintStrumGlyph(Canvas canvas, double x, ScoreStrumKind kind) {
    final top = _tabTop - 4;
    final bottom = _tabTop + 3 * ScoreSheetLayout.tabLineGap + 4;
    final paint = Paint()
      ..color = scheme.onSurface
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    switch (kind) {
      case ScoreStrumKind.roll:
        // 波浪:三段小弧连成的竖向 zigzag(慢扫)。
        final path = Path();
        var y = top;
        var dir = 1.0;
        path.moveTo(x, y);
        while (y < bottom) {
          y = math.min(y + 7, bottom);
          path.quadraticBezierTo(x + 5 * dir, y - 3.5, x, y);
          dir = -dir;
        }
        canvas.drawPath(path, paint..strokeWidth = 1.6);
      case ScoreStrumKind.strumDown:
        canvas.drawLine(Offset(x, top), Offset(x, bottom - 4), paint);
        canvas.drawPath(
          Path()
            ..moveTo(x - 5, bottom - 9)
            ..lineTo(x, bottom)
            ..lineTo(x + 5, bottom - 9),
          paint..strokeWidth = 1.8,
        );
      case ScoreStrumKind.strumUp:
        canvas.drawLine(Offset(x, top + 4), Offset(x, bottom), paint);
        canvas.drawPath(
          Path()
            ..moveTo(x - 5, top + 9)
            ..lineTo(x, top)
            ..lineTo(x + 5, top + 9),
          paint..strokeWidth = 1.8,
        );
    }
  }

  void _paintNumbered(Canvas canvas) {
    for (final point in layout.numPoints) {
      final symbol = point.symbol;
      final x = point.x + 2;
      _text(canvas, '${symbol.degree}', Offset(x, _numCenterY), _numFontSize,
          scheme.onSurface, alignLeft: true);

      final dotPaint = Paint()..color = scheme.onSurface;
      for (var d = 0; d < symbol.highDots; d++) {
        canvas.drawCircle(
          Offset(x + 4, _numCenterY - _numFontSize / 2 - 3 - d * 3.5), 1.4,
          dotPaint);
      }
      for (var d = 0; d < symbol.lowDots; d++) {
        canvas.drawCircle(
          Offset(x + 4, _numCenterY + _numFontSize / 2 + 3 + d * 3.5), 1.4,
          dotPaint);
      }
      _paintDurationMark(canvas, x, symbol);
      if (symbol.arcOut) _paintArc(canvas, point);
      if (symbol.restAfter != null) _paintRest(canvas, point);
    }
  }

  void _paintDurationMark(Canvas canvas, double x, NumNote symbol) {
    final topY = _numCenterY + _numFontSize / 2 + 2;
    final color = scheme.onSurface;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (var i = 0; i < symbol.underlines; i++) {
      canvas.drawLine(
          Offset(x, topY + i * 3.2), Offset(x + 11, topY + i * 3.2), paint);
    }
    if (symbol.dotted) {
      canvas.drawCircle(Offset(x + 14, topY - 4), 1.5,
          paint..style = PaintingStyle.fill);
    }
    for (var i = 0; i < symbol.dashes; i++) {
      canvas.drawLine(Offset(x + 6 + i * 14, topY - 4),
          Offset(x + 18 + i * 14, topY - 4), paint);
    }
  }

  void _paintArc(Canvas canvas, ScoreNumPoint point) {
    final nextIndex = point.noteIndex + 1;
    var nextX = nextIndex < layout.numPoints.length
        ? layout.stripX(layout.numPoints[nextIndex].symbol.mainBeat)
        : layout.stripWidth;
    final color = scheme.onSurface.withValues(alpha: 0.7);
    final path = Path()
      ..moveTo(point.x + 7, _numCenterY - _numFontSize / 2 - 8)
      ..quadraticBezierTo(
        (point.x + 7 + nextX) / 2,
        _numCenterY - _numFontSize / 2 - 13,
        nextX + 5,
        _numCenterY - _numFontSize / 2 - 8,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  }

  void _paintRest(Canvas canvas, ScoreNumPoint point) {
    final rest = point.symbol.restAfter!;
    final restX = point.x + ScoreSheetLayout.stripPxPerBeat;
    final mark = durationMarkOf(rest);
    final color = scheme.onSurface.withValues(alpha: 0.55);
    _text(canvas, '0', Offset(restX, _numCenterY), _numFontSize, color,
        alignLeft: true);
    final topY = _numCenterY + _numFontSize / 2 + 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (var i = 0; i < mark.underlines; i++) {
      canvas.drawLine(
          Offset(restX, topY + i * 3.2), Offset(restX + 11, topY + i * 3.2),
          paint);
    }
    if (mark.dotted) {
      canvas.drawCircle(Offset(restX + 14, topY - 4), 1.5,
          paint..style = PaintingStyle.fill);
    }
    for (var i = 0; i < mark.dashes; i++) {
      canvas.drawLine(Offset(restX + 6 + i * 14, topY - 4),
          Offset(restX + 18 + i * 14, topY - 4), paint);
    }
  }

  void _paintLyrics(Canvas canvas) {
    for (final point in layout.numPoints) {
      final lyric = point.symbol.lyric;
      if (lyric == null) continue;
      _text(canvas, lyric, Offset(point.x + 2, _lyricY), _lyricFontSize,
          scheme.onSurface, alignLeft: true);
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) => old.layout != layout;
}

/// 当位覆盖层(GLOSSARY「跟随高亮」):只有当前几个元素每帧重绘——
/// 当前和弦图描边、TAB 当前音主色圆、简谱当前音/歌词字重绘主色。
class _StripHighlightPainter extends CustomPainter {
  _StripHighlightPainter(this.layout, this.scheme, this.cursor);

  final ScoreSheetLayout layout;
  final ColorScheme scheme;
  final ScoreCursor? cursor;

  // 纵带 y 与字号一律取自内核单源——与静态带逐像素同位
  //(真机教训:间距调整后覆盖层公式没跟上,当前音/歌词错位 8px)。
  double get _tabTop => ScoreSheetLayout.tabBandTop;

  @override
  void paint(Canvas canvas, Size size) {
    final cursor = this.cursor;
    if (cursor == null) return;

    // 当前和弦图描边。
    if (cursor.chordIndex >= 0 && cursor.chordIndex < layout.chordGlyphs.length) {
      final g = layout.chordGlyphs[cursor.chordIndex];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(g.x, 0, ScoreSheetLayout.chordGlyphWidth, 66),
          const Radius.circular(6),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = scheme.primary,
      );
    }

    // TAB 当前音(同拍组一齐点亮,与四线谱跟练同纪律)。
    if (cursor.tabIndex >= 0 && cursor.tabIndex < layout.tabPoints.length) {
      final currentBeat = layout.tabNotes[cursor.tabIndex].beat;
      for (final point
          in layout.tabPoints.where((p) => p.note.beat == currentBeat)) {
        final y =
            _tabTop + (point.note.string - 1) * ScoreSheetLayout.tabLineGap;
        final center = Offset(point.x, y);
        canvas.drawCircle(center, 10.5, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = scheme.primary);
        canvas.drawCircle(center, 8, Paint()..color = scheme.primary);
        _text(canvas, point.isChordPluck ? '×' : '${point.note.fret}', center,
            ScoreSheetLayout.tabFontSize, scheme.onPrimary, bold: true);
      }
    }

    // 简谱当前音与歌词字:原位重绘主色(盖过静态层同位笔画)。
    if (cursor.melodyIndex >= 0 &&
        cursor.melodyIndex < layout.numPoints.length) {
      final point = layout.numPoints[cursor.melodyIndex];
      final symbol = point.symbol;
      final x = point.x + 2;
      _text(canvas, '${symbol.degree}', Offset(x, ScoreSheetLayout.numCenterY),
          ScoreSheetLayout.numFontSize, scheme.primary, bold: true,
          alignLeft: true);
      final dotPaint = Paint()..color = scheme.primary;
      for (var d = 0; d < symbol.highDots; d++) {
        canvas.drawCircle(
          Offset(x + 4, ScoreSheetLayout.numCenterY -
              ScoreSheetLayout.numFontSize / 2 - 3 - d * 3.5), 1.4, dotPaint);
      }
      for (var d = 0; d < symbol.lowDots; d++) {
        canvas.drawCircle(
          Offset(x + 4, ScoreSheetLayout.numCenterY +
              ScoreSheetLayout.numFontSize / 2 + 3 + d * 3.5), 1.4, dotPaint);
      }
      if (symbol.lyric != null) {
        _text(canvas, symbol.lyric!, Offset(point.x + 2,
            ScoreSheetLayout.lyricCenterY), ScoreSheetLayout.lyricFontSize,
            scheme.primary, bold: true, alignLeft: true);
      }
    }
  }

  @override
  bool shouldRepaint(_StripHighlightPainter old) =>
      old.layout != layout || old.cursor != cursor;
}

void _text(
  Canvas canvas,
  String text,
  Offset at,
  double fontSize,
  Color color, {
  bool bold = false,
  bool alignLeft = false,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        height: 1,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  try {
    final origin = alignLeft
        ? Offset(at.dx, at.dy - tp.height / 2)
        : at - Offset(tp.width / 2, tp.height / 2);
    tp.paint(canvas, origin);
  } finally {
    tp.dispose(); // 播放期绘制,原生段落即时释放(与四线谱画笔同纪律)。
  }
}
