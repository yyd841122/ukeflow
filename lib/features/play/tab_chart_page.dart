import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/tab_chart.dart';
import '../../core/practice/tab_practice_state.dart';
import '../../core/ui/bpm_control.dart';
import '../../core/ui/engine_status_line.dart';
import '../../core/ui/speed_control.dart';
import '../demo/demo_playback_controller.dart';
import 'chart_meta.dart';
import 'practice_session_shell.dart';
import 'tab_chart_view.dart';
import 'tab_practice_controller.dart';
import 'tab_practice_view.dart';

/// 指弹跟练会话页(工单 13,GLOSSARY「跟练」):一首内置指弹谱的完整
/// 练习现场。工单 12 的静态读谱视图收进空闲面板作弹前读谱;运行时页面
/// 只是逐音练习状态的轮询壳(轮询壳/预备过渡/弹回即停纪律在
/// [PracticeSessionState],与弹唱跟练页共用)。预备数拍期显示倒计面板;
/// 曲末自动回闲。与弹唱跟练页(PracticePage)同构:无节奏型与参考音
/// 切换——KS 逐音示范声就是参考声。
class TabChartPage extends ConsumerStatefulWidget {
  const TabChartPage({super.key, required this.chart});

  final TabChart chart;

  @override
  ConsumerState<TabChartPage> createState() => _TabChartPageState();
}

class _TabChartPageState extends PracticeSessionState<TabChartPage> {
  /// 最近一次轮询算出的练习状态(运行中视图的全部数据源);空闲 null。
  TabPracticeState? _visual;

  // dispose 里不能用 ref(Riverpod 3):notifier 在 initState 缓存成字段。
  late final TabPracticeController _controller;
  late final DemoPlaybackController _demo;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(tabPracticeProvider.notifier);
    _demo = ref.read(demoPlaybackProvider.notifier);
    // 定参+预热都在帧末:Riverpod 3 禁止 build 生命周期内改 provider 状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.prepareFor(widget.chart);
        _controller.warmup(); // 离开页面即停:不留后台节拍声。
      }
    });
  }

  @override
  void resetVisual() => _visual = null;

  @override
  void onPoll() {
    final timeline = _controller.timeline;
    final anchor = _controller.visualAnchor;
    final now = _controller.visualNow();
    if (timeline == null || anchor == null || now == null) return;

    // 预备数拍期:倒计面板(预备拍与正曲同一节拍网格,查询同源)。
    if (advancePrep(_controller.prepStateNow()?.count)) return;

    final practice = tabPracticeStateAt(
      timeline: timeline,
      t0: anchor.t0,
      now: now,
    );
    if (practice == null) {
      _controller.stop(); // 曲末(节拍网格走出最后一拍):回闲,轮询随之自停。
      return;
    }
    // 当前音/拍/预告窗任一推进才重绘(预告窗入窗不必等拍翻转——预亮
    // 提前量是「左手可提前移动」的本体;窗内下标连续,首+长定窗)。
    final visual = _visual;
    final upcomingChanged =
        visual == null ||
        practice.upcomingNoteIndexes.length !=
            visual.upcomingNoteIndexes.length ||
        (practice.upcomingNoteIndexes.isNotEmpty &&
            practice.upcomingNoteIndexes.first !=
                visual.upcomingNoteIndexes.first);
    if (practice.beat != visual?.beat ||
        practice.currentNoteIndex != visual?.currentNoteIndex ||
        upcomingChanged) {
      setState(() => _visual = practice);
    }
  }

  @override
  void dispose() {
    stopSessionOnUnmount([_controller.stop, _demo.stop]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tabPracticeProvider);
    // 运行状态翻转时启停轮询(ref.listen 须在 build 内注册)。
    ref.listen(tabPracticeProvider, (previous, next) {
      if (previous?.running != next.running) {
        next.running ? startPolling() : stopPolling();
      }
    });
    return Scaffold(
      appBar: AppBar(title: Text(widget.chart.title)),
      body: SafeArea(
        child: state.running ? _runningBody(state) : _idleBody(state),
      ),
    );
  }

  // ── 空闲面板:弹前读谱 + 定 BPM/变速,开始 ────────────────────

  Widget _idleBody(TabSessionState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tabChartMetaLine(widget.chart),
            key: const Key('tab-meta'),
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
          // 弹前读谱(工单 12「能看」收进会话页):静态四线谱,横向可滚。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TabChartView(chart: widget.chart),
          ),
          const SizedBox(height: 24),
          Text('速度', style: _sectionLabelStyle),
          BpmControl(
            bpm: state.bpm,
            min: TabPracticeController.minBpm,
            max: TabPracticeController.maxBpm,
            onChanged: _controller.setBpm,
          ),
          const SizedBox(height: 16),
          Text('变速', style: _sectionLabelStyle),
          const SizedBox(height: 8),
          SpeedControl(
            speed: state.speed,
            min: TabPracticeController.minSpeed,
            max: TabPracticeController.maxSpeed,
            onChanged: _controller.setSpeed,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            key: const Key('tab-practice-start'),
            // 引擎未就绪不可启。
            onPressed: state.engineReady
                ? () => _controller.start(chart: widget.chart)
                : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始跟练'),
          ),
        ],
      ),
    );
  }

  TextStyle get _sectionLabelStyle => Theme.of(context).textTheme.labelLarge!;

  // ── 运行面板:预备倒计/正曲视图 + 控制 ──────────────────────────

  Widget _runningBody(TabSessionState state) {
    return Column(
      children: [
        Expanded(
          child: prepCount != null ? _prepPanel(prepCount!) : _songBody(),
        ),
        _controls(state),
      ],
    );
  }

  /// 预备数拍面板:大字倒计 + 提示。预备拍的声音由调度器管(专用音源),
  /// 这里只读 [prepStateAt] 的倒计。
  Widget _prepPanel(int prepCount) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$prepCount',
          key: const Key('tab-prep-count'),
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
    final timeline = _controller.timeline;
    final visual = _visual;
    if (timeline == null || visual == null) {
      // 首查前的过渡帧(轮询首查同步,常态 ≤ 一帧)。
      return const Center(child: CircularProgressIndicator());
    }
    return TabPracticeView(
      chart: widget.chart,
      timeline: timeline,
      practice: visual,
    );
  }

  /// 运行控制:暂停/继续、回到开头、停止(一行);变速(一行)。
  Widget _controls(TabSessionState state) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const Key('tab-practice-pause'),
                  onPressed: state.paused
                      ? _controller.resume
                      : _controller.pause,
                  icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
                  label: Text(state.paused ? '继续' : '暂停'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('tab-practice-restart'),
                onPressed: _controller.restart,
                icon: const Icon(Icons.replay),
                label: const Text('回到开头'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('tab-practice-stop'),
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
