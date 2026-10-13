import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/beat_scheduling.dart';
import '../../core/audio/beat_scheduler.dart';
import '../../core/audio/providers.dart';
import '../../core/audio/tick_synth.dart';

/// 节拍器页状态。
class MetronomeState {
  const MetronomeState({
    required this.bpm,
    required this.engineReady,
    required this.running,
    required this.scheduledBeats,
    this.error,
  });

  const MetronomeState.initial()
      : this(
          bpm: MetronomeController.defaultBpm,
          engineReady: false,
          running: false,
          scheduledBeats: 0,
        );

  /// 拍频(40–208,工单验收范围)。
  final int bpm;
  final bool engineReady;

  /// 引擎错误文案(初始化失败/运行中引擎异常);null = 正常。
  final String? error;
  final bool running;

  /// 本次运行已预定拍数(真机长测核对 600 拍用);停止即清零。
  final int scheduledBeats;

  MetronomeState copyWith({
    int? bpm,
    bool? engineReady,
    Object? error = _sentinel,
    bool? running,
    int? scheduledBeats,
  }) =>
      MetronomeState(
        bpm: bpm ?? this.bpm,
        engineReady: engineReady ?? this.engineReady,
        error: identical(error, _sentinel) ? this.error : error as String?,
        running: running ?? this.running,
        scheduledBeats: scheduledBeats ?? this.scheduledBeats,
      );

  static const _sentinel = Object();
}

final metronomeProvider =
    NotifierProvider<MetronomeController, MetronomeState>(
  MetronomeController.new,
);

/// 节拍器控制器:启停、BPM、4/4 强弱拍音源选择。
/// 一切时刻读引擎时钟(ADR-0005);发声经 BeatScheduler → playClocked。
class MetronomeController extends Notifier<MetronomeState> {
  static const minBpm = 40;
  static const maxBpm = 208;
  static const defaultBpm = 120;

  EngineSound? _strong;
  EngineSound? _weak;
  BeatScheduler? _scheduler;

  @override
  MetronomeState build() {
    ref.onDispose(_teardown);
    return const MetronomeState.initial();
  }

  /// 引擎预热 + 注入强弱拍音源;失败进 error 状态,页面上可见。
  Future<void> warmup() async {
    if (state.engineReady) return;
    try {
      final engine = ref.read(audioEngineProvider);
      await engine.ensureInitialized();
      // 音源与引擎解耦(ADR-0004):WAV 由 TickSynth 代码合成,内存注入。
      _strong = await engine.loadMem('tick_strong', TickSynth.strong());
      _weak = await engine.loadMem('tick_weak', TickSynth.weak());
      state = state.copyWith(engineReady: true);
    } catch (error) {
      state = state.copyWith(error: '引擎初始化失败:$error');
    }
  }

  void toggle() => state.running ? stop() : start();

  /// 视觉层锚点:运行中的时间轴起点与拍周期;未运行 null。
  ({Duration t0, double periodMs})? get visualAnchor => _scheduler?.anchor;

  /// UI 轮询调用:同步已预定拍数(仅运行时有意义)。
  void refreshScheduled() {
    final scheduler = _scheduler;
    if (scheduler == null || !state.running) return;
    final count = scheduler.scheduledCount;
    if (count != state.scheduledBeats) {
      state = state.copyWith(scheduledBeats: count);
    }
  }

  void start() {
    if (!state.engineReady || state.running) return;
    final scheduler = BeatScheduler(
      engine: ref.read(audioEngineProvider),
      pickSound: _pick,
      onError: _onEngineError,
    );
    scheduler.start(periodMs: 60000 / state.bpm);
    _scheduler = scheduler;
    state = state.copyWith(running: true, error: null);
    refreshScheduled();
  }

  void stop() {
    _scheduler?.stop();
    _scheduler = null;
    if (state.running) {
      state = state.copyWith(running: false, scheduledBeats: 0);
    }
  }

  /// 设 BPM(钳制 40–208);运行中即时生效(相位保持重锚定)。
  void setBpm(int bpm) {
    state = state.copyWith(bpm: bpm.clamp(minBpm, maxBpm));
    _scheduler?.changePeriod(60000 / state.bpm);
    refreshScheduled();
  }

  /// 4/4 强弱:每小节第 1 拍用强拍音源。
  EngineSound? _pick(int beat) => beat % beatsPerBar == 0 ? _strong : _weak;

  void _onEngineError(Object error) {
    // 驱动器抛错路径已自停;这里只清引用、改状态。
    _scheduler = null;
    state = state.copyWith(
      running: false,
      scheduledBeats: 0,
      error: '引擎出错,节拍器已停止:$error',
    );
  }

  void _teardown() {
    _scheduler?.stop();
    _scheduler = null;
  }
}
