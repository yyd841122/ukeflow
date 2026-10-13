import 'package:flutter/material.dart';

import '../../core/model/tab_chart.dart';
import '../../core/practice/tab_practice_state.dart';
import '../../core/practice/tab_timeline.dart';
import 'tab_chart_layout.dart';
import 'tab_chart_view.dart';

/// 逐音跟练运行视图(GLOSSARY「跟练」的指弹显示层):给定练习状态画
/// 全部视觉——四线谱逐音高亮(当前音/预亮两级)、小节内拍号、总进度。
/// 薄渲染(ADR-0005):无时钟无动画,一切信息读 [practice],由跟练页
/// 以 ~16ms 轮询重灌;本组件自己不产生任何时间。
///
/// 跟谱平移是**阶梯式**:当前音走出可视窗右沿(或预亮窗右沿顶到边)
/// 才平移,把当前音锚回视口左 1/4——读谱以静为主,不与视线抢跑;
/// 平滑跟滚需引擎时刻时间插值,与弹唱歌词平滑滚动同归打磨(票 23)。
class TabPracticeView extends StatefulWidget {
  const TabPracticeView({
    super.key,
    required this.chart,
    required this.timeline,
    required this.practice,
  });

  final TabChart chart;

  /// 时间轴(总进度分母用 totalBeats;练习状态里不带——它属于时间轴)。
  final TabTimeline timeline;

  final TabPracticeState practice;

  @override
  State<TabPracticeView> createState() => _TabPracticeViewState();
}

class _TabPracticeViewState extends State<TabPracticeView> {
  final _scroll = ScrollController();

  /// 谱面几何(谱面整页不变,缓存一次)。
  late final TabChartLayout _layout;

  @override
  void initState() {
    super.initState();
    // 跟谱几何与 TabChartView 缺省同一档位宽(44,半拍音位 22px 不挤):
    // 跟随平移的 x 与画布 x 同一布局,不另立系数。
    _layout = TabChartLayout(widget.chart, pxPerBeat: 44);
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
  }

  @override
  void didUpdateWidget(TabPracticeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当前音推进才评估跟随(薄渲染:预亮窗随轮询滑动但不触发平移)。
    if (widget.practice.currentNoteIndex !=
        oldWidget.practice.currentNoteIndex) {
      _follow();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 当前音走出可视窗(左沿落下/右沿逼近/预亮窗顶边)→ 平移把当前音
  /// 锚回视口左 1/4。全部量读自滚动位置与谱面几何,无第二时间源。
  void _follow() {
    if (!_scroll.hasClients) return;
    final index = widget.practice.currentNoteIndex;
    final currentBeat = index < 0 ? 0.0 : _layout.notes[index].beat;
    final currentX = _layout.noteX(currentBeat);
    final upcoming = widget.practice.upcomingNoteIndexes;
    // 预亮窗右沿:窗内最远音的 x + 音点半径余量;无预告时退当前音。
    final edgeX = upcoming.isEmpty
        ? currentX
        : _layout.noteX(_layout.notes[upcoming.last].beat) +
              TabChartLayout.noteRadius;
    final position = _scroll.position;
    const margin = TabChartLayout.rightPad + 8;
    final offRight =
        currentX - _scroll.offset > position.viewportDimension * 0.75;
    final edgeOver =
        edgeX > _scroll.offset + position.viewportDimension - margin;
    if (currentX >= _scroll.offset && !offRight && !edgeOver) return;
    final target = (currentX - position.viewportDimension * 0.25).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if ((target - _scroll.offset).abs() < 1) return;
    _scroll.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TabChartView(
            chart: widget.chart,
            highlight: TabHighlight(
              currentIndex: widget.practice.currentNoteIndex,
              upcomingIndexes: widget.practice.upcomingNoteIndexes.toSet(),
            ),
            scrollController: _scroll,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${widget.practice.beatInBar + 1}',
          key: const Key('tab-beat-number'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LinearProgressIndicator(
            key: const Key('tab-progress'),
            value: widget.timeline.totalBeats == 0
                ? 0
                : widget.practice.beat / widget.timeline.totalBeats,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
