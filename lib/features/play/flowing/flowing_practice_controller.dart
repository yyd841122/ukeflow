import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/audio_engine.dart';
import '../../../core/audio/providers.dart';
import '../../../core/score/flowing_timeline.dart';
import '../../../core/score/reference_score.dart';
import 'flowing_note_scheduler.dart';

/// 可覆盖的曲谱装载缝(测试注入,免 rootBundle)。
final flowingScoreLoaderProvider = Provider<Future<ReferenceScore> Function()>(
  (ref) => loadReferenceScore,
);

/// 跟练会话状态(GLOSSARY「流水谱跟练」,一手数据 MVP)。
enum FlowingStatus {
  /// 装载中(读资产、转换、预注入音源)。
  loading,

  /// 就绪,等待播放。
  ready,

  /// 播放中(视觉当前秒由视图按 t0+引擎时钟逐帧读,见 [t0])。
  playing,

  /// 暂停(含拖动后;codex 方法:拖动与松手后保持暂停)。
  paused,

  /// 整首到尾(终点保留,不自动回开头)。
  finished,

  /// 引擎/数据故障(错误见 [error])。
  error,
}

class FlowingPracticeState {
  const FlowingPracticeState({
    this.status = FlowingStatus.loading,
    this.score,
    this.positionSeconds = 0,
    this.t0,
    this.error,
  });

  final FlowingStatus status;
  final ReferenceScore? score;

  /// 静态位置(暂停/就绪/曲末);播放中该值滞后,视图以时钟为准。
  final double positionSeconds;

  /// 播放中的时间轴原点引擎时刻;null = 不在播放。
  final Duration? t0;
  final String? error;

