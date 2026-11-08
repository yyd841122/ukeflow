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
  EngravingPlan? _plan;

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

  /// 每小节几何(2026-11-08 用户对谱实录:原尺寸小节几乎占满竖屏一屏,
  /// 与原谱密度不符)。原谱实测:小节宽 152.7px、弦距 9.24px、原站播放
  /// 器流速 50~62px/s;取 pps=52(流速落在原站区间),竖屏约 2 小节/屏、
  /// 横屏约 4,密度与原站一致。留白 32/24(codex 同款):首音的琶音
  /// 波浪在音位左 17px,留白 <17 会压上小节线(16 版真机实录)。
  static const double _pixelsPerSecond = 52;
  static const double _leftGutter = 32;
  static const double _rightGutter = 24;

  void _ensureDerived(ReferenceScore score, double width) {
    if (_layout != null && _layoutWidth == width && _index != null) return;
    _layoutWidth = width;
    _layout = FlowingLayout.fromScore(
      score,
      pixelsPerSecond: _pixelsPerSecond,
      leftGutter: _leftGutter,
      rightGutter: _rightGutter,
    );
    _index = _ScoreIndex(score);
    _plan = buildEngravingPlan(score);
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
                            plan: _plan!,
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
    required this.plan,
    required this.frame,
    required this.cursorX,
    required this.width,
    required this.textPainter,
  });

  final ReferenceScore score;
  final FlowingLayout layout;
  final _ScoreIndex index;
  final EngravingPlan plan;
  final FlowingFrame frame;
  final double cursorX;
  final double width;
  final TextPainter Function(String, Color, double,
      {FontWeight weight, String? family}) textPainter;

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

    _paintHeaders(canvas, windowLeft, windowRight, startT, endT);
    _paintMeasures(canvas, windowLeft, windowRight, startT, endT);
    _paintEvents(canvas, startT, endT, windowLeft, windowRight);
    _paintBeams(canvas, windowLeft, windowRight);
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

  /// 谱面标记层(原谱画法,2026-11-08 全量机比补齐):段落名印在起始
  /// 小节上方;曲头印「调 拍号」与「♩=速度」。
  void _paintHeaders(Canvas canvas, double windowLeft, double windowRight,
      double startT, double endT) {
    for (final measure in score.measures) {
      final section = measure.section;
      if (section == null) continue;
      if (measure.startSeconds + measure.durationSeconds < startT ||
          measure.startSeconds > endT) {
        continue;
      }
      final x = layout.measureLeftX[measure.index];
      if (x < windowLeft - 80 || x > windowRight + 80) continue;
      textPainter(section, _glyph, 13, weight: FontWeight.w700)
          .paint(canvas, Offset(x + 2, 6));
    }
    // 曲头:key = 调 拍号、♩= 速度(印在第一小节顶行,随内容滚走)。
    if (startT <= 0.001 && score.measures.isNotEmpty) {
      final m0 = score.measures.first;
      final keyTp = textPainter(
        'key = ${keyName(score.keySignature)} ${m0.numerator}/${m0.denominator}',
        _glyph,
        12,
        weight: FontWeight.w600,
      );
      keyTp.paint(canvas, Offset(layout.measureLeftX[0] + 2, 8));
      // ♩= 速度紧随 key 文本(固定偏移会被窄屏右缘裁掉,真机实录)。
      final tempoX = layout.measureLeftX[0] + 2 + keyTp.width + 10;
      final note = textPainter('\uE1D5', _mutedGlyph, 13, family: 'Bravura');
      // Bravura 字形基线偏移大,按实测抬高与 '= 80' 文字行对齐
      // (真机 2026-11-08 实录:默认顶对齐音符沉底 ~15px)。
      note.paint(canvas, Offset(tempoX, -4));
      textPainter('= ${m0.tempo}', _mutedGlyph, 11)
          .paint(canvas, Offset(tempoX + note.width + 1, 12));
    }
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

  /// 符杠底 y 与每层间距(与移植源同款几何)。
  static const double _stemBottomY = 241;
  static const double _beamLevelGap = 7;

  void _paintEvent(Canvas canvas, RefEvent event, double x, bool isActive) {
    _paintChordDiagram(canvas, event, x);
    if (event.isRest) {
      // 真休止符形(Bravura 码点,flowing_engraving 单一来源);到点变色。
      final glyph = plan.rhythmOf(event.id)?.restCodePoint ?? 0xE4E5;
      final tp = textPainter(String.fromCharCode(glyph),
          isActive ? _highlightRed : _mutedGlyph, 30, family: 'Bravura');
      tp.paint(canvas, Offset(x - tp.width / 2, 170 - tp.height * 0.78));
      return;
    }
    // 符干(原谱画法,2026-11-08 实测:杆一路贯穿到弦下方的符杠;
    // codex 的「最低弦下 13px 短桩」与原谱不符,弃)。延音和弦隐藏
    // 数字但仍保留符干。
    // 和弦列(多弦数字):杆右移到数字列外缘——杆挂在和弦右侧(经典
    // 记谱法/原谱同款),杆身不与任何数字重叠(2026-11-08 用户实录:
    // 杆穿过 0 的字缝可见)。单音杆在自身数字下一弦起,水平不重叠。
    final isTieChord = index.tieChords.contains(event.id);
    final topMostString = event.notes.map((n) => n.stringNo).reduce(math.min);
    final stemX = x + (event.notes.length > 1 && !isTieChord
        ? _stemClearance(event)
        : 0.0);
    final stemTop = event.notes.length > 1 && !isTieChord
        ? _rows[topMostString - 1] + 2
        : _rows[math.min(topMostString, 3)] + 2;
    canvas.drawLine(
      Offset(stemX, stemTop),
      Offset(stemX, _stemBottomY),
      Paint()
        ..color = _mutedGlyph
        ..strokeWidth = 1.1,
    );
    // 独立符尾(未入杠的音才有)+ 附点。
    final beamed = plan.beams.any((pair) => pair.$1 == event.id || pair.$2 == event.id);
    final rhythm = plan.rhythmOf(event.id);
    final flags = rhythm?.flags ?? 0;
    if (!beamed) {
      for (var f = 0; f < flags; f++) {
        final path = Path()
          ..moveTo(x, _stemBottomY - f * _beamLevelGap)
          ..quadraticBezierTo(x + 12, _stemBottomY - f * _beamLevelGap - 2,
              x + 13, _stemBottomY - f * _beamLevelGap - 14);
        canvas.drawPath(
          path,
          Paint()
            ..color = _mutedGlyph
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
    final dots = rhythm?.dots ?? 0;
    for (var d = 0; d < dots; d++) {
      canvas.drawCircle(
        Offset(x + 9 + d * 5, 232),
        1.8,
        Paint()..color = _mutedGlyph,
      );
    }
    // 琶音波浪/扫弦箭头(原谱记号,含延音和弦续显的 3 处)。
    _paintBrush(canvas, event, x);
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
      // 品位数字骑在弦线上:按文字框高度对弦线垂直居中(原谱画法——
      // 弦线从数字正中穿过;此前按框顶定位,数字吊在线下,2026-11-08
      // 用户实录指出)。
      final tp = textPainter(text, color, 16, weight: FontWeight.w600);
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
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

  /// 和弦按法图(codex drawChord 忠实移植):和弦名 + 四弦网格 +
  /// 按位点/空弦圈 + 左端品位标注。
  void _paintChordDiagram(Canvas canvas, RefEvent event, double x) {
    final chord = event.chord;
    if (chord == null) return;
    final cx = x + 4;
    if (chord.showName && chord.name.isNotEmpty) {
      textPainter(chord.name, _glyph, 13, weight: FontWeight.w600)
          .paint(canvas, Offset(cx - _textWidth(chord.name, 13) / 2, 28));
    }
    if (!chord.showDiagram) return;
    final left = cx - 14;
    const top = 45.0;
    final gridPaint = Paint()
      ..color = const Color(0xFF8B9683)
      ..strokeWidth = 0.6;
    for (var line = 0; line <= 4; line++) {
      final y = top + line * 8;
      if (line == 0) gridPaint.strokeWidth = 1.4;
      canvas.drawLine(Offset(left, y), Offset(left + 28, y), gridPaint);
      if (line == 0) gridPaint.strokeWidth = 0.6;
    }
    for (var string = 0; string < 4; string++) {
      final sx = left + string * 28 / 3;
      canvas.drawLine(Offset(sx, top), Offset(sx, top + 32), gridPaint);
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
      final label = '${chord.firstFret}';
      textPainter(label, _glyph, 10)
          .paint(canvas, Offset(left - 5 - _textWidth(label, 10), top));
    }
  }

  /// 琶音波浪(3/4)或扫弦直箭(1/2)。波浪沿事件弦位区间 zigzag,
  /// 箭头指向拨动方向;横向偏移按移植源规则(含泛音的事件让位 32)。
  void _paintBrush(Canvas canvas, RefEvent event, double x) {
    final mark = plan.brushes.where((b) => b.eventId == event.id).firstOrNull;
    if (mark == null) return;
    final top = _rows
            .sublist(0, 4)
            .reduce((a, b) => a < b ? a : b) -
        3;
    final bottom = _rows.reduce((a, b) => b > a ? b : a) + 3;
    final hasHarmonic = event.notes.any((n) => n.isNaturalHarmonic);
    // 波浪左伸 12(泛音 24):逐小节测宽后八分间距 24px,17px 左伸会压上
    // 前一个音的数字(2026-11-08 用户实录「与前一个音符重合」)。
    final bx = x - (hasHarmonic ? 24.0 : 12.0);
    final tip = mark.up ? top : bottom;
    final step = mark.up ? 6.0 : -6.0;
    final path = Path()..moveTo(bx, top);
    if (mark.isArpeggio) {
      var y = top.toDouble();
      var i = 0;
      while (y < bottom) {
        final end = math.min(y + 8, bottom);
        final bend = i % 2 == 1 ? 4.0 : -4.0;
        path.cubicTo(bx + bend, y + (end - y) / 3, bx + bend,
            y + (end - y) * 2 / 3, bx, end);
        y += 8;
        i++;
      }
    } else {
      path.lineTo(bx, bottom);
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

  /// 符杠连横线与短钩(窗口外整组跳过;层叠几何与移植源一致)。
  void _paintBeams(Canvas canvas, double windowLeft, double windowRight) {
    final byId = {for (final e in score.events) e.id: e};
    for (final segment in plan.beamSegments) {
      final first = byId[segment.from]!;
      final last = byId[segment.to]!;
      if (last.startSeconds < 0 || first.startSeconds < 0) continue;
      // 梁端点 = 各事件的符干位(和弦右缘净距),与符干同一来源。
      final x1 = layout.positionAt(first.startSeconds) +
          _stemClearanceFor(first);
      if (x1 < windowLeft - 40 || x1 > windowRight + 40) continue;
      final y = _stemBottomY - (segment.level - 1) * _beamLevelGap;
      final double x2;
      if (segment.hook != null) {
        x2 = x1 + (segment.hook == 'left' ? -12 : 12);
      } else {
        x2 = layout.positionAt(last.startSeconds) +
            _stemClearanceFor(last);
      }
      canvas.drawLine(
        Offset(x1, y),
        Offset(x2, y),
        Paint()
          ..color = _mutedGlyph
          ..strokeWidth = 1.8,
      );
    }
  }

  double _textWidth(String text, double fontSize) =>
      textPainter(text, _glyph, fontSize).width;

  /// 事件的符干水平偏移(延音和弦数字已隐藏 → 0;和弦 = 净距)。
  double _stemClearanceFor(RefEvent event) =>
      event.notes.length > 1 && !index.tieChords.contains(event.id)
          ? _stemClearance(event)
          : 0.0;

  /// 和弦杆的水平净距:杆挂到数字列右缘外(最宽数字半宽 + 3px),
  /// 梁端点与符干共用同一偏移(单一来源)。
  double _stemClearance(RefEvent event) {
    var half = 0.0;
    for (final note in event.notes) {
      final text = note.isNaturalHarmonic ? '<${note.fret}>' : '${note.fret}';
      half = math.max(half, _textWidth(text, 16) / 2);
    }
    return half + 3;
  }

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
