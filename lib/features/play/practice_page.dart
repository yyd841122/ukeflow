import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/providers.dart';
import '../../core/model/builtin_strum_patterns.dart';
import '../../core/model/strum_chart.dart';
import '../../core/practice/practice_state.dart';
import '../../data/chord_library.dart';
import 'chart_meta.dart';
import 'play_practice_controller.dart';
import 'practice_view.dart';

/// 跟练会话页(GLOSSARY「跟练」):一首内置弹唱谱的完整练习现场。
///
/// 空闲面板定参数(BPM/节奏型)后开始;运行时页面只是练习状态的轮询壳
/// (ADR-0005):16ms 定时器只当重绘触发器,一切时刻经 practiceStateAt
/// 读引擎时钟,页内无第二时间源。v1 固定速度从头到尾,曲末自动回闲;
/// 暂停/变速/预告窗在工单 10。
class PracticePage extends ConsumerStatefulWidget {
  const PracticePage({super.key, required this.chart});

  final StrumChart chart;

  @override
  ConsumerState<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends ConsumerState<PracticePage> {
  static const _pollInterval = Duration(milliseconds: 16);

  Timer? _poll;

  /// 最近一次轮询算出的练习状态(运行中视图的全部数据源);空闲 null。
  PracticeState? _visual;

  // dispose 里不能用 ref(Riverpod 3):notifier 在 initState 缓存成字段。
  late final PlayPracticeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(playPracticeProvider.notifier);
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
    // 引擎调度与节拍声在下一宏任务前即全停,无任何残留。
    // 节奏型训练页同此纪律(工单 06 顺修)。
    scheduleMicrotask(_controller.stop);
    super.dispose();
  }

  void _onPoll() {
    final timeline = _controller.timeline;
    final anchor = _controller.visualAnchor;
    if (timeline == null || anchor == null) return;
    final practice = practiceStateAt(
      timeline: timeline,
      t0: anchor.t0,
      now: ref.read(audioEngineProvider).engineTime(),
    );
    if (practice == null) {
      _controller.stop(); // 曲末(节拍网格走出最后一拍):回闲,轮询随之自停。
      return;
    }
    // 拍/动作/行/段落任一推进才重绘(与节奏型训练页同一薄渲染纪律)。
    if (practice.beat != _visual?.beat ||
        practice.currentStrum != _visual?.currentStrum ||
        practice.currentLine != _visual?.currentLine ||
        practice.currentSection != _visual?.currentSection) {
      setState(() => _visual = practice);
    }
  }

  void _startPoll() {
    _poll?.cancel();
    setState(() => _visual = null);
    _poll = Timer.periodic(_pollInterval, (_) => _onPoll());
    _onPoll(); // 首查同步完成(与 BeatScheduler 先过窗同理):进入即有画面。
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playPracticeProvider);
    // 运行状态翻转时启停轮询(ref.listen 须在 build 内注册)。
    ref.listen(playPracticeProvider, (previous, next) {
      if (previous?.running != next.running) {
        next.running ? _startPoll() : _stopPoll();
      }
    });
    return Scaffold(
      appBar: AppBar(title: Text(widget.chart.title)),
      body: SafeArea(
        child: state.running
            ? _runningBody(state, ref.watch(chordLibraryProvider))
            : _idleBody(state),
      ),
    );
  }

  // ── 空闲面板:定 BPM 与节奏型,开始 ──────────────────────────────

  Widget _idleBody(PlayPracticeState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chartMetaLine(widget.chart) case final meta?)
            Text(
              meta,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          const SizedBox(height: 12),
          _engineStatus(state),
          const SizedBox(height: 32),
          Text('速度', style: _sectionLabelStyle),
          _bpmControl(state),
          const SizedBox(height: 16),
          Text('节奏型', style: _sectionLabelStyle),
          const SizedBox(height: 8),
          _patternPicker(state),
          const SizedBox(height: 32),
          FilledButton.icon(
            key: const Key('practice-start'),
            // 引擎未就绪不可启;空谱(无段落)不可启。
            onPressed: state.engineReady && widget.chart.sections.isNotEmpty
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

  Widget _engineStatus(PlayPracticeState state) {
    if (state.error != null) {
      return Text(
        state.error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
        textAlign: TextAlign.center,
      );
    }
    return Text(
      state.engineReady ? '引擎就绪' : '引擎初始化中…',
      style: TextStyle(color: Theme.of(context).colorScheme.outline),
      textAlign: TextAlign.center,
    );
  }

  Widget _bpmControl(PlayPracticeState state) {
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
            Text('BPM', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ],
        ),
        Slider(
          key: const Key('bpm-slider'),
          value: state.bpm.toDouble(),
          min: PlayPracticeController.minBpm.toDouble(),
          max: PlayPracticeController.maxBpm.toDouble(),
          divisions:
              PlayPracticeController.maxBpm - PlayPracticeController.minBpm,
          label: '${state.bpm}',
          onChanged: (v) => _controller.setBpm(v.round()),
        ),
      ],
    );
  }

  Widget _patternPicker(PlayPracticeState state) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final pattern in builtinStrumPatterns)
          ChoiceChip(
            key: Key('pattern-${pattern.id}'),
            label: Text(pattern.name),
            selected: state.pattern == pattern,
            onSelected: (_) => _controller.setPattern(pattern),
          ),
      ],
    );
  }

  // ── 运行面板:练习状态的薄渲染 + 停止 ────────────────────────────

  Widget _runningBody(
    PlayPracticeState state,
    AsyncValue<ChordLibrary> libraryAsync,
  ) {
    final timeline = _controller.timeline;
    final visual = _visual;
    if (timeline == null || visual == null) {
      // 首查前的过渡帧(轮询首查同步,常态 ≤ 一帧)。
      return const Center(child: CircularProgressIndicator());
    }
    // 和弦库缺位(资产坏损等极端路径)不冻结练习:指法小图缺席,
    // 和弦名/歌词/箭头照走(视图对查不到的和弦本就兜底显示名字)。
    // Riverpod 3 的 AsyncValue.value 在 error 态返回 null,恰作降级判据。
    final library = libraryAsync.value;
    return Column(
      children: [
        Expanded(
          child: PracticeView(
            timeline: timeline,
            practice: visual,
            pattern: state.pattern,
            chords: library == null
                ? const {}
                : {
                    for (final chord in library.chords) chord.label: chord,
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            key: const Key('practice-stop'),
            onPressed: () => _controller.stop(),
            icon: const Icon(Icons.stop),
            label: const Text('停止'),
          ),
        ),
      ],
    );
  }
}
