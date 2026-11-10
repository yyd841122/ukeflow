import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/score/flowing_engraving.dart';
import '../../core/score/flowing_timeline.dart';
import '../../core/score/reference_score.dart';
import 'flowing/flowing_practice_controller.dart';

/// 《天空之城》流水谱跟练页(一手数据 MVP)。
///
/// codex 方法落地:固定红线,内容按音乐时间从右向左移动;当前演奏位置
/// 变色(当弹音红、其余照旧——参照视频的两态规则);画面位置全部查
/// [FlowingLayout] 同一张对照表;视觉不进调度,播放中每帧读引擎时钟
/// (ADR-0005)。拖动/松手保持暂停;曲末终点保留。
///
/// 排版细部(符杠、琶音波浪、休止符形)暂用简画,待展示验收后再补。
class FlowingScorePage extends ConsumerStatefulWidget {
  const FlowingScorePage({super.key});

  @override
  ConsumerState<FlowingScorePage> createState() => _FlowingScorePageState();
}

class _FlowingScorePageState extends ConsumerState<FlowingScorePage>
    with TickerProviderStateMixin {
  Ticker? _ticker;

  /// 染色红(与票08 横带同一色值,系统内一处语义)。
  static const Color _highlightRed = Color(0xFFC8616D);
  static const Color _background = Color(0xFFFAF9F4);
  static const Color _glyph = Color(0xFF374D3A);
  static const Color _mutedGlyph = Color(0xFF617258);

  /// 数字/标签 TextPainter 缓存(键 = 文本|颜色|字号):每帧只 paint,
  /// 不反复 layout——长跑 60fps 不积 GC。
  final Map<String, TextPainter> _textCache = {};

  FlowingEngraving? _engraving;
  double _layoutWidth = 0;

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _syncTicker(FlowingStatus status) {
    final shouldRun = status == FlowingStatus.playing;
    if (shouldRun && _ticker == null) {
      _ticker = createTicker((_) => setState(() {}))..start();
    } else if (!shouldRun && _ticker != null) {
      _ticker!.stop();
      _ticker!.dispose();
      _ticker = null;
      setState(() {});
    }
  }
  // 复数 TickerProviderStateMixin(2026-11-10 真机教训):Single 变体在
  // 「暂停清 ticker → 同页再播」时 createTicker 二次抛错红屏——我们
  // dispose 后只置空自持字段,mixin 内部引用仍在;同一页内
  // play→停→再播(曲末再练一遍、变速前暂停)是常规路径,必须用复数。

  /// 纸色描边光晕(数字的遮罩层,codex .fret stroke paper 同款)。
  TextPainter _haloPainter(String text, double fontSize,
      {FontWeight weight = FontWeight.w600}) {
    final key = 'halo|$text|$fontSize|$weight';
    final cached = _textCache[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          foreground: Paint()
            ..color = _background
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..strokeJoin = StrokeJoin.round,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    _textCache[key] = painter;
    return painter;
  }

  TextPainter _textPainter(String text, Color color, double fontSize,
      {FontWeight weight = FontWeight.w500, String? family}) {
    final key = '$text|$color|$fontSize|$weight|$family';
    final cached = _textCache[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: weight,
            fontFamily: family),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    _textCache[key] = painter;
    return painter;
  }

  /// 每秒像素(codex 同款规则):窄屏 100、宽屏 145;小节留白 32/24、
  /// 数字 18px、光晕 7px——全部照抄 codex 终版几何(2026-11-09 定案)。
  static double pixelsPerSecondFor(double width) => width < 500 ? 100 : 145;

  void _ensureDerived(ReferenceScore score, double width) {
    // codex 方法:zoom=1 永不缩放——几何固定 294 高、pps 竖 100/横 145、
    // 数字 18px,比例永远协调(竖屏上下留白是原谱同款呼吸感)。
    if (_engraving != null && _layoutWidth == width) return;
    _layoutWidth = width;
    final layout = FlowingLayout.fromScore(
      score,
      pixelsPerSecond: pixelsPerSecondFor(width),
    );
    _engraving = FlowingEngraving.build(
      score,
      layout: layout,
      plan: buildEngravingPlan(score),
      geometry: const FlowingGeometry(),
    );
    _textCache.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flowingPracticeProvider);
    final controller = ref.read(flowingPracticeProvider.notifier);
    _syncTicker(state.status);
    final score = state.score;
    final seconds = state.status == FlowingStatus.playing && state.t0 != null
        ? controller.currentSeconds()
        : state.positionSeconds;

    return Scaffold(
      appBar: AppBar(title: const Text('天空之城 · 流水谱')),
      backgroundColor: _background,
      body: Column(
        children: [
          _statusLine(state),
          if (score != null)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  _ensureDerived(score, width);
                  final frame = frameAt(score, _engraving!.layout, seconds, _cursorX(width));
                  // FittedBox:横屏竖排高度不足 280 时等比缩小画布,
                  // 不得溢出盖住播放条(真机 2026-11-08 实录)。
                  return Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: width,
                        height: 294,
                        child: CustomPaint(
                          painter: _FlowingPainter(
                            engraving: _engraving!,
                            geometry: _engraving!.geometry,
                            frame: frame,
                            cursorX: _cursorX(width),
                            width: width,
                            textPainter: _textPainter,
                            haloPainter: _haloPainter,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            )
          else
            const Expanded(child: SizedBox()),
          _transport(state, controller, seconds),
        ],
      ),
    );
  }

  double _cursorX(double width) => math.min(width - 90, width < 500 ? 252.0 : 320.0);

  Widget _statusLine(FlowingPracticeState state) {
    final message = switch (state.status) {
      FlowingStatus.loading => '正在读取一手曲谱…',
      FlowingStatus.ready => '准备好了，点播放跟着红线弹',
      FlowingStatus.playing => '看红线，提前准备下一个音',
      FlowingStatus.paused => '已暂停，准备好后再播放',
      FlowingStatus.finished => '整首弹完了，可以再练一遍',
      FlowingStatus.error => state.error ?? '出错了，请重开本页',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(message,
          style: TextStyle(color: state.status == FlowingStatus.error ? _highlightRed : _glyph)),
    );
  }

  Widget _transport(
    FlowingPracticeState state,
    FlowingPracticeController controller,
    double seconds,
  ) {
    final score = state.score;
    final playing = state.status == FlowingStatus.playing;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (score != null && state.status != FlowingStatus.loading)
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => playing ? controller.pause() : controller.play(),
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                    tooltip: playing ? '暂停' : '播放',
                  ),
                  IconButton.filledTonal(
                    onPressed: () => controller.seek(0),
                    icon: const Icon(Icons.replay),
                    tooltip: '从头',
                  ),
                  const SizedBox(width: 12),
                  // 时间与小节信息上下两行自适应(竖屏一行放不下会溢出,
                  // 真机 2026-11-08 实录 RIGHT OVERFLOWED BY 16 PIXELS)。
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_format(seconds)} / ${_format(score.durationSeconds)}',
                          style: const TextStyle(color: _glyph),
                        ),
                        const SizedBox(height: 2),
                        _measureInfo(score, seconds),
                      ],
                    ),
                  ),
                ],
              ),
            if (score != null && state.status != FlowingStatus.loading)
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _highlightRed,
                  thumbColor: _highlightRed,
                ),
                child: Slider(
                  value: seconds < 0
                      ? 0
                      : (seconds > score.durationSeconds ? score.durationSeconds : seconds),
                  max: score.durationSeconds,
                  label: _format(seconds),
                  onChanged: (value) => controller.seek(value),
                ),
              ),
            if (score != null && state.status != FlowingStatus.loading)
              _speedSelector(state, controller),
            if (score == null && state.status == FlowingStatus.loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  /// 速度三档(票01;codex 同款 0.5/0.75/1.0,措辞照抄「原速」)。
  /// 播放中切速即生效(控制器重锚,无突跳);紧凑排,不挤竖屏。
  Widget _speedSelector(
    FlowingPracticeState state,
    FlowingPracticeController controller,
  ) {
    return SizedBox(
      height: 40,
      child: SegmentedButton<double>(
        segments: const [
          ButtonSegment(value: 0.5, label: Text('0.5倍', key: Key('speed-05'))),
          ButtonSegment(
              value: 0.75, label: Text('0.75倍', key: Key('speed-075'))),
          ButtonSegment(value: 1.0, label: Text('原速', key: Key('speed-10'))),
        ],
        selected: {state.speed},
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        onSelectionChanged: (selection) => controller.setSpeed(selection.first),
      ),
    );
  }

  Widget _measureInfo(ReferenceScore score, double seconds) {
    var measureIndex = measureIndexAt(score, seconds);
    if (measureIndex < 0) measureIndex = 0;
    if (measureIndex > score.measures.length - 1) {
      measureIndex = score.measures.length - 1;
    }
    final measure = score.measures[measureIndex];
    var section = '从头开始';
    for (var i = 0; i <= measureIndex && i < score.measures.length; i++) {
      final s = score.measures[i].section;
      if (s != null) section = s == 'Ending' ? '最后一段' : s;
    }
    return Text(
      '第 ${measureIndex + 1}/${score.measures.length} 小节 · $section · ${measure.tempo} 拍/分',
      style: const TextStyle(color: _mutedGlyph, fontSize: 12),
    );
  }

  String _format(double seconds) {
    final total = seconds.floor().clamp(0, 36000);
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }
}

