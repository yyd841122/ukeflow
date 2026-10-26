import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/beat_scheduling.dart' show beatsPerBar;
import '../../core/chart/score_sheet_defs.dart';
import '../../core/import/score_ir_editor.dart';
import '../../core/model/tab_chart.dart';
import '../../core/practice/dual_track_timeline.dart';
import '../../core/practice/score_sheet_layout.dart';
import '../../core/ui/engine_status_line.dart';
import '../../core/ui/speed_control.dart';
import '../../core/ui/step_slider_control.dart';
import '../../data/chart_providers.dart';
import '../../data/providers.dart';
import 'note_tune_panel.dart';
import 'practice_session_shell.dart';
import 'score_ir_edit_session.dart';
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
    this.importedSoloRowId,
  });

  final ScoreSheetDef def;
  final TabChart tabChart;
  final TabChart melodyChart;

  /// 导入独奏谱的数据库行 id(工单 45):非空 = 谱面音符可点选轻改,
  /// 改源存回后本页经导入谱流重物化换源。内置谱为 null(不可轻改)。
  final int? importedSoloRowId;

  @override
  ConsumerState<ScoreSheetPage> createState() => _ScoreSheetPageState();
}

/// 示范轨道(GLOSSARY「双轨混播」):单轨 = 只伴奏;双轨 = 伴奏 + 旋律
/// 代唱。阶段A 默认单轨;切换在空闲面板,运行中固定。
enum ScoreTrackMode { accompaniment, dual }

class _ScoreSheetPageState extends PracticeSessionState<ScoreSheetPage> {
  ScoreTrackMode _trackMode = ScoreTrackMode.accompaniment;
  ScoreCursor? _visual;
  final _scroll = ScrollController();

  /// 当前展示的三源(初始照 widget;轻改落库后经导入谱流换新)。
  late ScoreSheetDef _def = widget.def;
  late TabChart _tabChart = widget.tabChart;
  late TabChart _melodyChart = widget.melodyChart;

  /// 轻改会话(工单 45;仅导入谱持有)。
  ScoreIrEditSession? get _editSession => widget.importedSoloRowId == null
      ? null
      : ScoreIrEditSession(
          ref.read(importedSoloChartsDaoProvider),
          rowId: widget.importedSoloRowId!,
        );

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

  /// 轻改落库后的重物化换源(工单 45):导入谱流推送新条目,三源有实
  /// 变才换(无关行的写库也会推流,内容同就不折腾会话),布局缓存一并
  /// 作废,空闲态重定会话谱;运行中不动(轻改只在空闲面板发生)。
  void _onImportedSoloChanged(List<ImportedSoloEntry> entries) {
    final entry = entries
        .where((e) => e.id == widget.importedSoloRowId)
        .firstOrNull;
    if (entry is! ReadyImportedSolo) return;
    if (_sameSources(entry)) return;
    setState(() {
      _def = entry.def;
      _tabChart = entry.accompaniment;
      _melodyChart = entry.melody;
      _layoutCache = null;
    });
    if (!ref.read(tabPracticeProvider).running) {
      _controller.prepareFor(_chartFor(_trackMode));
    }
  }

  /// 三源实变判定:逐音 (弦,品,拍) + 定义字段(物化逐次新建实例,
  /// 不能比身份;无关行推流时内容不变,免一次会话重定)。
  bool _sameSources(ReadyImportedSolo entry) {
    bool sameNotes(List<TabNote> a, List<TabNote> b) =>
        a.length == b.length &&
        [for (var i = 0; i < a.length; i++) (a[i].string, a[i].fret, a[i].beat)]
                .toString() ==
            [
              for (var i = 0; i < b.length; i++)
                (b[i].string, b[i].fret, b[i].beat),
            ].toString();
    return identical(entry.def, _def) ||
        (entry.def.id == _def.id &&
            entry.def.melodyAlignBeats == _def.melodyAlignBeats &&
            entry.def.keySignature == _def.keySignature &&
            sameNotes(entry.accompaniment.notes, _tabChart.notes) &&
            sameNotes(entry.melody.notes, _melodyChart.notes));
  }

