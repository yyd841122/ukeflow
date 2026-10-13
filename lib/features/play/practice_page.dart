import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/builtin_strum_patterns.dart';
import '../../core/model/strum_chart.dart';
import '../../core/model/strum_pattern.dart';
import '../../core/practice/practice_state.dart';
import '../../data/chord_library.dart';
import 'chart_meta.dart';
import 'play_practice_controller.dart';
import 'practice_view.dart';

/// 跟练会话页(GLOSSARY「跟练」):一首内置弹唱谱的完整练习现场。
///
/// 空闲面板定参数(BPM/变速/节奏型/参考音)后开始;运行时页面只是练习
/// 状态的轮询壳(ADR-0005):16ms 定时器只当重绘触发器,一切时刻经
/// [practiceStateAt]/[prepStateAt] 按 [PlayPracticeController.visualNow]
/// 读出,页内无第二时间源。预备数拍期显示倒计面板;曲末自动回闲。
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

  /// 预备数拍期剩余倒计(4..1);非 null = 倒计面板。正曲期 null。
  int? _prepCount;

  // dispose 里不能用 ref(Riverpod 3):notifier 在 initState 缓存成字段。
  late final PlayPracticeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(playPracticeProvider.notifier);
    // 定参+预热都在帧末:Riverpod 3 禁止 build 生命周期内改 provider 状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.prepareFor(widget.chart, chords: _chords());
        _controller.warmup(); // 离开页面即停:不留后台节拍声。
      }
    });
  }

  /// 和弦名 → 和弦(谱面和弦已过白名单,恒可查;库未就绪给空表降级)。
  Map<String, Chord> _chords() => _chordMap(ref.read(chordLibraryProvider).value);

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
    final now = _controller.visualNow();
    if (timeline == null || anchor == null || now == null) return;

    // 预备数拍期:倒计面板(预备拍与正曲同一节拍网格,查询同源;
    // 锚在调度 t0,经控制器查询——曲头反推会有取整误差,见 prepStateAt)。
    final prep = _controller.prepStateNow();
    if (prep != null) {
      if (prep.count != _prepCount) setState(() => _prepCount = prep.count);
      return;
    }
    if (_prepCount != null) setState(() => _prepCount = null); // 预备毕,切正曲

    final practice = practiceStateAt(
      timeline: timeline,
      t0: anchor.t0,
      now: now,
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
    final state = ref.watch(playPracticeProvider);
    // 运行状态翻转时启停轮询(ref.listen 须在 build 内注册)。
    ref.listen(playPracticeProvider, (previous, next) {
      if (previous?.running != next.running) {
        next.running ? _startPoll() : _stopPoll();
      }
    });
    // 和弦库异步就绪后推给控制器(预备扫弦音源;进页时多半还没就绪)。
    ref.listen(chordLibraryProvider, (previous, next) {
      if (next.value case final ChordLibrary library?) {
        _controller.setChords(_chordMap(library));
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

  // ── 空闲面板:定 BPM/变速/节奏型/参考音,开始 ─────────────────────

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
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          const SizedBox(height: 12),
          _engineStatus(state),
          const SizedBox(height: 32),
          Text('速度', style: _sectionLabelStyle),
          _bpmControl(state),
          const SizedBox(height: 16),
          Text('变速', style: _sectionLabelStyle),
          _SpeedControl(
            speed: state.speed,
            onChanged: _controller.setSpeed,
          ),
          const SizedBox(height: 16),
          Text('节奏型', style: _sectionLabelStyle),
          const SizedBox(height: 8),
          _patternPicker(state),
          const SizedBox(height: 16),
          Text('参考音', style: _sectionLabelStyle),
          const SizedBox(height: 8),
          _ReferenceToggle(
            reference: state.reference,
            onChanged: _controller.setReference,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            key: const Key('practice-start'),
            // 引擎未就绪不可启;空谱(无段落)不可启。
            onPressed: state.engineReady && widget.chart.sections.isNotEmpty
                ? () => _controller.start(chart: widget.chart, chords: _chords())
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
            Text(
              'BPM',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
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

  // ── 运行面板:预备倒计/正曲视图 + 控制 ──────────────────────────

  Widget _runningBody(
    PlayPracticeState state,
    AsyncValue<ChordLibrary> libraryAsync,
  ) {
    return Column(
      children: [
        Expanded(
          child: _prepCount != null
              ? _prepPanel(_prepCount!)
              : _songBody(libraryAsync, state.pattern),
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
          key: const Key('prep-count'),
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

  Widget _songBody(AsyncValue<ChordLibrary> libraryAsync, StrumPattern pattern) {
    final timeline = _controller.timeline;
    final visual = _visual;
    if (timeline == null || visual == null) {
      // 首查前的过渡帧(轮询首查同步,常态 ≤ 一帧)。
      return const Center(child: CircularProgressIndicator());
    }
    // 和弦库缺位(资产坏损等极端路径)不冻结练习:指法小图缺席,
    // 和弦名/歌词/箭头照走(视图对查不到的和弦本就兜底显示名字)。
    // Riverpod 3 的 AsyncValue.value 在 error 态返回 null,恰作降级判据。
    final chords = _chordMap(libraryAsync.value);
    return PracticeView(
      timeline: timeline,
      practice: visual,
      pattern: pattern,
      chords: chords,
    );
  }

  /// 运行控制:暂停/继续、回到开头、停止(一行);变速与参考音(两行)。
  Widget _controls(PlayPracticeState state) {
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
                  key: const Key('practice-pause'),
                  onPressed: state.paused
                      ? _controller.resume
                      : _controller.pause,
                  icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
                  label: Text(state.paused ? '继续' : '暂停'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('practice-restart'),
                onPressed: _controller.restart,
                icon: const Icon(Icons.replay),
                label: const Text('回到开头'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('practice-stop'),
                onPressed: _controller.stop,
                icon: const Icon(Icons.stop),
                label: const Text('停止'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _SpeedControl(speed: state.speed, onChanged: _controller.setSpeed),
          _ReferenceToggle(
            reference: state.reference,
            onChanged: _controller.setReference,
          ),
        ],
      ),
    );
  }
}

/// 和弦库 → 和弦名映射(跟练页三处共用;null 库给空表降级)。
Map<String, Chord> _chordMap(ChordLibrary? library) => library == null
    ? const {}
    : {for (final chord in library.chords) chord.label: chord};

/// 变速控制(空闲与运行共用):原速的 50%–100%,5% 一档。
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
            min: PlayPracticeController.minSpeed,
            max: PlayPracticeController.maxSpeed,
            divisions: 10,
            label: '$percent%',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// 参考音切换(空闲与运行共用):节拍声 / 示范扫弦声。
class _ReferenceToggle extends StatelessWidget {
  const _ReferenceToggle({required this.reference, required this.onChanged});

  final ReferenceSound reference;
  final ValueChanged<ReferenceSound> onChanged;

  @override
  Widget build(BuildContext context) {
    // ButtonSegment 无 key 参数:Key 挂在 label 上(点 label 即选段)。
    return SegmentedButton<ReferenceSound>(
      segments: const [
        ButtonSegment(
          value: ReferenceSound.beat,
          icon: Icon(Icons.music_note),
          label: Text('节拍声', key: Key('reference-beat')),
        ),
        ButtonSegment(
          value: ReferenceSound.strum,
          icon: Icon(Icons.graphic_eq),
          label: Text('示范扫弦', key: Key('reference-strum')),
        ),
      ],
      selected: {reference},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
