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
    this.speed = 1.0,
    this.loopStart,
    this.loopEnd,
    this.error,
  });

  final FlowingStatus status;
  final ReferenceScore? score;

  /// 静态位置(暂停/就绪/曲末);播放中该值滞后,视图以时钟为准。
  final double positionSeconds;

  /// 播放中的时间轴原点引擎时刻;null = 不在播放。
  final Duration? t0;

  /// 慢放倍率(票01 三档 0.5/0.75/1.0):只缩放时间轴,排版几何不动。
  final double speed;

  /// AB 循环选段(票02,音乐秒;独立槽位)。两端齐备且 start < end 才
  /// 生效,见 [activeLoop];不满足时槽位保留展示但不挂循环。
  final double? loopStart;
  final double? loopEnd;
  final String? error;

  /// 生效中的循环窗口;null = 不循环。
  ({double start, double end})? get activeLoop {
    final a = loopStart;
    final b = loopEnd;
    if (a == null || b == null || !(b > a)) return null;
    return (start: a, end: b);
  }

  FlowingPracticeState copyWith({
    FlowingStatus? status,
    ReferenceScore? score,
    double? positionSeconds,
    Duration? t0,
    double? speed,
    double? loopStart,
    double? loopEnd,
    String? error,
    bool clearT0 = false,
    bool clearError = false,
    bool clearLoop = false,
  }) {
    return FlowingPracticeState(
      status: status ?? this.status,
      score: score ?? this.score,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      t0: clearT0 ? null : (t0 ?? this.t0),
      speed: speed ?? this.speed,
      loopStart: clearLoop ? null : (loopStart ?? this.loopStart),
      loopEnd: clearLoop ? null : (loopEnd ?? this.loopEnd),
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

  /// 当前音乐秒(唯一时间源=引擎时钟;未播放时为静态位置)。慢放:
  /// 音乐秒 = speed ×(引擎时钟 − t0),视图红线推进随之降为
  /// pixelsPerSecond × speed,排版几何不动(票01)。循环挂上时按窗口
  /// 模回跳(B 独占):raw ≥ A 即 mod 进 [A,B)——与调度器的纯音乐域
  /// 推进出自同一 t0,音画同源同刻(票02)。
  double currentSeconds() {
    final t0 = state.t0;
    final score = state.score;
    if (t0 == null || score == null) return state.positionSeconds;
    final raw =
        state.speed * (_engine.engineTime() - t0).inMicroseconds / Duration.microsecondsPerSecond;
    final loop = state.activeLoop;
    if (loop != null && raw >= loop.start) {
      final span = loop.end - loop.start;
      return loop.start + (raw - loop.start) % span;
    }
    if (raw < 0) return 0;
    if (raw > score.durationSeconds) return score.durationSeconds;
    return raw;
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
    // 循环挂上时窗外起点吸附到 A(codex 同款:position<loop.a 或 ≥
    // loop.b 都从 A 起跑);窗内起点(含暂停恢复)原地续跑。
    final loop = state.activeLoop;
    var from = state.status == FlowingStatus.finished ? 0.0 : state.positionSeconds;
    if (loop != null && (from < loop.start || from >= loop.end)) {
      from = loop.start;
    }
    final speed = state.speed;
    final t0 = _engine.engineTime() -
        Duration(
            microseconds:
                (from / speed * Duration.microsecondsPerSecond).round());
    final scheduler = _buildScheduler(score, speed);
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

  /// 速度切换(票01 三档 0.5/0.75/1.0;codex transport.setSpeed 同款)。
  /// 播放中即切:取当前音乐秒按新速度重锚(t0 = now − pos/newSpeed),
  /// 位置连续无突跳,红线只是斜率瞬时变缓;调度器重建——已响攻击经
  /// consumedUntil=now 全部越过不重放,旧在途未响预定停弃(其绝对时刻
  /// 已随速度改变),正在响的尾音不截停自然衰减(与暂停立静不同:
  /// 变速不该听得见)。
  void setSpeed(double value) {
    if (!_validSpeeds.contains(value)) {
      throw ArgumentError.value(value, 'speed', '只支持 0.5/0.75/1.0');
    }
    if (value == state.speed) return;
    if (state.status != FlowingStatus.playing || state.score == null) {
      // 静止态只换倍率:下次 play() 按新速度锚定。
      state = state.copyWith(speed: value);
      if (kDebugMode) debugPrint('UFLOW_FLOW SPEED $value (静止,待播生效)');
      return;
    }
    final position = currentSeconds();
    final now = _engine.engineTime();
    final old = _scheduler;
    final t0 = now -
        Duration(
            microseconds:
                (position / value * Duration.microsecondsPerSecond).round());
    final scheduler = _buildScheduler(state.score!, value);
    old?.stop(silenceRinging: false);
    scheduler.start(t0: t0, consumedUntil: now);
    _scheduler = scheduler;
    state = state.copyWith(speed: value, t0: t0, positionSeconds: position);
    if (kDebugMode) {
      debugPrint(
          'UFLOW_FLOW SPEED $value pos=${position.toStringAsFixed(3)} '
          'engMs=${now.inMilliseconds}');
    }
  }

  static final Set<double> _validSpeeds = {0.5, 0.75, 1.0};

  /// 设 A = 当前位(codex 选段同源;票02)。已有 B 且新 A ≥ B 时窗口
  /// 失效(槽位保留展示,不挂循环),符合「先 A 后 B」的练琴动线。
  void markLoopStart() => _applyLoop(currentSeconds(), state.loopEnd);

  /// 设 B = 当前位。
  void markLoopEnd() => _applyLoop(state.loopStart, currentSeconds());

  /// 清除循环。
  void clearLoop() => _applyLoop(null, null);

  /// 应用循环槽位(钳制到曲长)。播放中即挂:可听位连续——新窗外且
  /// ≥ B 按模回跳进窗(与红线公式一致),其余原地续;一律重锚
  /// (t0 = now − pos/speed,此后 raw == 可听位)并重建调度器
  /// (consumedUntil=now:已响不重放,被停的在途由新调度器同刻重排,
  /// 同 setSpeed 纪律)。清除/失效时从可听位继续线性推进,无跳变。
  void _applyLoop(double? a, double? b) {
    final score = state.score;
    if (score == null) return;
    final ca = a?.clamp(0.0, score.durationSeconds);
    final cb = b?.clamp(0.0, score.durationSeconds);
    final clear = ca == null && cb == null;
    if (state.status != FlowingStatus.playing || state.t0 == null) {
      state = state.copyWith(loopStart: ca, loopEnd: cb, clearLoop: clear);
      return;
    }
    var pos = currentSeconds();
    final loop = (ca != null && cb != null && cb > ca)
        ? (start: ca, end: cb)
        : null;
    if (loop != null && pos >= loop.end) {
      pos = loop.start + (pos - loop.start) % (loop.end - loop.start);
    }
    final now = _engine.engineTime();
    final old = _scheduler;
    final t0 = now -
        Duration(
            microseconds: (pos / state.speed * Duration.microsecondsPerSecond)
                .round());
    final scheduler = _buildScheduler(score, state.speed, loop: loop);
    old?.stop(silenceRinging: false);
    scheduler.start(t0: t0, consumedUntil: now);
    _scheduler = scheduler;
    state = state.copyWith(
      loopStart: ca,
      loopEnd: cb,
      clearLoop: clear,
      t0: t0,
      positionSeconds: pos,
    );
    if (kDebugMode) {
      debugPrint('UFLOW_FLOW LOOP ${loop == null ? 'off' : '${loop.start}-${loop.end}'} '
          'pos=${pos.toStringAsFixed(3)} engMs=${now.inMilliseconds}');
    }
  }

  /// [loop] 显式给定时优先(挂循环瞬间 state 还没换新值,见 _applyLoop);
  /// 缺省读当前 state。
  FlowingNoteScheduler _buildScheduler(
    ReferenceScore score,
    double speed, {
    ({double start, double end})? loop,
  }) {
    final pluck = ref.read(pluckPlayerProvider);
    final controller = this;
    final effectiveLoop = loop ?? state.activeLoop;
    return FlowingNoteScheduler(
      engine: _engine,
      attacks: _attacks,
      duration: Duration(milliseconds: (score.durationSeconds * 1000).round()),
      speed: speed,
      loopStart: effectiveLoop == null
          ? null
          : Duration(milliseconds: (effectiveLoop.start * 1000).round()),
      loopEnd: effectiveLoop == null
          ? null
          : Duration(milliseconds: (effectiveLoop.end * 1000).round()),
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
        'UFLOW_FLOW t speed=${state.speed} music=${musicSec.toStringAsFixed(3)} '
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