  /// 轨道 → 会话谱:单轨 = 伴奏错峰播放谱;双轨 = 合并谱(旋律 +20 拍/
  /// +4 半音,伴奏同样错峰)。四线谱跟练次入口仍用原谱(模型分界不动)。
  TabChart _chartFor(ScoreTrackMode mode) => buildScorePlaybackChart(
    _def,
    _tabChart,
    melodyChart: mode == ScoreTrackMode.dual ? _melodyChart : null,
  );

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
    // 流水跟滚:每帧按引擎时刻平移横带(播放头恒在视口左 1/3),
    // 弹过的向左滑出、后面的从右补上;高亮仍只在当位变化才重绘。
    final viewportWidth = _contentWidth ?? 360;
    final target =
        (_layout.stripX(mainBeat) -
                viewportWidth * ScoreSheetLayout.followViewportFraction)
            .clamp(
              0.0,
              _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0,
            );
    if (_scroll.hasClients && (_scroll.offset - target).abs() >= 0.5) {
      _scroll.jumpTo(target);
    }

    final cursor = _layout.currentAt(mainBeat);
    if (cursor != _visual) {
      setState(() => _visual = cursor);
    }
  }

  /// 布局缓存:横带几何一次构造(onPoll 每帧查询共享;轻改换源作废)。
  ScoreSheetLayout get _layout => _layoutCache ??= ScoreSheetLayout(
    def: _def,
    tabChart: _tabChart,
    melodyChart: _melodyChart,
  );

  ScoreSheetLayout? _layoutCache;
  double? _contentWidth;

  @override
  void dispose() {
    _scroll.dispose();
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
    // 轻改刷新源(工单 45):导入谱流推送即换三源。
    if (widget.importedSoloRowId != null) {
      ref.listen(importedSoloChartsProvider, (_, next) {
        final entries = next.value;
        if (entries != null) _onImportedSoloChanged(entries);
      });
    }
    return Scaffold(
      appBar: AppBar(title: Text(_def.title)),
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
          // 弹前读谱 = 横带全景(横向可拖;开始示范按钮一屏可见)。
          // 导入谱接点选轻改(工单 45):点音弹微调面板。
          ScoreStripView(
            def: _def,
            tabChart: _tabChart,
            melodyChart: _melodyChart,
            onNoteTap: _editSession == null ? null : _openTunePanel,
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

  /// 点选音 → 微调面板(工单 45);存回 true = 源已落库,流会推新源。
  Future<void> _openTunePanel(ScoreIrNoteRef noteRef) async {
    final session = _editSession;
    if (session == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NoteTunePanel(session: session, noteRef: noteRef),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已存回,谱面已刷新')));
    }
  }

  String get _metaLine => '谱面视图 · ${_def.subtitleLine(_tabChart)}';

  TextStyle get _sectionLabelStyle => Theme.of(context).textTheme.labelLarge!;

  // ── 运行面板:预备倒计/跟随视图 + 控制 ──────────────────────────

  Widget _runningBody(TabSessionState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _contentWidth = constraints.maxWidth;
        return Column(
          children: [
            Expanded(
              child: prepCount != null ? _prepPanel(prepCount!) : _songBody(),
            ),
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
    // 流水展示(用户真机反馈 2026-10-24):横带按引擎时刻匀速左移,
    // 播放头恒在视口左 1/3,弹过的滑出、后面的从右补上,不跳行。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: ScoreStripView(
                  def: _def,
                  tabChart: _tabChart,
                  melodyChart: _melodyChart,
                  cursor: visual,
                  scrollController: _scroll,
                  layout: _layoutCache,
                ),
              ),
              // 播放头标线(视口左 1/3,与跟滚锚点同位)。
              Positioned(
                left:
                    (_contentWidth ?? 360) *
                        ScoreSheetLayout.followViewportFraction -
                    1,
                top: 0,
                bottom: 0,
                width: 2,
                child: ColoredBox(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.35),
                ),
              ),
            ],
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
                Text(
                  '第 ${state.pass} 遍',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const Key('score-practice-pause'),
                  onPressed: state.paused
                      ? _controller.resume
                      : _controller.pause,
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
