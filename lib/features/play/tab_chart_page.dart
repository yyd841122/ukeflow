import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/tab_chart.dart';
import '../../core/practice/tab_practice_state.dart';
import '../demo/demo_playback_controller.dart';
import 'chart_meta.dart';
import 'tab_chart_view.dart';
import 'tab_practice_controller.dart';
import 'tab_practice_view.dart';

/// 指弹跟练会话页(工单 13,GLOSSARY「跟练」):一首内置指弹谱的完整
/// 练习现场。工单 12 的静态读谱视图收进空闲面板作弹前读谱;运行时页面
/// 只是逐音练习状态的轮询壳(ADR-0005):16ms 定时器只当重绘触发器,
/// 一切时刻经 [tabPracticeStateAt]/[prepStateAt] 按
/// [TabPracticeController.visualNow] 读出,页内无第二时间源。预备数拍
/// 期显示倒计面板;曲末自动回闲。与弹唱跟练页(PracticePage)同构:
/// 无节奏型与参考音切换——KS 逐音示范声就是参考声。
class TabChartPage extends ConsumerStatefulWidget {
  const TabChartPage({super.key, required this.chart});

  final TabChart chart;

  @override
  ConsumerState<TabChartPage> createState() => _TabChartPageState();
}

class _TabChartPageState extends ConsumerState<TabChartPage> {
  static const _pollInterval = Duration(milliseconds: 16);

  Timer? _poll;

  /// 最近一次轮询算出的练习状态(运行中视图的全部数据源);空闲 null。
  TabPracticeState? _visual;

  /// 预备数拍期剩余倒计(4..1);非 null = 倒计面板。正曲期 null。
  int? _prepCount;

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
  void dispose() {
    _poll?.cancel();
    // 弹回即停。Riverpod 3 禁止 widget unmount 期间改 provider 状态
    // (直接 stop 会抛"tried to modify a provider"),推迟一个微任务:
    // 引擎调度与节拍声/拨弦声在下一宏任务前即全停,无任何残留。
    // 与弹唱跟练页同一纪律(工单 09)。
    scheduleMicrotask(() {
      _controller.stop();
      _demo.stop();
    });
    super.dispose();
  }

  void _onPoll() {
    final timeline = _controller.timeline;
    final anchor = _controller.visualAnchor;
    final now = _controller.visualNow();
    if (timeline == null || anchor == null || now == null) return;

    // 预备数拍期:倒计面板(预备拍与正曲同一节拍网格,查询同源)。
    final prep = _controller.prepStateNow();
    if (prep != null) {
      if (prep.count != _prepCount) setState(() => _prepCount = prep.count);
      return;
    }
    if (_prepCount != null) setState(() => _prepCount = null); // 预备毕,切正曲

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

  void _startPoll() {
    _poll?.cancel();
    setState(() {
      _visual = null;
      _prepCount = null;
    });
    _poll = Timer.periodic(_pollInterval, (_) => _onPoll());
    _onPoll(); // 首查同步完成(与 BeatScheduler 先过窗同理):进入即有画面。
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tabPracticeProvider);
    // 运行状态翻转时启停轮询(ref.listen 须在 build 内注册)。
    ref.listen(tabPracticeProvider, (previous, next) {
      if (previous?.running != next.running) {
        next.running ? _startPoll() : _stopPoll();
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
          _engineStatus(state),
          const SizedBox(height: 16),
          // 弹前读谱(工单 12「能看」收进会话页):静态四线谱,横向可滚。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TabChartView(chart: widget.chart),
          ),
          const SizedBox(height: 24),
          Text('速度', style: _sectionLabelStyle),
          _bpmControl(state),
          const SizedBox(height: 16),
          Text('变速', style: _sectionLabelStyle),
          const SizedBox(height: 8),
          _SpeedControl(speed: state.speed, onChanged: _controller.setSpeed),
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

  Widget _engineStatus(TabSessionState state) {
    if (state.error != null) {
      return Column(
        children: [
          Text(
            state.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // 初始化失败可原地重试,不必重进页面(warmup 自带在途合并)。
          TextButton.icon(
            key: const Key('warmup-retry'),
            onPressed: () => _controller.warmup(),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      );
    }
    return Text(
      state.engineReady ? '引擎就绪' : '引擎初始化中…',
      style: TextStyle(color: Theme.of(context).colorScheme.outline),
      textAlign: TextAlign.center,
    );
  }

  Widget _bpmControl(TabSessionState state) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const Key('bpm-minus'),
              onPressed: () => _controller.setBpm(state.bpm - 1),
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 96,
              child: Text(
                '${state.bpm}',
                key: const Key('bpm-value'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              key: const Key('bpm-plus'),
              onPressed: () => _controller.setBpm(state.bpm + 1),
              icon: const Icon(Icons.add),
            ),
            Text(
              'BPM',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
        Slider(
          key: const Key('bpm-slider'),
          value: state.bpm.toDouble(),
          min: TabPracticeController.minBpm.toDouble(),
          max: TabPracticeController.maxBpm.toDouble(),
          divisions:
              TabPracticeController.maxBpm - TabPracticeController.minBpm,
          label: '${state.bpm}',
          onChanged: (v) => _controller.setBpm(v.round()),
        ),
      ],
    );
  }

  // ── 运行面板:预备倒计/正曲视图 + 控制 ──────────────────────────

  Widget _runningBody(TabSessionState state) {
    return Column(
      children: [
        Expanded(
          child: _prepCount != null ? _prepPanel(_prepCount!) : _songBody(),
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
          _SpeedControl(speed: state.speed, onChanged: _controller.setSpeed),
        ],
      ),
    );
  }
}

/// 变速控制(空闲与运行共用):原速的 50%–100%,5% 一档。
/// (与弹唱跟练页的同名控件重复——BPM/变速控件的提取归票 19,工单 09
/// 已注记;此处维持两谱会话页各自成形的现状。)
class _SpeedControl extends StatelessWidget {
  const _SpeedControl({required this.speed, required this.onChanged});

  final double speed;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final percent = (speed * 100).round();
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            '$percent%',
            key: const Key('speed-value'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: Slider(
            key: const Key('speed-slider'),
            value: speed,
            min: TabPracticeController.minSpeed,
            max: TabPracticeController.maxSpeed,
            divisions: 10,
            label: '$percent%',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
