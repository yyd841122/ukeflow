import 'package:flutter/material.dart';

import '../../core/audio/beat_scheduling.dart' show beatsPerBar;

import '../../core/model/tab_chart.dart';
import 'tab_chart_layout.dart';

/// 逐音高亮(工单 13 跟练):当前音与预亮窗内音的下标。下标与
/// [TabChartLayout.notes] 同序(同为 sortedTabNotes 序,与时间轴事件
/// 一一对应)。null = 静态读谱视图(工单 12)。
class TabHighlight {
  const TabHighlight({
    required this.currentIndex,
    required this.upcomingIndexes,
  });

  /// 当前音下标;持稳到下一音(长音不闪断),曲首还没有任何音时 -1。
  final int currentIndex;

  /// 预亮窗内的音下标(升序连续,来自 tabPracticeStateAt)。
  final Set<int> upcomingIndexes;

  @override
  bool operator ==(Object other) =>
      other is TabHighlight &&
      other.currentIndex == currentIndex &&
      other.upcomingIndexes.length == upcomingIndexes.length &&
      other.upcomingIndexes.every(upcomingIndexes.contains);

  @override
  int get hashCode => Object.hash(currentIndex, upcomingIndexes.length);
}

/// 四线谱(GLOSSARY「指弹谱」的显示形式):四条弦线 + 小节线/拍位栅 +
/// 品位点(数字),音的横坐标即时值——全部几何出自 [TabChartLayout]
/// (纯函数),本组件与画笔只做笔画与滚动。
///
/// 工单 12 交付「能看」:静态读谱视图(横向滚动);工单 13 升级跟练:
/// 传 [highlight] 即换音点配色(当前音主色加大+描边环、预亮窗内音
/// 三级色、已响淡出,几何不动),[scrollController] 供跟练视图自动
/// 平移跟随。
class TabChartView extends StatelessWidget {
  const TabChartView({
    super.key,
    required this.chart,
    this.pxPerBeat = 44,
    this.highlight,
    this.scrollController,
  });

  final TabChart chart;

  /// 一档拍位的像素宽(缩放系数;缺省 44,半拍音位留 22px 不粘连)。
  final double pxPerBeat;

  /// 逐音高亮(跟练);null = 静态读谱。
  final TabHighlight? highlight;

  /// 横向滚动的接管口(跟练自动平移用);null = 用户手动滚。
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final layout = TabChartLayout(chart, pxPerBeat: pxPerBeat);
    return SizedBox(
      height: layout.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧弦号列固定,横向滚动时读谱不失参照。
          CustomPaint(
            key: const Key('tab-chart-labels'),
            size: Size(_labelWidth, layout.height),
            painter: _StringLabelsPainter(scheme),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              scrollDirection: Axis.horizontal,
              child: CustomPaint(
                key: const Key('tab-chart-canvas'),
                size: Size(layout.chartWidth, layout.height),
                painter: _TabChartPainter(layout, scheme, highlight),
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

/// 谱面画笔:弦线、小节线(含小节号)、拍位栅、品位点。带高亮时音点
/// 按三级配色(当前/预亮/已响),几何不动(工单 13:高亮 = 换配色)。
class _TabChartPainter extends CustomPainter {
  _TabChartPainter(this.layout, this.scheme, [this.highlight]);

  final TabChartLayout layout;
  final ColorScheme scheme;
  final TabHighlight? highlight;

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

    // 品位点:落在弦线上的实心圆,数字为品位(0 = 空弦)。跟练高亮
    // 三级:当前音主色加大+描边环(「此刻拨这」)、预亮窗内音三级色
    // (「左手提前移」)、已响音淡出;无高亮/未到音 = 静态主色。
    // 当前**组**按拍位相等取:同拍多音(和弦对)同刻拨响,一齐突出,
    // 不让先录入的那个从预亮直接跌进已响(工单 13 评审修)。
    final highlight = this.highlight;
    final currentBeat = (highlight == null || highlight.currentIndex < 0)
        ? null
        : layout.notes[highlight.currentIndex].beat;
    for (var i = 0; i < layout.notes.length; i++) {
      final note = layout.notes[i];
      final isCurrent = currentBeat != null && note.beat == currentBeat;
      final isUpcoming =
          highlight != null && highlight.upcomingIndexes.contains(i);
      final isPast = currentBeat != null && note.beat < currentBeat;
      final center = Offset(
        layout.noteX(note.beat),
        TabChartLayout.stringY(note.string),
      );
      final Color fill;
      final Color label;
      var radius = TabChartLayout.noteRadius;
      if (isCurrent) {
        fill = scheme.primary;
        label = scheme.onPrimary;
        radius += 2;
      } else if (isUpcoming) {
        fill = scheme.tertiary;
        label = scheme.onTertiary;
      } else if (isPast) {
        fill = scheme.onSurface.withValues(alpha: 0.18);
        label = scheme.onSurface.withValues(alpha: 0.45);
      } else {
        fill = scheme.primary;
        label = scheme.onPrimary;
      }
      if (isCurrent) {
        // 描边环:当前音的第二级强调(与静态音点、预亮音都拉开)。
        canvas.drawCircle(
          center,
          radius + 3.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = scheme.primary,
        );
      }
      canvas.drawCircle(center, radius, Paint()..color = fill);
      _text(canvas, '${note.fret}', center, radius * 1.15, label);
    }

    // 歌词缀字:唱词落在该音正下方的歌词行(逐音缀字,新手跟唱;
    // 长音的字居中停在音位上,唱到下一字前不移动)。
    for (final note in layout.notes) {
      final lyric = note.lyric;
      if (lyric == null) continue;
      _text(
        canvas,
        lyric,
        Offset(layout.noteX(note.beat), layout.lyricY),
        TabChartLayout.fontSize,
        scheme.onSurface,
      );
    }
  }

  @override
  bool shouldRepaint(_TabChartPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.scheme != scheme ||
      oldDelegate.highlight != highlight;
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
  try {
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  } finally {
    tp.dispose(); // 播放期逐帧绘制,原生段落即时释放不给 GC 添压(审计 #38)。
  }
}
