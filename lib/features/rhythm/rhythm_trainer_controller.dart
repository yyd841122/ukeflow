import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/beat_scheduling.dart';
import '../../core/audio/beat_scheduler.dart';
import '../../core/audio/providers.dart';
import '../../core/audio/tick_synth.dart';
import '../../core/model/builtin_strum_patterns.dart';
import '../../core/model/strum_pattern.dart';

/// 节奏型训练页状态。
class RhythmTrainerState {
  const RhythmTrainerState({
    required this.pattern,
    required this.bpm,
    required this.engineReady,
    required this.clickOn,
    required this.running,
    this.error,
  });

  factory RhythmTrainerState.initial() => RhythmTrainerState(
        pattern: builtinStrumPatterns.first,
        bpm: RhythmTrainerController.defaultBpm,
        engineReady: false,
        clickOn: true,
        running: false,
      );

  /// 当前节奏型;运行中换型即时生效(箭头纯函数逐帧读它)。
  final StrumPattern pattern;

  /// 拍频(40–208,慢练下限 40 是工单验收)。
  final int bpm;
  final bool engineReady;

  /// 节拍声开关(箭头训练不受影响)。
  final bool clickOn;
  final bool running;

  /// 引擎错误文案(初始化失败/运行中引擎异常);null = 正常。
  final String? error;

  RhythmTrainerState copyWith({
    StrumPattern? pattern,
    int? bpm,
    bool? engineReady,
    bool? clickOn,
    bool? running,
    Object? error = _sentinel,
  }) =>
      RhythmTrainerState(
        pattern: pattern ?? this.pattern,
        bpm: bpm ?? this.bpm,
        engineReady: engineReady ?? this.engineReady,
        clickOn: clickOn ?? this.clickOn,
        running: running ?? this.running,
        error: identical(error, _sentinel) ? this.error : error as String?,
      );

  static const _sentinel = Object();
}

final rhythmTrainerProvider =
    NotifierProvider<RhythmTrainerController, RhythmTrainerState>(
  RhythmTrainerController.new,
);

/// 节奏型训练控制器:选节奏型 + BPM 慢练 + 节拍声开关。
///
/// 节拍声直接复用节拍器的 BeatScheduler→playClocked 管线(4/4 强弱拍);
/// 箭头高亮不进调度——UI 轮询经 [rhythmPracticeAt] 纯函数按引擎时刻算出,
/// 换节奏型只是换查表参数,不动时间轴。
class RhythmTrainerController extends Notifier<RhythmTrainerState> {
  static const minBpm = 40;
  static const maxBpm = 208;

  /// 慢练页默认速度:低于节拍器默认,起步即可逐拍跟箭头。
  static const defaultBpm = 80;

  EngineSound? _strong;
  EngineSound? _weak;
  BeatScheduler? _scheduler;
  bool _clickOn = true;

  @override
  RhythmTrainerState build() {
    ref.onDispose(_teardown);
    return RhythmTrainerState.initial();
  }

  /// 引擎预热 + 注入强弱拍音源;失败进 error 状态,页面上可见。
  Future<void> warmup() async {
    if (state.engineReady) return;
    try {
      final engine = ref.read(audioEngineProvider);
      await engine.ensureInitialized();
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

  /// 换节奏型:纯函数每次轮询重读 state.pattern,调度无需任何动作。
  void setPattern(StrumPattern pattern) =>
      state = state.copyWith(pattern: pattern);

  /// 节拍声开关。生效于后续预定(400ms 提前量窗内已预定的拍至多再响一声)。
  void toggleClick() {
    _clickOn = !_clickOn;
    state = state.copyWith(clickOn: _clickOn);
  }

  void start() {
    if (!state.engineReady || state.running) return;
    final scheduler = BeatScheduler(
      engine: ref.read(audioEngineProvider),
      pickSound: _pick,
      onError: _onEngineError,
    );
    scheduler.start(bpm: state.bpm);
    _scheduler = scheduler;
    state = state.copyWith(running: true, error: null);
  }

  void stop() {
    _scheduler?.stop();
    _scheduler = null;
    if (state.running) {
      state = state.copyWith(running: false);
    }
  }

  /// 设 BPM(钳制 40–208);运行中即时生效(相位保持重锚定)。
  void setBpm(int bpm) {
    state = state.copyWith(bpm: bpm.clamp(minBpm, maxBpm));
    _scheduler?.changeBpm(state.bpm);
  }

  /// 4/4 强弱拍节拍声;节拍声关时静默(返回 null 即该拍不发声)。
  EngineSound? _pick(int beat) {
    if (!_clickOn) return null;
    return beat % beatsPerBar == 0 ? _strong : _weak;
  }

  void _onEngineError(Object error) {
    _scheduler = null;
    state = state.copyWith(
      running: false,
      error: '引擎出错,训练已停止:$error',
    );
  }

  void _teardown() {
    _scheduler?.stop();
    _scheduler = null;
  }
}
