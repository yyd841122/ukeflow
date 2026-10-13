import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/beat_scheduling.dart';
import '../../core/audio/beat_scheduler.dart';
import '../../core/audio/providers.dart';
import '../../core/audio/tick_synth.dart';
import '../../core/model/builtin_strum_patterns.dart';
import '../../core/model/strum_chart.dart';
import '../../core/model/strum_pattern.dart';
import '../../core/practice/play_timeline.dart';

/// 跟练页状态（GLOSSARY「跟练」）。
class PlayPracticeState {
  const PlayPracticeState({
    required this.bpm,
    required this.pattern,
    required this.engineReady,
    required this.running,
    this.error,
  });

  factory PlayPracticeState.initial() => PlayPracticeState(
    bpm: PlayPracticeController.defaultBpm,
    pattern: builtinStrumPatterns.first,
    engineReady: false,
    running: false,
  );

  /// 当前 BPM（进谱默认取谱面 tempo,页内可调;运行中固定——控制与变速在工单 10）。
  final int bpm;

  /// 节奏型（时间轴编译参数;同一首谱可换型练,运行中固定）。
  final StrumPattern pattern;
  final bool engineReady;
  final bool running;

  /// 引擎错误文案(初始化失败/运行中引擎异常);null = 正常。
  final String? error;

  PlayPracticeState copyWith({
    int? bpm,
    StrumPattern? pattern,
    bool? engineReady,
    bool? running,
    Object? error = _sentinel,
  }) => PlayPracticeState(
    bpm: bpm ?? this.bpm,
    pattern: pattern ?? this.pattern,
    engineReady: engineReady ?? this.engineReady,
    running: running ?? this.running,
    error: identical(error, _sentinel) ? this.error : error as String?,
  );

  static const _sentinel = Object();
}

final playPracticeProvider =
    NotifierProvider<PlayPracticeController, PlayPracticeState>(
      PlayPracticeController.new,
    );

/// 跟练控制器:内置弹唱谱 → 按当前 BPM+节奏型编译时间轴 → 节拍声有界调度。
///
/// 音画同源（ADR-0005）在此接线:节拍声走 BeatScheduler→playClocked 管线,
/// 锚点 t0/拍周期与时间轴同源同刻;视觉不进调度——UI 轮询经
/// practiceStateAt 纯函数按引擎时刻算出（跟练页负责轮询）。v1 固定速度
/// 从头到尾:BPM/节奏型只在进谱时与空闲时改,运行中重编译归工单 10。
class PlayPracticeController extends Notifier<PlayPracticeState> {
  static const minBpm = 40;
  static const maxBpm = 208;

  /// 无谱面 tempo 时的缺省速度（与节奏型训练器同源,慢练起步）。
  static const defaultBpm = 80;

  EngineSound? _strong;
  EngineSound? _weak;
  BeatScheduler? _scheduler;
  PlayTimeline? _timeline;
  Future<void>? _warming;

  /// 运行中的动作事件时间轴;未运行 null。
  PlayTimeline? get timeline => _timeline;

  /// 视觉层锚点:时间轴起点与拍周期;未运行 null。
  ({Duration t0, double periodMs})? get visualAnchor => _scheduler?.anchor;

  @override
  PlayPracticeState build() {
    ref.onDispose(_teardown);
    return PlayPracticeState.initial();
  }

  /// 引擎预热 + 注入强弱拍音源;失败进 error 状态,页面上可见。
  /// 并发调用共享同一次在途初始化(快速重进页不重复注入音源)。
  Future<void> warmup() async {
    if (state.engineReady) return;
    return _warming ??= _doWarmup().whenComplete(() => _warming = null);
  }

  Future<void> _doWarmup() async {
    try {
      final engine = ref.read(audioEngineProvider);
      await engine.ensureInitialized();
      if (!ref.mounted) return; // 容器已随应用退出:状态无可落盘。
      final strong = await engine.loadMem('tick_strong', TickSynth.strong());
      final weak = await engine.loadMem('tick_weak', TickSynth.weak());
      if (!ref.mounted) return;
      _strong = strong;
      _weak = weak;
      // error: null——上次初始化失败的文案不残留到成功之后。
      state = state.copyWith(engineReady: true, error: null);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(error: '引擎初始化失败:$error');
    }
  }

  /// 进谱定参:取谱面 tempo 为当前 BPM（钳制 40–208）。只应在进页时调;
  /// 运行中是空操作（页内重启不清已调好的速度）。
  void prepareFor(StrumChart chart) {
    if (state.running) return;
    final tempo = chart.tempo ?? defaultBpm;
    state = state.copyWith(bpm: tempo.clamp(minBpm, maxBpm));
  }

  /// 设 BPM(钳制 40–208)。仅空闲生效:运行中固定速度(工单 10 接管)。
  void setBpm(int bpm) {
    if (state.running) return;
    state = state.copyWith(bpm: bpm.clamp(minBpm, maxBpm));
  }

  /// 换节奏型。仅空闲生效:节奏型是编译参数,运行中换型=重编译(工单 10)。
  void setPattern(StrumPattern pattern) {
    if (state.running) return;
    state = state.copyWith(pattern: pattern);
  }

  /// 开始跟练:编译时间轴,节拍声与时间轴同源起跑（[BeatScheduler.start]
  /// 传 totalBeats,曲末无幻拍声）。未就绪或已在跑则拒绝。
  void start({required StrumChart chart}) {
    if (!state.engineReady || state.running) return;
    final timeline = compileTimeline(
      chart: chart,
      pattern: state.pattern,
      bpm: state.bpm.toDouble(),
    );
    final scheduler = BeatScheduler(
      engine: ref.read(audioEngineProvider),
      pickSound: _pick,
      onError: _onEngineError,
    );
    // 先挂字段再起跑:首过即抛时 onError→stop 会当场清掉它们(下方据此识别)。
    _timeline = timeline;
    _scheduler = scheduler;
    scheduler.start(bpm: state.bpm, totalBeats: timeline.totalBeats);
    if (_scheduler != scheduler) return; // 首过即抛:错误状态已落地,不宣布运行。
    state = state.copyWith(running: true, error: null);
  }

  /// 停止:取消轮询调度、停掉尚未发声的预定、时间轴清空。
  void stop() {
    // 引擎侧停止不依赖 ref:容器已销毁(应用退出竞态)也照停。
    _scheduler?.stop();
    _scheduler = null;
    _timeline = null;
    if (!ref.mounted) return; // 容器已随应用退出:状态无可落盘。
    if (state.running) {
      state = state.copyWith(running: false);
    }
  }

  /// 4/4 强弱拍节拍声（与节拍器/训练器同一管线;参考音开关在工单 10）。
  EngineSound? _pick(int beat) => beat % beatsPerBar == 0 ? _strong : _weak;

  void _onEngineError(Object error) {
    stop();
    state = state.copyWith(running: false, error: '引擎出错,跟练已停止:$error');
  }

  void _teardown() {
    _scheduler?.stop();
    _scheduler = null;
    _timeline = null;
  }
}
