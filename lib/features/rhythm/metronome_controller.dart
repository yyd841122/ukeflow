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
  /// 每次异步返回后查 [ref.mounted]:容器已释放(应用退出竞态)时状态
  /// 无可落盘,不得再写(审计 2026-10-16 #43);成功时清旧错误——
  /// 瞬态失败后重开不残留失败文案(#44)。
  Future<void> warmup() async {
    if (state.engineReady) {
      // 运行时错误后的重试(引擎仍就绪):清陈错即恢复可用,真正重跑
      // 走 start;重跑再败会再落错误态。
      if (state.error != null) state = state.copyWith(error: null);
      return;
    }
    try {
      final engine = ref.read(audioEngineProvider);
      await engine.ensureInitialized();
      if (!ref.mounted) return;
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
    // 先注册再起跑:首播(即时首过)失败时 onError 已清引用与状态,
    // 下方据此识别——不得再以 running=true / error=null 覆盖失败
    // (审计 2026-10-16 #45)。
    _scheduler = scheduler;
    scheduler.start(periodMs: 60000 / state.bpm);
    if (_scheduler != scheduler) return; // 首播失败:错误已落地,不宣布运行。
    state = state.copyWith(running: true, error: null);
    refreshScheduled();
  }

  void stop() {
    // 引擎侧停止不依赖 ref:容器已销毁(应用退出竞态)也照停。
    _scheduler?.stop();
    _scheduler = null;
    if (!ref.mounted) return; // 容器已销毁:状态无可落盘(与训练器同纪律)。
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
