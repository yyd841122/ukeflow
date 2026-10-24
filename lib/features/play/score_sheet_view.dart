import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/chart/score_sheet_defs.dart';
import '../../core/model/tab_chart.dart';
import '../../core/practice/score_sheet_layout.dart';
import '../chords/chord_diagram.dart';

/// 谱面视图渲染(GLOSSARY「谱面视图」)的组件层:单行(谱表系统)视图 +
/// 系统画笔。几何全部出自 [ScoreSheetLayout](纯函数内核),组件只做笔画、
/// 和弦图组件落位——和弦图复用 ChordDiagram 自绘(工单 37 台账手读指形)。
/// 整页纵滚视图已删(真机反馈跟练整页易乱,2026-10-24:弹前读谱与跟练
/// 都只出一行;整页排版能力保留在布局内核,要全谱浏览再从 git 复活)。
/// 单系统视图(运行态,GLOSSARY「谱表系统」):只画当前一行四层——
/// 真机跟练视线只有一行,播完切下一行(用户真机反馈 2026-10-24:整页
/// 折行难追播放点;与四线谱跟练的阶梯平移同一「以静为主」纪律)。几何
/// 与整页共用 [ScoreSheetLayout] 与同一画笔。
class ScoreSheetSystemView extends StatelessWidget {
  const ScoreSheetSystemView({
    super.key,
    required this.def,
    required this.tabChart,
    required this.melodyChart,
    required this.system,
    this.cursor,
    this.layout,
  });

  final ScoreSheetDef def;
  final TabChart tabChart;
  final TabChart melodyChart;

  /// 当前系统号(播放头所在行)。
  final int system;

  final ScoreCursor? cursor;

  /// 预建布局(页缓存注入则不再按帧重建/重排序;缺省自建)。
  final ScoreSheetLayout? layout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = this.layout ??
            ScoreSheetLayout(
              def: def,
              tabChart: tabChart,
              melodyChart: melodyChart,
              contentWidth: constraints.maxWidth,
            );
        return SizedBox(
          key: const Key('score-sheet-line'),
          width: constraints.maxWidth,
          height: ScoreSheetLayout.systemHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ScoreSystemPainter(
                    layout,
                    system.clamp(0, math.max(0, layout.systemCount - 1)),
                    scheme,
                    cursor,
                    originY: 0,
                  ),
                ),
              ),
              // 谱角调号每行都标(单行视口换行时不失调号语境)。
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
              for (final glyph in layout.chordsInSystem(system))
                Positioned(
                  left: glyph.x,
                  top: 0,
                  width: ScoreSheetLayout.chordGlyphWidth,
                  child: _ChordGlyph(
                    anchor: glyph.anchor,
                    highlighted:
                        cursor != null && cursor!.chordIndex == glyph.anchorIndex,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 和弦位:名 + 图(44px 窗),当前位描边点亮。
class _ChordGlyph extends StatelessWidget {
  const _ChordGlyph({required this.anchor, required this.highlighted});

  final ScoreChordAnchor anchor;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: highlighted
          ? BoxDecoration(
              border: Border.all(color: scheme.primary, width: 2),
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        children: [
          Text(
            anchor.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
              color: highlighted ? scheme.primary : scheme.onSurface,
            ),
          ),
          ChordDiagram(fingering: anchor.fingering, width: 40),
        ],
      ),
    );
  }
}

/// 系统画笔:小节线(纵贯四层)+ 小节号 + TAB 弦线与品位点 + 简谱符号
/// (度数/八度点/时值线/延音线弧/休止 0)+ 歌词缀字 + 谱角调号(首系统)。
/// 带当位时按三级配色(当前/已过/未到),几何不动。
class _ScoreSystemPainter extends CustomPainter {
  _ScoreSystemPainter(
    this.layout,
    this.system,
    this.scheme,
    this.cursor, {
    required this.originY,
  });

  final ScoreSheetLayout layout;
  final int system;
  final ColorScheme scheme;
  final ScoreCursor? cursor;

