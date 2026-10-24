import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/beat_scheduling.dart' show beatsPerBar;
import '../../core/chart/score_sheet_defs.dart';
import '../../core/model/tab_chart.dart';
import '../../core/practice/dual_track_timeline.dart';
import '../../core/practice/score_sheet_layout.dart';
import '../../core/ui/engine_status_line.dart';
import '../../core/ui/speed_control.dart';
import '../../core/ui/step_slider_control.dart';
import 'practice_session_shell.dart';
import 'score_sheet_view.dart';
import 'tab_practice_controller.dart';

/// 谱面视图会话页(工单 39,GLOSSARY「谱面视图」):独奏谱点开默认进这里
/// ——四层对齐谱面(和弦图+和弦名 / TAB 伴奏 / 简谱旋律 / 歌词)+ 跟随
/// 高亮 + 单轨/双轨示范。空闲面板 = 弹前读谱 + 定速 + 轨道选择;运行 =
/// 预备数拍 → 跟随高亮纵向跟滚。
///
/// 会话机制(预备数拍/暂停恢复/变速/循环/曲末回闲)整表复用指弹跟练
/// 控制器(TabPracticeController):单轨示范 = 伴奏谱原样;双轨混播 =
/// [buildDualTrackChart] 合并谱(旋律轨播放侧 +4 半音合流 E 调)。页内
/// 无第二时间源(ADR-0005):跟随当位查 [ScoreSheetLayout.currentAt],
/// 主轴拍位自引擎时刻换算。
class ScoreSheetPage extends ConsumerStatefulWidget {
  const ScoreSheetPage({
    super.key,
    required this.def,
    required this.tabChart,
    required this.melodyChart,
  });

  final ScoreSheetDef def;
  final TabChart tabChart;
  final TabChart melodyChart;

  @override
  ConsumerState<ScoreSheetPage> createState() => _ScoreSheetPageState();
}

/// 示范轨道(GLOSSARY「双轨混播」):单轨 = 只伴奏;双轨 = 伴奏 + 旋律
/// 代唱。阶段A 默认单轨;切换在空闲面板,运行中固定。
enum ScoreTrackMode { accompaniment, dual }

class _ScoreSheetPageState extends PracticeSessionState<ScoreSheetPage> {
  ScoreTrackMode _trackMode = ScoreTrackMode.accompaniment;
  ScoreCursor? _visual;