  FlowingPracticeState copyWith({
    FlowingStatus? status,
    ReferenceScore? score,
    double? positionSeconds,
    Duration? t0,
    String? error,
    bool clearT0 = false,
    bool clearError = false,
  }) {
    return FlowingPracticeState(
      status: status ?? this.status,
      score: score ?? this.score,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      t0: clearT0 ? null : (t0 ?? this.t0),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 流水谱跟练控制器:《天空之城》一手数据 MVP。
///
/// 职责收口:装载与预注入、play/pause/seek 的会话状态机、示范声调度器
/// 生命周期。时间纪律(ADR-0005):控制器只持有锚点 t0,当前音乐秒 =
/// (引擎时钟 − t0),由视图逐帧读取;调度器只预定声音,不驱动画面。
/// codex 方法对齐:拖动即停声并保持暂停;曲末终点保留;暂停立静
/// (连尾音,KS 拨弦衰减由停声截断,与 alphaTab pause 语义一致)。
class FlowingPracticeController extends Notifier<FlowingPracticeState> {
  FlowingNoteScheduler? _scheduler;
  List<FlowingAttack> _attacks = const [];
  bool _disposed = false;

  /// 真机诊断遥测(仅 debug 构建编译进来;ADR-0005 不破:墙钟只进日志,
  /// 不进任何同步逻辑——codex SCORE_TELEMETRY 同款办法,量「时钟 vs
  /// 真实时间推进比例」「调度进度」)。
  Timer? _telemetryTimer;
  final Stopwatch _telemetryWall = Stopwatch();
  int _telemetryLastEngMs = 0;
  int _telemetryLastWallMs = 0;

  @override
  FlowingPracticeState build() {
    // 页面关闭(监听清空 → provider 销毁)即停声清场。
    ref.onDispose(() {
      _disposed = true;
      _disposeScheduler();
    });
    Future(() => _load());
    return const FlowingPracticeState();
  }

  AudioEngine get _engine => ref.read(audioEngineProvider);

  Future<void> _load() async {
    try {
      final score = await ref.read(flowingScoreLoaderProvider)();
      _attacks = buildAttacks(score);
      // 全曲音源一次注入(按「音高×时长」缓存; distinct 音高很少,
      // 注入期免调度 await)。
      final pluck = ref.read(pluckPlayerProvider);
      await pluck.preloadSounds({
        for (final a in _attacks) ...a.freqs,
      });
      if (_disposed) return;
      state = FlowingPracticeState(
        status: FlowingStatus.ready,
        score: score,
        positionSeconds: 0,
      );
    } catch (error) {
      if (_disposed) return;
      state = FlowingPracticeState(
        status: FlowingStatus.error,
        error: '曲谱或琴声装载失败：$error',
      );
    }
  }

  /// 事件表 → 攻击序列:休止无攻击;延音尾音剔除(起点音仍在衰减,
  /// 重拨即错成两声);和弦同刻一组。
  @visibleForTesting
  static List<FlowingAttack> buildAttacks(ReferenceScore score) {
    final attacks = <FlowingAttack>[];
    for (final event in score.events) {
      final freqs = [
        for (final note in event.notes)
          if (!note.isTieDestination) midiToFrequency(note.midi),
      ];
      if (freqs.isEmpty) continue;
      attacks.add((
        time: Duration(milliseconds: (event.startSeconds * 1000).round()),
        freqs: freqs,
      ));
    }
    return attacks;
  }

  /// 当前音乐秒(唯一时间源=引擎时钟;未播放时为静态位置)。
  double currentSeconds() {
    final t0 = state.t0;
    final score = state.score;
    if (t0 == null || score == null) return state.positionSeconds;
    final seconds =
        (_engine.engineTime() - t0).inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds < 0) return 0;
    if (seconds > score.durationSeconds) return score.durationSeconds;
    return seconds;
  }

  /// 播放(曲末再按 = 从头;codex 同款)。已在播放时无害幂等。
  Future<void> play() async {
    final score = state.score;
    if (score == null ||
        state.status == FlowingStatus.playing ||
        state.status == FlowingStatus.loading ||
        state.status == FlowingStatus.error) {
      return;
    }
    try {
      await _engine.ensureInitialized();
    } catch (error) {
      state = state.copyWith(status: FlowingStatus.error, error: '琴声没有准备好：$error');
      return;
    }
    final from = state.status == FlowingStatus.finished ? 0.0 : state.positionSeconds;
    final t0 = _engine.engineTime() -
        Duration(milliseconds: (from * 1000).round());
    final scheduler = _buildScheduler(score);
    scheduler.start(t0: t0);
    _scheduler = scheduler;
    _startTelemetry();
    state = state.copyWith(
      status: FlowingStatus.playing,
      t0: t0,
      positionSeconds: from,
      clearError: true,
    );
  }

  /// 暂停:立静(含尾音)、冻结位置、等待再播。
  void pause() {
    if (state.status != FlowingStatus.playing) return;
    final position = currentSeconds();
    _disposeScheduler();
    state = state.copyWith(
      status:
          position >= (state.score?.durationSeconds ?? 0) ? FlowingStatus.finished : FlowingStatus.paused,
      positionSeconds: position,
      clearT0: true,
    );
  }

  /// 跳转:停声清旧、更新位置、**保持暂停**(codex 方法)。
  void seek(double seconds) {
    final score = state.score;
    if (score == null) return;
    var position = seconds;
    if (position < 0) position = 0;
    if (position > score.durationSeconds) position = score.durationSeconds;
    _disposeScheduler();
    state = state.copyWith(
      status: position >= score.durationSeconds ? FlowingStatus.finished : FlowingStatus.paused,
      positionSeconds: position,
      clearT0: true,
      clearError: true,
    );
  }

  FlowingNoteScheduler _buildScheduler(ReferenceScore score) {
    final pluck = ref.read(pluckPlayerProvider);
    final controller = this;
    return FlowingNoteScheduler(
      engine: _engine,
      attacks: _attacks,
      duration: Duration(milliseconds: (score.durationSeconds * 1000).round()),
      pickSound: (freqs) => [for (final f in freqs) pluck.loadedSound(f)],
      onFinished: () {
        if (_disposed) return;
        controller.state = controller.state.copyWith(
          status: FlowingStatus.finished,
          positionSeconds: score.durationSeconds,
          clearT0: true,
        );
      },
      onError: (error) {
        if (_disposed) return;
        controller.state = controller.state.copyWith(
          status: FlowingStatus.error,
          error: '琴声出错了：$error',
          clearT0: true,
        );
      },
    );
  }

  void _disposeScheduler() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _telemetryWall.stop();
    _scheduler?.stop(silenceRinging: true);
    _scheduler = null;
  }

  void _startTelemetry() {
    if (!kDebugMode) return;
    _telemetryWall
      ..reset()
      ..start();
    _telemetryLastEngMs = 0;
    _telemetryLastWallMs = 0;
    debugPrint('UFLOW_FLOW PLAY engMs=${_engine.engineTime().inMilliseconds}');
    _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final scheduler = _scheduler;
      final t0 = state.t0;
      if (scheduler == null || t0 == null) return;
      final engMs = _engine.engineTime().inMilliseconds;
      final wallMs = _telemetryWall.elapsedMilliseconds;
      final dEng = engMs - _telemetryLastEngMs;
      final dWall = wallMs - _telemetryLastWallMs;
      _telemetryLastEngMs = engMs;
      _telemetryLastWallMs = wallMs;
      final musicSec = currentSeconds();
      debugPrint(
        'UFLOW_FLOW t music=${musicSec.toStringAsFixed(3)} '
        'engMs=$engMs wallMs=$wallMs pace=${(dWall == 0 ? 0 : dEng / dWall).toStringAsFixed(3)} '
        'consumed=${scheduler.consumedCount}/${scheduler.total} '
        'pending=${scheduler.pendingCount}',
      );
    });
  }
}

/// 流水谱跟练提供方(Riverpod 3 全量默认可销毁:页面关闭即停,
/// ref.onDispose → 调度器停声清场)。
final flowingPracticeProvider =
    NotifierProvider<FlowingPracticeController, FlowingPracticeState>(
  FlowingPracticeController.new,
);