  /// 本系统在画布上的纵原点:整页画布 = system×系统高;单行画布恒 0
  /// (画布只有一个系统高,再带系统偏移会把四层全画到画布外——真机
  /// 第 2 行起只余和弦图组件的教训)。
  final double originY;

  static const _numFontSize = 14.0;
  static const _lyricFontSize = 11.0;
  static const _tabFontSize = 10.0;

  double get _y0 => originY;

  double get _tabTop =>
      _y0 +
      ScoreSheetLayout.chordBandHeight +
      ScoreSheetLayout.chordTabGap +
      ScoreSheetLayout.tabTopPad;

  /// 简谱带纵排:高音点(8)→ 度数(14)→ 时值线(6),带高 30。
  double get _numBandTop => _y0 +
      ScoreSheetLayout.chordBandHeight +
      ScoreSheetLayout.tabBandHeight;

  double get _numCenterY => _numBandTop + 8 + _numFontSize / 2;

  double get _lyricY =>
      _numBandTop + ScoreSheetLayout.numBandHeight + ScoreSheetLayout.lyricBandHeight / 2;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBarlines(canvas);
    _paintTab(canvas);
    _paintNumbered(canvas);
    _paintLyrics(canvas);
  }

  void _paintBarlines(Canvas canvas) {
    final top = _y0;
    final bottom =
        _y0 + ScoreSheetLayout.systemHeight - ScoreSheetLayout.systemGap;
    final barPaint = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.45)
      ..strokeWidth = 1.4;
    final first = layout.firstBarOfSystem(system);
    for (var b = 0; b <= layout.barsInSystem(system); b++) {
      final x = layout.barXInSystem(system, first + b);
      canvas.drawLine(Offset(x, top), Offset(x, bottom), barPaint);
      if (b < layout.barsInSystem(system)) {
        _text(canvas, '${first + b + 1}', Offset(x + 8, _tabTop - 7), 9,
            scheme.onSurfaceVariant);
      }
    }
    // 全休止小节:四层皆无,简谱带画全休止 0。
    for (final bar in layout.emptyBars) {
      if (layout.systemOfBar(bar) != system) continue;
      final x = layout.barXInSystem(system, bar);
      _text(
        canvas,
        '0',
        Offset(
          x + layout.barWidth / 2,
          _numCenterY,
        ),
        _numFontSize,
        scheme.onSurface.withValues(alpha: 0.55),
      );
    }
  }

  void _paintTab(Canvas canvas) {
    final stringPaint = Paint()
      ..color = scheme.onSurface.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;
    for (var s = 1; s <= 4; s++) {
      final y = _tabTop + (s - 1) * ScoreSheetLayout.tabLineGap;
      canvas.drawLine(Offset(0, y), Offset(layout.contentWidth, y), stringPaint);
    }
    final currentIndex = cursor?.tabIndex ?? -1;
    final currentBeat = currentIndex < 0 || currentIndex >= layout.tabNotes.length
        ? null
        : layout.tabNotes[currentIndex].beat;
    for (final point in layout.tabInSystem(system)) {
      final isCurrent = currentBeat != null && point.note.beat == currentBeat;
      final isPast = currentBeat != null && point.note.beat < currentBeat;
      final y = _tabTop + (point.note.string - 1) * ScoreSheetLayout.tabLineGap;
      final center = Offset(point.x, y);
      final Color label;
      if (isCurrent) {
        final r = 8.0;
        canvas.drawCircle(center, r + 2.5, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = scheme.primary);
        canvas.drawCircle(center, r, Paint()..color = scheme.primary);
        label = scheme.onPrimary;
      } else {
        label = isPast
            ? scheme.onSurface.withValues(alpha: 0.35)
            : scheme.onSurface;
      }
      // 印张 ×(品位按当前和弦指形,图在行首)或旋律品位数字。
      _text(canvas, point.isChordPluck ? '×' : '${point.note.fret}', center,
          _tabFontSize, label, bold: isCurrent);
    }
  }

  void _paintNumbered(Canvas canvas) {
    final currentIndex = cursor?.melodyIndex ?? -1;
    final points = layout.numberedInSystem(system);
    for (final point in points) {
      final isCurrent = cursor != null && point.noteIndex == currentIndex;
      final isPast =
          cursor != null && point.noteIndex < currentIndex;
      final color = isCurrent
          ? scheme.primary
          : (isPast ? scheme.onSurface.withValues(alpha: 0.30) : scheme.onSurface);
      final x = point.x + 2;
      final symbol = point.symbol;
      _text(canvas, '${symbol.degree}', Offset(x, _numCenterY), _numFontSize,
          color, bold: isCurrent, alignLeft: true);

      // 八度点:上/下小圆点,叠在度数正上方/下方。
      final dotPaint = Paint()..color = color;
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
      _paintDurationMark(
        canvas, x, _numCenterY + _numFontSize / 2 + 2, symbol.underlines,
        symbol.dotted, symbol.dashes, color);

      // 延音线/连音弧:到后继延续音,弧顶在度数上方。
      if (symbol.arcOut) {
        final nextIndex = point.noteIndex + 1;
        var nextX = nextIndex < layout.numberedNotes.length
            ? layout.beatXInSystem(system,
                layout.numberedNotes[nextIndex].mainBeat)
            : layout.contentWidth;
        // 后继在下一系统时 beatXInSystem 为负:弧收行尾(主轴拍位经
        // NumNote.mainBeat,已含旋律层对齐偏移)。
        _arc(canvas, Offset(x + 5, _numCenterY - _numFontSize / 2 - 8),
            Offset(math.min(nextX + 5, layout.contentWidth),
                _numCenterY - _numFontSize / 2 - 8),
            color.withValues(alpha: 0.7));
      }

      // 休止 0:延续音满 1 拍后的余量,带自己的时值标记。
      final rest = symbol.restAfter;
      if (rest != null) {
        final restX = x + layout.pxPerBeat;
        final mark = durationMarkOf(rest);
        _text(canvas, '0', Offset(restX, _numCenterY), _numFontSize,
            scheme.onSurface.withValues(alpha: 0.55), alignLeft: true);
        _paintDurationMark(canvas, restX,
            _numCenterY + _numFontSize / 2 + 2, mark.underlines, mark.dotted,
            mark.dashes, scheme.onSurface.withValues(alpha: 0.55));
      }
    }
  }

  void _paintDurationMark(
    Canvas canvas,
    double x,
    double topY,
    int underlines,
    bool dotted,
    int dashes,
    Color color,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (var i = 0; i < underlines; i++) {
      canvas.drawLine(
          Offset(x, topY + i * 3.2), Offset(x + 11, topY + i * 3.2), paint);
    }
    if (dotted) {
      canvas.drawCircle(Offset(x + 14, topY - 4), 1.5, paint..style = PaintingStyle.fill);
    }
    for (var i = 0; i < dashes; i++) {
      canvas.drawLine(Offset(x + 6 + i * 14, topY - 4),
          Offset(x + 18 + i * 14, topY - 4), paint);
    }
  }

  void _paintLyrics(Canvas canvas) {
    final currentIndex = cursor?.melodyIndex ?? -1;
    for (final point in layout.numberedInSystem(system)) {
      final lyric = point.symbol.lyric;
      if (lyric == null) continue;
      final isCurrent = cursor != null && point.noteIndex == currentIndex;
      _text(
        canvas,
        lyric,
        Offset(point.x + 2, _lyricY),
        _lyricFontSize,
        isCurrent ? scheme.primary : scheme.onSurface,
        bold: isCurrent,
        alignLeft: true,
      );
    }
  }

  void _arc(Canvas canvas, Offset from, Offset to, Color color) {
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(
        (from.dx + to.dx) / 2, from.dy - 5, to.dx, to.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  }

  @override
  bool shouldRepaint(_ScoreSystemPainter old) =>
      old.layout != layout ||
      old.system != system ||
      old.scheme != scheme ||
      old.cursor != cursor;
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
    tp.dispose(); // 播放期逐帧绘制,原生段落即时释放(与四线谱画笔同纪律)。
  }
}
