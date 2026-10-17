import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/model/builtin_strum_patterns.dart';
import '../../core/model/strum_chart.dart';
import '../../core/model/strum_pattern.dart';
import '../../core/practice/practice_state.dart';
import '../../core/ui/step_slider_control.dart';
import '../../core/ui/engine_status_line.dart';
import '../../core/ui/speed_control.dart';
import '../../data/chord_library.dart';
import '../demo/demo_playback_controller.dart';
import 'chart_meta.dart';
import 'play_practice_controller.dart';
import 'practice_session_shell.dart';
import 'practice_view.dart';

/// 跟练会话页(GLOSSARY「跟练」):一首内置弹唱谱的完整练习现场。
///
/// 空闲面板定参数(BPM/变速/节奏型/参考音)后开始;运行时页面只是练习
/// 状态的轮询壳(轮询壳/预备过渡/弹回即停纪律在 [PracticeSessionState],
/// 与指弹会话页共用)。预备数拍期显示倒计面板;曲末自动回闲。
class PracticePage extends ConsumerStatefulWidget {
  const PracticePage({super.key, required this.chart});

  final StrumChart chart;

  @override
  ConsumerState<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends PracticeSessionState<PracticePage> {
  /// 最近一次轮询算出的练习状态(运行中视图的全部数据源);空闲 null。
  PracticeState? _visual;

  // dispose 里不能用 ref(Riverpod 3):notifier 在 initState 缓存成字段。
  late final PlayPracticeController _controller;
  late final DemoPlaybackController _demo;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(playPracticeProvider.notifier);
    _demo = ref.read(demoPlaybackProvider.notifier);
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
  void resetVisual() => _visual = null;

  @override
  void onPoll() {
    final timeline = _controller.timeline;
    final anchor = _controller.visualAnchor;
    final now = _controller.visualNow();
    if (timeline == null || anchor == null || now == null) return;

    // 预备数拍期:倒计面板(预备拍与正曲同一节拍网格,查询同源;
    // 锚在调度 t0,经控制器查询——曲头反推会有取整误差,见 prepStateAt)。
    if (advancePrep(_controller.prepStateNow()?.count)) return;

    final practice = practiceStateAt(
      timeline: timeline,
      t0: anchor.t0,
      now: now,
    );
    if (practice == null) {
      _controller.stop(); // 曲末(节拍网格走出最后一拍):回闲,轮询随之自停。
      return;
    }
    // 拍/动作/行/段落任一推进才重绘(薄渲染纪律)。
    if (practice.beat != _visual?.beat ||
        practice.currentStrum != _visual?.currentStrum ||
        practice.currentLine != _visual?.currentLine ||
        practice.currentSection != _visual?.currentSection) {
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
    final state = ref.watch(playPracticeProvider);
    final demo = ref.watch(demoPlaybackProvider);
    // 运行状态翻转时启停轮询(ref.listen 须在 build 内注册)。
    ref.listen(playPracticeProvider, (previous, next) {
      if (previous?.running != next.running) {
        next.running ? startPolling() : stopPolling();
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
            : _idleBody(state, demo),
      ),
    );
  }

  // ── 空闲面板:定 BPM/变速/节奏型/参考音,示范试听,开始 ────────────

  Widget _idleBody(PlayPracticeState state, DemoPlaybackState demo) {
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
          EngineStatusLine(
            ready: state.engineReady,
            error: state.error,
            onRetry: () => _controller.warmup(),
          ),
          const SizedBox(height: 32),
          Text('速度', style: _sectionLabelStyle),
          StepSliderControl(
            value: state.bpm,
            min: PlayPracticeController.minBpm,
            max: PlayPracticeController.maxBpm,
            onChanged: _controller.setBpm,
          ),
          const SizedBox(height: 16),
          Text('变速', style: _sectionLabelStyle),
          SpeedControl(
            speed: state.speed,
            min: PlayPracticeController.minSpeed,
            max: PlayPracticeController.maxSpeed,
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
          // 示范试听(工单 11):弹前一键,按当前节奏型+BPM 听整曲扫弦。
          // 试听中参数控件照常可调(在途按开始一刻的快照,再点即听新的)。
          OutlinedButton.icon(
            key: const Key('demo-toggle'),
            onPressed: _demoAction(state, demo),
            icon: Icon(
              demo.status == DemoPlaybackStatus.playing
                  ? Icons.stop
                  : Icons.music_note,
            ),
            label: Text(
              demo.status == DemoPlaybackStatus.playing ? '停止试听' : '示范试听',
            ),
          ),
          if (demo.error != null) ...[
            const SizedBox(height: 8),
            Text(
              demo.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('practice-start'),
            // 引擎未就绪不可启;空谱(无段落)不可启;试听即停不叠声。
            onPressed: state.engineReady && widget.chart.sections.isNotEmpty
                ? () {
                    _demo.stop();
                    _controller.start(chart: widget.chart, chords: _chords());
                  }
                : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始跟练'),
          ),
        ],
      ),
    );
  }

  /// 试听钮的回调:发声中=停止;空闲且可启(引擎就绪+有段落)=开试听;
  /// 准备中/不可启 = 禁用。
  VoidCallback? _demoAction(PlayPracticeState state, DemoPlaybackState demo) {
    if (demo.status == DemoPlaybackStatus.playing) return _demo.stop;
    if (demo.status != DemoPlaybackStatus.idle) return null;
    if (!state.engineReady || widget.chart.sections.isEmpty) return null;
    return () => _demo.start(chart: widget.chart, chords: _chords());
  }

  TextStyle get _sectionLabelStyle => Theme.of(context).textTheme.labelLarge!;

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
          child: prepCount != null
              ? _prepPanel(prepCount!)
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
          SpeedControl(
            speed: state.speed,
            min: PlayPracticeController.minSpeed,
            max: PlayPracticeController.maxSpeed,
            onChanged: _controller.setSpeed,
          ),
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