  late final TabPracticeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(tabPracticeProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.prepareFor(_chartFor(_trackMode));
        _controller.warmup(); // 离开页面即停:不留后台节拍声。
      }
    });
  }

  @override
  void resetVisual() {
    _visual = null;
  }

  /// 轨道 → 会话谱:单轨 = 伴奏原样;双轨 = 合并谱(旋律 +20 拍/+4 半音
  /// 在编译处落定)。
  TabChart _chartFor(ScoreTrackMode mode) => switch (mode) {
    ScoreTrackMode.accompaniment => widget.tabChart,
    ScoreTrackMode.dual =>
      buildDualTrackChart(widget.def, widget.tabChart, widget.melodyChart),
  };

  @override
  void onPoll() {
    final timeline = _controller.timeline;
    final anchor = _controller.visualAnchor;
    final now = _controller.visualNow();
    if (timeline == null || anchor == null || now == null) return;

    if (advancePrep(_controller.prepStateNow()?.count)) return;

    final elapsedMs = (now - anchor.t0).inMicroseconds / 1000;
    final mainBeat = elapsedMs / anchor.periodMs;
    if (mainBeat >= timeline.totalBeats) {
      // 曲末:循环开→接下一遍;关→回闲。
      _controller.passEnd();
      return;
    }
    final cursor = _layout.currentAt(mainBeat);
    if (cursor != _visual) {
      setState(() => _visual = cursor);
    }
  }

  int _systemOfCursor(ScoreCursor cursor) =>
      _layout.systemOfBeat(cursor.tabIndex >= 0
          ? _layout.tabNotes[cursor.tabIndex].beat
          : 0.0);

  /// 布局缓存:谱面整页不变,内容宽变了才重建(onPoll 每拍查询共享)。
  ScoreSheetLayout get _layout {
    final width = _contentWidth ?? 360;
    if (_layoutCache == null || _layoutWidth != width) {
      _layoutCache = ScoreSheetLayout(
        def: widget.def,
        tabChart: widget.tabChart,
        melodyChart: widget.melodyChart,
        contentWidth: width,
      );
      _layoutWidth = width;
    }
    return _layoutCache!;
  }

  ScoreSheetLayout? _layoutCache;
  double? _layoutWidth;
  double? _contentWidth;

  @override
  void dispose() {
    stopSessionOnUnmount([_controller.stop]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tabPracticeProvider);
    ref.listen(tabPracticeProvider, (previous, next) {
      if (previous?.running != next.running) {
        next.running ? startPolling() : stopPolling();
      }
    });
    return Scaffold(
      appBar: AppBar(title: Text(widget.def.title)),
      body: SafeArea(
        child: state.running ? _runningBody(state) : _idleBody(state),
      ),
    );
  }

  // ── 空闲面板:弹前读谱 + 定速/变速 + 轨道,开始 ──────────────────

  Widget _idleBody(TabSessionState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Text(
          _metaLine,
          key: const Key('score-meta'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 12),
        EngineStatusLine(
          ready: state.engineReady,
          error: state.error,
          onRetry: () => _controller.warmup(),
        ),
        const SizedBox(height: 16),
        // 弹前读谱缩为一行(首系统,与跟练视图同款)——用户反馈整页
        // 太长,开始示范按钮要一屏可见(2026-10-24)。
        ScoreSheetSystemView(
          def: widget.def,
          tabChart: widget.tabChart,
          melodyChart: widget.melodyChart,
          system: 0,
        ),
        const SizedBox(height: 12),
        SegmentedButton<ScoreTrackMode>(
          segments: const [
            ButtonSegment(
              value: ScoreTrackMode.accompaniment,
              icon: Icon(Icons.music_note),
              label: Text('伴奏示范'),
            ),
            ButtonSegment(
              value: ScoreTrackMode.dual,
              icon: Icon(Icons.layers),
              label: Text('双轨混播'),
            ),
          ],
          selected: {_trackMode},
          onSelectionChanged: (selection) {
            final mode = selection.first;
            if (mode == _trackMode) return;
            setState(() => _trackMode = mode);
            // 换轨即换会话谱:BPM 重定 + 该轨拨弦音源预注入。
            _controller.prepareFor(_chartFor(mode));
          },
        ),
        const SizedBox(height: 12),
        Text('速度', style: _sectionLabelStyle),
        StepSliderControl(
          value: state.bpm,
          min: TabPracticeController.minBpm,
          max: TabPracticeController.maxBpm,
          onChanged: _controller.setBpm,
        ),
        // 变速在运行控制行(与四线谱跟练同),空闲面板省一屏。
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('score-practice-start'),
          onPressed: state.engineReady
              ? () => _controller.start(chart: _chartFor(_trackMode))
              : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('开始示范'),
        ),
        ],
      ),
    );
  }

  String get _metaLine => '谱面视图 · ${widget.def.subtitleLine(widget.tabChart)}';

  TextStyle get _sectionLabelStyle => Theme.of(context).textTheme.labelLarge!;

  // ── 运行面板:预备倒计/跟随视图 + 控制 ──────────────────────────

  Widget _runningBody(TabSessionState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _contentWidth = constraints.maxWidth;
        return Column(
          children: [
            Expanded(child: prepCount != null ? _prepPanel(prepCount!) : _songBody()),
            _controls(state),
          ],
        );
      },
    );
  }

  Widget _prepPanel(int prepCount) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$prepCount',
          key: const Key('score-prep-count'),
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          prepCount > 2 ? '跟着拍子数,准备手指' : '马上开弹',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      ],
    );
  }

  Widget _songBody() {
    final visual = _visual;
    final timeline = _controller.timeline;
    if (visual == null || timeline == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // 运行态只出当前一行(谱表系统),播完切下一行——真机反馈整页
    // 折行难追播放点(2026-10-24),与四线谱跟练的阶梯平移同一纪律。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ScoreSheetSystemView(
              def: widget.def,
              tabChart: widget.tabChart,
              melodyChart: widget.melodyChart,
              system: _systemOfCursor(visual),
              cursor: visual,
              layout: _layoutWidth == _contentWidth ? _layoutCache : null,
            ),
          ),
        ),
        Text(
          '${_beatInBar(visual)}',
          key: const Key('score-beat-number'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LinearProgressIndicator(
            key: const Key('score-progress'),
            value: timeline.totalBeats == 0
                ? 0
                : (visual.tabIndex < 0
                      ? 0
                      : _layout.tabNotes[visual.tabIndex].beat /
                            timeline.totalBeats),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// 小节内拍号(1..4,随当位音所在拍;曲首无当前音记 1)。
  int _beatInBar(ScoreCursor cursor) {
    if (cursor.tabIndex < 0) return 1;
    final beat = _layout.tabNotes[cursor.tabIndex].beat;
    return (beat % beatsPerBar).floor() + 1;
  }


  Widget _controls(TabSessionState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilterChip(
                key: const Key('score-practice-loop'),
                selected: state.loop,
                onSelected: (_) => _controller.toggleLoop(),
                avatar: const Icon(Icons.repeat, size: 18),
                label: const Text('单曲循环'),
              ),
              if (state.loop) ...[
                const SizedBox(width: 12),
                Text('第 ${state.pass} 遍',
                    style: Theme.of(context).textTheme.labelLarge),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const Key('score-practice-pause'),
                  onPressed: state.paused ? _controller.resume : _controller.pause,
                  icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
                  label: Text(state.paused ? '继续' : '暂停'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('score-practice-restart'),
                onPressed: _controller.restart,
                icon: const Icon(Icons.replay),
                label: const Text('回到开头'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('score-practice-stop'),
                onPressed: _controller.stop,
                icon: const Icon(Icons.stop),
                label: const Text('停止'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SpeedControl(
            speed: state.speed,
            min: TabPracticeController.minSpeed,
            max: TabPracticeController.maxSpeed,
            onChanged: _controller.setSpeed,
          ),
        ],
      ),
    );
  }
}
