import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;

  /// 逻辑画布高(与移植源同款 280;行距/字号按此比例)。
  static const double canvasHeight = 280;

  /// 染色红(与票08 横带同一色值,系统内一处语义)。
  static const Color _highlightRed = Color(0xFFC8616D);
  static const Color _background = Color(0xFFFAF9F4);
  static const Color _glyph = Color(0xFF374D3A);
  static const Color _mutedGlyph = Color(0xFF617258);

  /// 数字/标签 TextPainter 缓存(键 = 文本|颜色|字号):每帧只 paint,
  /// 不反复 layout——长跑 60fps 不积 GC。
  final Map<String, TextPainter> _textCache = {};

  FlowingLayout? _layout;
  double _layoutWidth = 0;
  _ScoreIndex? _index;

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

  TextPainter _textPainter(String text, Color color, double fontSize,
      {FontWeight weight = FontWeight.w500}) {
    final key = '$text|$color|$fontSize|$weight';
    final cached = _textCache[key];
    if (cached != null) return cached;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: weight),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    _textCache[key] = painter;
    return painter;
  }

  void _ensureDerived(ReferenceScore score, double width) {
    if (_layout != null && _layoutWidth == width && _index != null) return;
    // 每秒像素:窄屏放慢(codex 同款规则;横屏/宽屏 145)。
    final pps = width < 500 ? 100.0 : 145.0;
    _layoutWidth = width;
    _layout = FlowingLayout.fromScore(score, pixelsPerSecond: pps);
    _index = _ScoreIndex(score);
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
                  final layout = _layout!;
                  final index = _index!;
                  final frame = frameAt(score, layout, seconds, _cursorX(width));
                  // FittedBox:横屏竖排高度不足 280 时等比缩小画布,
                  // 不得溢出盖住播放条(真机 2026-11-08 实录)。
                  return Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: width,
                        height: canvasHeight,
                        child: CustomPaint(
                          painter: _FlowingPainter(
                            score: score,
                            layout: layout,
                            index: index,
                            frame: frame,
                            cursorX: _cursorX(width),
                            width: width,
                            textPainter: _textPainter,
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
                  const SizedBox(width: 8),
                  Text(
                    '${_format(seconds)} / ${_format(score.durationSeconds)}',
                    style: const TextStyle(color: _glyph),
                  ),
                  const Spacer(),
                  _measureInfo(score, seconds),
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

/// 静态字形查取(每份谱建一次):延音和弦判别、滑音目标、音→事件归属。
class _ScoreIndex {
  _ScoreIndex(this.score) {
    // 滑音终点 = 同一弦上本事件之后第一个带音事件:顺序扫一遍,
    // 每弦只挂一个未决起点,遇带音事件即配对。
    final pending = <int, (RefEvent, RefNote)>{};
    for (final event in score.events) {
      if (event.notes.isNotEmpty) {
        for (final stringNo in pending.keys.toList()) {
          final target = event.notes
              .where((n) => n.stringNo == stringNo)
              .firstOrNull;
          if (target != null) {
            slideTarget[pending[stringNo]!.$2.id] = (event, target);
            pending.remove(stringNo);
          }
        }
      }
      for (final note in event.notes) {
        eventByNoteId[note.id] = event;
        if (note.hasSlideOut) pending[note.stringNo] = (event, note);
      }
      if (event.notes.isNotEmpty && event.notes.every((n) => n.isTieDestination)) {
        tieChords.add(event.id);
        final originId = event.notes.first.tieOriginNoteId;
        if (originId != null) {
          final originEvent = eventByNoteId[originId];
          if (originEvent != null) tieOriginByEventId[event.id] = originEvent;
        }
      }
    }
  }

  final ReferenceScore score;
  final Map<int, RefEvent> eventByNoteId = {};
  final Set<int> tieChords = {};
  final Map<int, RefEvent> tieOriginByEventId = {};
  final Map<int, (RefEvent, RefNote)> slideTarget = {};
}

/// 流水谱画笔:一次 paint 全部可见字形(窗口化:只画视口前后 2 秒)。
class _FlowingPainter extends CustomPainter {
  _FlowingPainter({
    required this.score,
    required this.layout,
    required this.index,
    required this.frame,
    required this.cursorX,
    required this.width,
    required this.textPainter,
  });

  final ReferenceScore score;
  final FlowingLayout layout;
  final _ScoreIndex index;
  final FlowingFrame frame;
  final double cursorX;
  final double width;
  final TextPainter Function(String, Color, double, {FontWeight weight}) textPainter;

  static const List<double> _rows = [124, 149, 174, 199];
  static const Color _highlightRed = Color(0xFFC8616D);
  static const Color _stringLine = Color(0xFFA3AD9A);
  static const Color _barLine = Color(0xFFB8BEAC);
  static const Color _glyph = Color(0xFF374D3A);
  static const Color _mutedGlyph = Color(0xFF617258);
  static const Color _faintGlyph = Color(0xFFB4BCA9);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFAF9F4));
    // 四弦线(屏幕固定,等价于移植源里足够长的横线)。
    final linePaint = Paint()
      ..color = _stringLine
      ..strokeWidth = 0.8;
    final labels = ['A', 'E', 'C', 'G'];
    for (var i = 0; i < _rows.length; i++) {
      final y = _rows[i];
      canvas.drawLine(Offset(0, y), Offset(width, y), linePaint);
      textPainter(labels[i], _mutedGlyph, 12)
          .paint(canvas, Offset(4, y - 6));
    }

    final translate = frame.translateX;
    canvas.save();
    canvas.translate(translate, 0);
    final windowLeft = -translate;
    final windowRight = width - translate;
    final seconds = frame.seconds;
    final pps = layout.pixelsPerSecond;
    final startT = math.max(0.0, seconds - cursorX / pps - 2);
    final endT = math.min(score.durationSeconds, seconds + (width - cursorX) / pps + 2);

    _paintMeasures(canvas, windowLeft, windowRight, startT, endT);
    _paintEvents(canvas, startT, endT, windowLeft, windowRight);
    _paintTimeTicks(canvas, startT, endT);
    _paintEndBar(canvas, windowRight);
    canvas.restore();

    // 固定红线(「现在弹这里」):不随内容平移。
    final cursorPaint = Paint()
      ..color = _highlightRed
      ..strokeWidth = 1.6;
    canvas.drawLine(
      Offset(cursorX, _rows.first - 6),
      Offset(cursorX, _rows.last + 6),
      cursorPaint,
    );
    canvas.drawCircle(Offset(cursorX, _rows.first - 10), 3, cursorPaint);
  }

  void _paintMeasures(Canvas canvas, double windowLeft, double windowRight,
      double startT, double endT) {
    final paint = Paint()
      ..color = _barLine
      ..strokeWidth = 0.8;
    for (final measure in score.measures) {
      if (measure.startSeconds + measure.durationSeconds < startT ||
          measure.startSeconds > endT) {
        continue;
      }
      final x = layout.measureLeftX[measure.index];
      if (x < windowLeft - 1 || x > windowRight + 1) continue;
      canvas.drawLine(Offset(x, _rows.first), Offset(x, _rows.last), paint);
      textPainter('${measure.index + 1}', _faintGlyph, 11)
          .paint(canvas, Offset(x + 4, 110));
    }
  }

  void _paintEvents(Canvas canvas, double startT, double endT,
      double windowLeft, double windowRight) {
    final events = score.events;
    var i = _firstEventAtOrAfter(startT);
    while (i < events.length && events[i].startSeconds <= endT) {
      final event = events[i];
      final x = layout.positionAt(event.startSeconds);
      final isActive = identical(frame.event, event);
      if (x >= windowLeft - 20 && x <= windowRight + 20) {
        _paintEvent(canvas, event, x, isActive);
      }
      i++;
    }
  }

  void _paintEvent(Canvas canvas, RefEvent event, double x, bool isActive) {
    if (event.chordName != null) {
      textPainter(event.chordName!, _glyph, 13, weight: FontWeight.w600)
          .paint(canvas, Offset(x + 4 - _textWidth(event.chordName!, 13) / 2, 28));
    }
    if (event.isRest) {
      // 休止暂用短横占位(符形后补);到点同样变色。
      final paint = Paint()
        ..color = isActive ? _highlightRed : _mutedGlyph
        ..strokeWidth = 3;
      canvas.drawLine(Offset(x - 7, 170), Offset(x + 7, 170), paint);
      return;
    }
    final isTieChord = index.tieChords.contains(event.id);
    for (final note in event.notes) {
      final y = _rows[note.stringNo - 1];
      if (isTieChord) {
        final origin = index.tieOriginByEventId[event.id];
        if (origin != null) {
          final ox = layout.positionAt(origin.startSeconds);
          if (ox >= x - 400 && ox < x) {
            final arc = Path()
              ..moveTo(ox + 8, y - 8)
              ..quadraticBezierTo((ox + x) / 2, y - 27, x - 8, y - 8);
            canvas.drawPath(
              arc,
              Paint()
                ..color = _mutedGlyph
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1,
            );
          }
        }
        continue;
      }
      final color = isActive && frame.noteIds.contains(note.id)
          ? _highlightRed
          : _glyph;
      final text = note.isNaturalHarmonic ? '<${note.fret}>' : '${note.fret}';
      textPainter(text, color, 16, weight: FontWeight.w600)
          .paint(canvas, Offset(x - _textWidth(text, 16) / 2, y + 6 - 8));
      if (note.hasSlideOut) {
        final target = index.slideTarget[note.id];
        if (target != null) {
          final tx = layout.positionAt(target.$1.startSeconds);
          if (tx > x && tx < x + 400) {
            final ty = _rows[target.$2.stringNo - 1];
            final direction = target.$2.fret > note.fret ? -1.0 : 1.0;
            canvas.drawLine(
              Offset(x + 12, y + 4 * direction),
              Offset(tx - 12, ty - 4 * direction),
              Paint()
                ..color = _mutedGlyph
                ..strokeWidth = 1.1,
            );
          }
        }
      }
    }
  }

  double _textWidth(String text, double fontSize) =>
      textPainter(text, _glyph, fontSize).width;

  int _firstEventAtOrAfter(double startT) {
    final events = score.events;
    var low = 0;
    var high = events.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (events[mid].startSeconds < startT - 0.5) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  void _paintTimeTicks(Canvas canvas, double startT, double endT) {
    final paint = Paint()
      ..color = _faintGlyph
      ..strokeWidth = 0.7;
    for (var t = (startT / 5).ceilToDouble() * 5; t <= endT; t += 5) {
      final x = layout.positionAt(t);
      canvas.drawLine(Offset(x, 259), Offset(x, 264), paint);
      final label = '${t ~/ 60}:${(t % 60).toInt().toString().padLeft(2, '0')}';
      textPainter(label, _faintGlyph, 10).paint(canvas, Offset(x + 4, 270));
    }
  }

  void _paintEndBar(Canvas canvas, double windowRight) {
    if (frame.seconds < score.durationSeconds - 1e-9 &&
        windowRight < layout.endX) {
      return;
    }
    final endX = layout.endX;
    final thin = Paint()
      ..color = _mutedGlyph
      ..strokeWidth = 1;
    final thick = Paint()
      ..color = _mutedGlyph
      ..strokeWidth = 3;
    canvas.drawLine(Offset(endX, _rows.first), Offset(endX, _rows.last), thin);
    canvas.drawLine(
        Offset(endX + 5, _rows.first), Offset(endX + 5, _rows.last), thick);
  }

  @override
  bool shouldRepaint(covariant _FlowingPainter oldDelegate) => true;
}