/// 流水谱渲染器:**哑渲染器**——只消费排版数据(FlowingEngraving),
/// 逐字形作画,零几何计算。当弹态由 frame 与字形事件比对得上色。
class _FlowingPainter extends CustomPainter {
  _FlowingPainter({
    required this.engraving,
    required this.geometry,
    required this.frame,
    required this.cursorX,
    required this.width,
    required this.textPainter,
    required this.haloPainter,
  });

  final FlowingEngraving engraving;
  final FlowingGeometry geometry;
  final FlowingFrame frame;
  final double cursorX;
  final double width;
  final TextPainter Function(String, Color, double,
      {FontWeight weight, String? family}) textPainter;
  final TextPainter Function(String, double, {FontWeight weight}) haloPainter;

  static const Color _highlightRed = Color(0xFFC8616D);
  static const Color _background = Color(0xFFFAF9F4);
  static const Color _glyph = Color(0xFF374D3A);
  static const Color _mutedGlyph = Color(0xFF617258);
  static const Color _faintGlyph = Color(0xFFB4BCA9);
  static const Color _barLine = Color(0xFFB8BEAC);
  static const Color _stringLine = Color(0xFFA3AD9A);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _background);

    // 四弦线 + 弦名(屏幕固定)。
    final stringPaint = Paint()
      ..color = _stringLine
      ..strokeWidth = 0.8;
    for (var i = 0; i < FlowingGeometry.rows.length; i++) {
      final y = FlowingGeometry.rows[i];
      canvas.drawLine(Offset(0, y), Offset(width, y), stringPaint);
      textPainter(const ['A', 'E', 'C', 'G'][i], _mutedGlyph, 12)
          .paint(canvas, Offset(4, y - 6));
    }

    final translate = frame.translateX;
    canvas.save();
    canvas.translate(translate, 0);
    final windowLeft = -translate;
    final windowRight = width - translate;

    _paintBars(canvas, windowLeft, windowRight);
    _paintEvents(canvas, windowLeft, windowRight);
    _paintBeams(canvas, windowLeft, windowRight);
    _paintTimeTicks(canvas, windowLeft, windowRight);
    _paintEndBar(canvas, windowRight);
    canvas.restore();

    // 固定红线(「现在弹这里」):不随内容平移。
    final cursorPaint = Paint()
      ..color = _highlightRed
      ..strokeWidth = 1.6;
    canvas.drawLine(
      Offset(cursorX, FlowingGeometry.rows.first - 6),
      Offset(cursorX, FlowingGeometry.rows.last + 6),
      cursorPaint,
    );
    canvas.drawCircle(Offset(cursorX, FlowingGeometry.rows.first - 10), 3, cursorPaint);
  }

  void _paintBars(Canvas canvas, double windowLeft, double windowRight) {
    for (final bar in engraving.bars) {
      if (bar.lineX < windowLeft - 1 || bar.lineX > windowRight + 1) continue;
      canvas.drawLine(
        Offset(bar.lineX, FlowingGeometry.rows.first),
        Offset(bar.lineX, FlowingGeometry.rows.last),
        Paint()
          ..color = _barLine
          ..strokeWidth = 0.8,
      );
      textPainter(bar.number, _faintGlyph, 11)
          .paint(canvas, Offset(bar.numberX, bar.numberY));
    }
  }

  void _paintEvents(Canvas canvas, double windowLeft, double windowRight) {
    for (final glyph in engraving.eventGlyphs) {
      if (glyph.x < windowLeft - 40 || glyph.x > windowRight + 40) continue;
      _paintEvent(canvas, glyph);
    }
  }

  void _paintEvent(Canvas canvas, EventGlyphs glyph) {
    final x = glyph.x;
    final isActive = identical(frame.event, glyph.event);

    // 和弦按法图(原谱式:名 + 网格 + 按位点 + 空弦圈 + 品位标注)。
    final chord = glyph.chord;
    if (chord != null) {
      final cx = glyph.chordX ?? x + 4;
      if (chord.showName && chord.name.isNotEmpty) {
        textPainter(chord.name, _glyph, 13, weight: FontWeight.w600)
            .paint(canvas, Offset(cx - _widthOf(chord.name, 13) / 2, 28));
      }
      if (chord.showDiagram) _paintChordGrid(canvas, cx, chord);
    }

    // 休止符(Bravura 字形,当弹变红)。
    if (glyph.restX != null) {
      final tp = textPainter(glyph.restGlyph, isActive ? _highlightRed : _mutedGlyph,
          30, family: 'Bravura');
      tp.paint(canvas, Offset(glyph.restX! - tp.width / 2,
          FlowingGeometry.restY - tp.height * 0.78));
      return;
    }

    // 符杆(延音和弦无数字但有杆)。
    if (glyph.stemX != null) {
      canvas.drawLine(
        Offset(glyph.stemX!, glyph.stemTop),
        Offset(glyph.stemX!, FlowingGeometry.stemBottom),
        Paint()
          ..color = _mutedGlyph
          ..strokeWidth = 1.1,
      );
    }

    // 独立符尾(q 曲线)。
    final flag = glyph.flag;
    if (flag != null) {
      for (var f = 0; f < flag.count; f++) {
        final y = flag.y - f * FlowingGeometry.beamGap;
        final path = Path()
          ..moveTo(flag.x, y)
          ..quadraticBezierTo(flag.x + 12, y - 2, flag.x + 13, y - 14);
        canvas.drawPath(
          path,
          Paint()
            ..color = _mutedGlyph
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    // 附点。
    for (final dot in glyph.dots) {
      canvas.drawCircle(Offset(dot.x, dot.y), 1.8, Paint()..color = _mutedGlyph);
    }

    // 琶音波浪/扫弦箭头。
    if (glyph.waveBx != null) _paintWave(canvas, glyph);

    // 延音小弧(谱面上方,源 → 本位置)。
    if (glyph.isTieChord) {
      final tie = engraving.tieArcOf(glyph.event.id);
      if (tie != null) {
        final x1 = tie.x1;
        final x2 = tie.x2;
        final mid = (x1 + x2) / 2;
        final arc = Path()
          ..moveTo(x1, 118)
          ..quadraticBezierTo(mid, 96, x2, 118)
          ..quadraticBezierTo(mid, 102, x1, 118);
        canvas.drawPath(
          arc,
          Paint()
            ..color = _mutedGlyph
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }

    // 滑音线。
    for (final slide in glyph.slides) {
      canvas.drawLine(
        Offset(slide.x1, slide.y1),
        Offset(slide.x2, slide.y2),
        Paint()
          ..color = _mutedGlyph
          ..strokeWidth = 1.1,
      );
    }

    // 品位数字(骑线,当弹红)。
    for (final digit in glyph.digits) {
      final color = isActive && frame.noteIds.contains(digit.noteId)
          ? _highlightRed
          : _glyph;
      // 纸色描边光晕垫底(codex app.css .fret: stroke paper 7px,
      // paint-order:stroke)——穿过的弦线/杆/波浪在数字周围被就地
      // 擦掉,数字永远干净;这是 codex 不做避让工程的根基。
      final halo = haloPainter(digit.text, 18, weight: FontWeight.w600);
      halo.paint(canvas,
          Offset(digit.x - halo.width / 2, digit.rowY - halo.height / 2));
      final tp = textPainter(digit.text, color, 18, weight: FontWeight.w600);
      tp.paint(canvas,
          Offset(digit.x - tp.width / 2, digit.rowY - tp.height / 2));
    }
  }

  void _paintChordGrid(Canvas canvas, double cx, RefChord chord) {
    final left = cx - 14;
    const top = 45.0;
    final grid = Paint()
      ..color = const Color(0xFF8B9683)
      ..strokeWidth = 0.6;
    for (var line = 0; line <= 4; line++) {
      final y = top + line * 8;
      if (line == 0) grid.strokeWidth = 1.4;
      canvas.drawLine(Offset(left, y), Offset(left + 28, y), grid);
      if (line == 0) grid.strokeWidth = 0.6;
    }
    for (var string = 0; string < 4; string++) {
      final sx = left + string * 28 / 3;
      canvas.drawLine(Offset(sx, top), Offset(sx, top + 32), grid);
      final value = chord.strings[3 - string];
      if (value > 0) {
        canvas.drawCircle(
          Offset(sx, top + (value - chord.firstFret + 0.5) * 8),
          2.5,
          Paint()..color = _glyph,
        );
      } else if (value == 0) {
        canvas.drawCircle(
          Offset(sx, top - 5),
          1.6,
          Paint()
            ..color = const Color(0xFF6D8067)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7,
        );
      }
    }
    if (chord.firstFret > 1) {
      textPainter('${chord.firstFret}', _glyph, 10)
          .paint(canvas, Offset(left - 5 - _widthOf('${chord.firstFret}', 10), top));
    }
  }

  void _paintWave(Canvas canvas, EventGlyphs glyph) {
    final bx = glyph.waveBx!;
    final tip = glyph.waveUp ? glyph.waveTop : glyph.waveBottom;
    final step = glyph.waveUp ? 6.0 : -6.0;
    final path = Path()..moveTo(bx, glyph.waveTop);
    if (glyph.waveIsArpeggio) {
      var y = glyph.waveTop;
      var i = 0;
      while (y < glyph.waveBottom) {
        final end = math.min(y + 8, glyph.waveBottom);
        final bend = i % 2 == 1 ? 4.0 : -4.0;
        path.cubicTo(bx + bend, y + (end - y) / 3, bx + bend,
            y + (end - y) * 2 / 3, bx, end);
        y += 8;
        i++;
      }
    } else {
      path.lineTo(bx, glyph.waveBottom);
    }
    path.moveTo(bx - 3, tip + step);
    path.lineTo(bx, tip);
    path.lineTo(bx + 3, tip + step);
    canvas.drawPath(
      path,
      Paint()
        ..color = _mutedGlyph
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  }

  void _paintBeams(Canvas canvas, double windowLeft, double windowRight) {
    for (final bar in engraving.beamBars) {
      if (bar.x1 < windowLeft - 40 || bar.x1 > windowRight + 40) continue;
      canvas.drawLine(
        Offset(bar.x1, bar.y),
        Offset(bar.x2, bar.y),
        Paint()
          ..color = _mutedGlyph
          ..strokeWidth = 1.8,
      );
    }
  }

  void _paintTimeTicks(Canvas canvas, double windowLeft, double windowRight) {
    final tickPaint = Paint()
      ..color = _faintGlyph
      ..strokeWidth = 0.7;
    for (final tick in engraving.timeTicks) {
      if (tick.x < windowLeft - 30 || tick.x > windowRight + 30) continue;
      canvas.drawLine(Offset(tick.x, FlowingGeometry.timeTick),
          Offset(tick.x, FlowingGeometry.timeTick + 5), tickPaint);
      textPainter(tick.label, _faintGlyph, 10)
          .paint(canvas, Offset(tick.x + 4, FlowingGeometry.timeLabel));
    }
  }

  void _paintEndBar(Canvas canvas, double windowRight) {
    if (frame.seconds < _duration - 1e-9 && windowRight < engraving.endBarX) {
      return;
    }
    final endX = engraving.endBarX;
    canvas.drawLine(
      Offset(endX, FlowingGeometry.rows.first),
      Offset(endX, FlowingGeometry.rows.last),
      Paint()
        ..color = _mutedGlyph
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(endX + 5, FlowingGeometry.rows.first),
      Offset(endX + 5, FlowingGeometry.rows.last),
      Paint()
        ..color = _mutedGlyph
        ..strokeWidth = 3,
    );
  }

  double get _duration => engraving.layout.durationSecondsOfSong;

  double _widthOf(String text, double fontSize) =>
      textPainter(text, _glyph, fontSize).width;

  @override
  bool shouldRepaint(covariant _FlowingPainter oldDelegate) => true;
}
