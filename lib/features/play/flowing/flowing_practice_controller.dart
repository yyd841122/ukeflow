import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/audio_engine.dart';
import '../../../core/audio/providers.dart';
import '../../../core/audio/tick_sounds.dart';
import '../../../core/score/flowing_timeline.dart';
import '../../../core/score/reference_score.dart';
import 'flowing_note_scheduler.dart'
    show FlowingAttack, FlowingBeat, FlowingNoteScheduler;

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

  /// 预备数拍中(票03:四下计数音,曲谱位置定住不推进;数完自动起播)。
  counting,

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
    this.countInEnabled = true,
    this.countPerLoop = false,
    this.countStart,
    this.countBeatDur,
    this.demoEnabled = true,
    this.demoVolume = 1.0,
    this.metroEnabled = false,
    this.metroVolume = 0.5,
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

  /// 数四下(票03):起播/换段前预备数拍(codex 同款两开关;暂停续播
  /// 不重数)。
  final bool countInEnabled;

  /// 循环每轮也数四下(仅挂循环时生效)。
  final bool countPerLoop;

  /// 预备数拍的首拍引擎时刻(仅 counting 状态非空;视图倒计数用)。
  final Duration? countStart;

  /// 数拍节拍时长(音乐域 60/tempo;视图按 speed 缩放显示倒计数)。
  final Duration? countBeatDur;

  /// 示范琴声开关与音量(票04,codex 同款默认:开 / 1.0)。静音只停
  /// 「出声」,时间线照推——红线与推进不受影响。
  final bool demoEnabled;
  final double demoVolume;

  /// 节拍器开关与音量(票04 新增节拍轨,codex 同款默认:关 / 0.5)。
  /// 数四下 tick 音量同骑此滑条(开关仍归数拍开关管)。
  final bool metroEnabled;
  final double metroVolume;
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
    bool? countInEnabled,
    bool? countPerLoop,
    Duration? countStart,
    Duration? countBeatDur,
    bool? demoEnabled,
    double? demoVolume,
    bool? metroEnabled,
    double? metroVolume,
    String? error,
    bool clearT0 = false,
    bool clearError = false,
    bool clearLoop = false,
    bool clearCount = false,
  }) {
    return FlowingPracticeState(
      status: status ?? this.status,
      score: score ?? this.score,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      t0: clearT0 ? null : (t0 ?? this.t0),
      speed: speed ?? this.speed,
      loopStart: clearLoop ? null : (loopStart ?? this.loopStart),
      loopEnd: clearLoop ? null : (loopEnd ?? this.loopEnd),
      countInEnabled: countInEnabled ?? this.countInEnabled,
      countPerLoop: countPerLoop ?? this.countPerLoop,
      countStart: clearCount ? null : (countStart ?? this.countStart),
      countBeatDur: clearCount ? null : (countBeatDur ?? this.countBeatDur),
      demoEnabled: demoEnabled ?? this.demoEnabled,
      demoVolume: demoVolume ?? this.demoVolume,
      metroEnabled: metroEnabled ?? this.metroEnabled,
      metroVolume: metroVolume ?? this.metroVolume,
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

  /// 数拍 tick 音源(独立预备音色,装载失败降级为不数直接播)。
  EngineSound? _countSound;

  /// 节拍器音源(票04:重拍 strong/弱拍 weak;与数拍同一次装载,
  /// 失败一并降级为无声——开关与音量仍在,只是不响)。
  EngineSound? _metroStrong;
  EngineSound? _metroWeak;

  /// 节拍器拍点表(票04,音乐域升序;装载时从小节表一次算清)。
  List<FlowingBeat> _metroBeats = const [];

  /// 预备数拍的引擎钟轮询(票03:Timer 只当触发器,数完时刻读引擎钟,
  /// 与调度器同纪律;测试可手动推进引擎钟立即翻状态)。
  Timer? _countPoll;
  Duration? _countEnd;
  double? _countFrom;

  /// 暂停续播不重数(codex 同款:暂停→播放直续;seek/曲末重开重数)。
  bool _resumeWithoutCount = false;

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
      _cancelCount();
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
      // tick 音源(票03 数拍 + 票04 节拍器 strong/weak 同一揽子装载;
      // 失败不阻断装载——降级为不数、节拍无声,开关与音量仍在)。
      _metroBeats = buildBeats(score);
      try {
        final ticks =
            await TickSounds.load(_engine, strong: true, weak: true, count: true);
        _metroStrong = ticks.strong;
        _metroWeak = ticks.weak;
        _countSound = ticks.count;
      } catch (_) {
        _metroStrong = null;
        _metroWeak = null;
        _countSound = null;
      }
      if (_disposed) return;
      state = FlowingPracticeState(
        status: FlowingStatus.ready,
        score: score,
        positionSeconds: 0,
        countInEnabled: state.countInEnabled,
        countPerLoop: state.countPerLoop,
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

  /// 小节表 → 节拍器拍点(票04):每小节按其拍速把时长均分为四分音符
  /// 拍(与转换器 quarterBeats×60/tempo 同式回推),小节头为重拍。纯
  /// 音乐域时刻——慢放/循环由调度器统一变换,与示范声同源。
  @visibleForTesting
  static List<FlowingBeat> buildBeats(ReferenceScore score) {
    final beats = <FlowingBeat>[];
    for (final measure in score.measures) {
      final startMs = (measure.startSeconds * 1000).round();
      final beatMs = 60000 / measure.tempo;
      final count =
          (measure.durationSeconds * measure.tempo / 60).round();
      for (var k = 0; k < count; k++) {
        beats.add((
          time: Duration(milliseconds: startMs + (beatMs * k).round()),
          accent: k == 0,
        ));
      }
    }
    return beats;
  }

  /// 当前音乐秒(唯一时间源=引擎时钟;未播放时为静态位置)。慢放:
  /// 音乐秒 = speed ×(引擎时钟 − t0),视图红线推进随之降为
  /// pixelsPerSecond × speed,排版几何不动(票01)。循环挂上时按窗口
  /// 模回跳(B 独占):raw ≥ A 即 mod 进「窗长 + 数拍 gap」的周期——
  /// gap 段(每轮数四下)红线定在 A,与调度器轮次推进同源同刻
  /// (票02/03)。
  double currentSeconds() {
    final t0 = state.t0;
    final score = state.score;
    if (t0 == null || score == null) return state.positionSeconds;
    final raw =
        state.speed * (_engine.engineTime() - t0).inMicroseconds / Duration.microsecondsPerSecond;
    final loop = state.activeLoop;
    if (loop != null && raw >= loop.start) {
      final span = loop.end - loop.start;
      final gap = _loopGapSeconds(loop);
      final r = (raw - loop.start) % (span + gap);
      // r ∈ [0, span) 为正曲段;r ∈ [span, span+gap) 为轮间数拍段
      //(占真实时刻不占曲谱时间),红线定在 A。
      return r < span ? loop.start + r : loop.start;
    }
    if (raw < 0) return 0;
    if (raw > score.durationSeconds) return score.durationSeconds;
    return raw;
  }

  /// 循环轮间数拍 gap(音乐秒;与调度器 _gapMusic 同源:tempo 取 A 处
  /// 小节拍速)。未挂循环或未开每轮数拍 = 0。
  double _loopGapSeconds(({double start, double end}) loop) {
    if (!state.countPerLoop) return 0;
    final beat = _beatDurAt(loop.start);
    return beat.inMicroseconds * 4 / Duration.microsecondsPerSecond;
  }

  /// 音乐时刻处的节拍时长(该小节拍速;60/tempo,音乐域)。
  Duration _beatDurAt(double musicTime) {
    final score = state.score;
    var tempo = score?.startingTempo ?? 80;
    if (score != null) {
      final index = measureIndexAt(score, musicTime);
      if (index >= 0 && index < score.measures.length) {
        tempo = score.measures[index].tempo;
      }
    }
    return Duration(microseconds: (60000000 / tempo).round());
  }

  /// 播放(曲末再按 = 从头;codex 同款)。已在播放时无害幂等。
  /// 数四下(票03):起播/换段(seek 后、曲末重开)先四下预备拍
  /// (独立预备钟:占真实时刻不占曲谱时间,红线定在起点),数完自动
  /// 起播;暂停续播不重数(codex 同款)。可开关。
  Future<void> play() async {
    final score = state.score;
    if (score == null ||
        state.status == FlowingStatus.playing ||
        state.status == FlowingStatus.counting ||
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
    final loop = state.activeLoop;
    var from = state.status == FlowingStatus.finished ? 0.0 : state.positionSeconds;
    if (loop != null && (from < loop.start || from >= loop.end)) {
      from = loop.start;
    }
    final resumeWithoutCount = _resumeWithoutCount;
    _resumeWithoutCount = false;
    if (state.countInEnabled && !resumeWithoutCount && _countSound != null) {
      _beginCount(from);
      return;
    }
    _startPlaybackAt(from);
  }

  /// 预备数拍(票03):4 记 tick 在引擎时刻 now+lead、+1 拍、+2 拍、
  /// +3 拍(playScheduled 绝对时刻,慢放同步变慢);曲谱时钟不动
  /// (t0 不设,positionSeconds 冻结在起点)。数完时刻由引擎钟轮询判定
  /// (Timer 只当触发器,ADR-0005),到点自动起播。
  void _beginCount(double from) {
    final speed = state.speed;
    final beat = _beatDurAt(from);
    final now = _engine.engineTime();
    final lead = const Duration(milliseconds: 120);
    final countStart = now + lead;
    _countVoices.clear();
    final sound = _countSound;
    for (var j = 0; j < 4 && sound != null; j++) {
      final at =
          countStart + Duration(microseconds: (beat.inMicroseconds * j / speed).round());
      try {
        _countVoices.add(
          _engine.playScheduled(sound, at, volume: state.metroVolume),
        );
      } catch (_) {}
    }
    _countEnd = countStart +
        Duration(microseconds: (beat.inMicroseconds * 4 / speed).round());
    _countFrom = from;
    _countPoll?.cancel();
    _countPoll = Timer.periodic(const Duration(milliseconds: 40), (_) {
      final end = _countEnd;
      if (end == null || _disposed) return;
      try {
        if (_engine.engineTime() < end) return;
      } catch (_) {
        return;
      }
      _finishCount();
    });
    state = state.copyWith(
      status: FlowingStatus.counting,
      positionSeconds: from,
      countStart: countStart,
      countBeatDur: beat,
      clearT0: true,
      clearError: true,
    );
    if (kDebugMode) {
      debugPrint('UFLOW_FLOW COUNT start=${countStart.inMilliseconds} '
          'beat=${beat.inMilliseconds} from=${from.toStringAsFixed(3)}');
    }
  }

  final _countVoices = <EngineVoice>[];

  /// 数完(或中止)预备拍:停轮询与在途 tick。
  void _cancelCount({bool keepVoices = false}) {
    _countPoll?.cancel();
    _countPoll = null;
    _countEnd = null;
    _countFrom = null;
    if (!keepVoices) {
      for (final voice in _countVoices) {
        try {
          _engine.stop(voice);
        } catch (_) {}
      }
    }
    _countVoices.clear();
  }

  /// 数完自动起播(引擎钟到点;轮询触发)。
  void _finishCount() {
    final from = _countFrom;
    _cancelCount(keepVoices: true); // 最后一拍自然衰减,不打断。
    if (from == null || _disposed) return;
    _startPlaybackAt(from);
  }

  /// 起播公共路径:锚 t0、建调度器、翻 playing。
  void _startPlaybackAt(double from) {
    final score = state.score;
    if (score == null) return;
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
      clearCount: true,
      clearError: true,
    );
  }

  /// 暂停:立静(含尾音)、冻结位置、等待再拍。数拍中暂停 = 中止预备,
  /// 续播不重数(codex 同款)。
  void pause() {
    if (state.status == FlowingStatus.counting) {
      _cancelCount();
      _resumeWithoutCount = true;
      state = state.copyWith(
        status: FlowingStatus.paused,
        clearT0: true,
        clearCount: true,
      );
      return;
    }
    if (state.status != FlowingStatus.playing) return;
    final position = currentSeconds();
    _disposeScheduler();
    _resumeWithoutCount = true;
    state = state.copyWith(
      status:
          position >= (state.score?.durationSeconds ?? 0) ? FlowingStatus.finished : FlowingStatus.paused,
      positionSeconds: position,
      clearT0: true,
    );
  }

  /// 跳转:停声清旧、更新位置、**保持暂停**(codex 方法)。换段重数
  /// (codex 同款:位置变了就重新预备)。数拍中跳转 = 中止预备。
  void seek(double seconds) {
    final score = state.score;
    if (score == null) return;
    var position = seconds;
    if (position < 0) position = 0;
    if (position > score.durationSeconds) position = score.durationSeconds;
    if (state.status == FlowingStatus.counting) _cancelCount();
    _disposeScheduler();
    _resumeWithoutCount = false;
    state = state.copyWith(
      status:
          position >= (state.score?.durationSeconds ?? 0) ? FlowingStatus.finished : FlowingStatus.paused,
      positionSeconds: position,
      clearT0: true,
      clearCount: true,
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

  /// 数拍开关(票03 两开关,codex 同款:起播数 / 循环每轮数)。
  /// countPerLoop 播放中挂循环即切——gap 进出必须调度器与视图模公式
  /// 同步换挡,重锚+重建调度器(同 _applyLoop 纪律,可听位连续);
  /// countInEnabled 只影响下次起播,状态直改。
  void setCountOptions({bool? countInEnabled, bool? countPerLoop}) {
    final perLoopChanged =
        countPerLoop != null && countPerLoop != state.countPerLoop;
    state = state.copyWith(
      countInEnabled: countInEnabled,
      countPerLoop: countPerLoop,
    );
    if (!perLoopChanged ||
        state.status != FlowingStatus.playing ||
        state.t0 == null ||
        state.activeLoop == null) {
      return;
    }
    final position = currentSeconds();
    final now = _engine.engineTime();
    final old = _scheduler;
    final t0 = now -
        Duration(
            microseconds:
                (position / state.speed * Duration.microsecondsPerSecond)
                    .round());
    final scheduler = _buildScheduler(state.score!, state.speed);
    old?.stop(silenceRinging: false);
    scheduler.start(t0: t0, consumedUntil: now);
    _scheduler = scheduler;
    state = state.copyWith(t0: t0, positionSeconds: position);
  }

  /// 声音分路(票04):示范琴声/节拍器各自开关+音量,codex 同款默认
  /// (琴声开 1.0、节拍关 0.5)。静音任一路只停「出声」:在途调度器
  /// 可变字段直改 + 停该路在途未响预定(≤400ms 已排声立静),不重建
  /// 调度器不重锚——游标照走、时钟照推,红线与推进不受影响(测试
  /// 锁定);静止态只换状态,下次起播生效。音量改动只影响之后的预定
  /// (在途已排声保持旧值,≤400ms 追平;循环数拍 tick 在回跳点一次
  /// 排 4 记,本轮回跳前的改动下一轮生效)。数拍 tick 音量同骑节拍
  /// 音量滑条(codex 同款),但开关归数拍开关管。
  void setAudioOptions({
    bool? demoEnabled,
    double? demoVolume,
    bool? metroEnabled,
    double? metroVolume,
  }) {
    state = state.copyWith(
      demoEnabled: demoEnabled,
      demoVolume: demoVolume?.clamp(0.0, 1.0),
      metroEnabled: metroEnabled,
      metroVolume: metroVolume?.clamp(0.0, 1.0),
    );
    if (kDebugMode) {
      debugPrint('UFLOW_FLOW AUDIO demo=${state.demoEnabled}/'
          '${state.demoVolume.toStringAsFixed(2)} '
          'metro=${state.metroEnabled}/${state.metroVolume.toStringAsFixed(2)}');
    }
    final scheduler = _scheduler;
    if (scheduler == null) return; // 静止态只换状态,下次起播生效。
    scheduler
      ..demoEnabled = state.demoEnabled
      ..demoVolume = state.demoVolume
      ..metroEnabled = state.metroEnabled
      ..metroVolume = state.metroVolume;
    if (demoEnabled == false) scheduler.silenceDemoPending();
    if (metroEnabled == false) scheduler.silenceMetroPending();
  }

  /// 预备数拍当前拍号(1..4);不在数拍段返回 null(状态行倒计数用)。
  /// 起播预备由 countStart/拍长推;循环轮间数拍由模公式 gap 段推。
  int? countBeatNow() {
    if (state.status == FlowingStatus.counting) {
      final start = state.countStart;
      final beat = state.countBeatDur;
      if (start == null || beat == null) return null;
      int elapsedUs;
      try {
        elapsedUs = (_engine.engineTime() - start).inMicroseconds;
      } catch (_) {
        return null;
      }
      final beatUs = (beat.inMicroseconds / state.speed).round();
      final n = 1 + (elapsedUs <= 0 ? 0 : elapsedUs ~/ beatUs);
      return n.clamp(1, 4);
    }
    if (state.status == FlowingStatus.playing && state.t0 != null) {
      final loop = state.activeLoop;
      if (loop == null || !state.countPerLoop) return null;
      final span = loop.end - loop.start;
      final gap = _loopGapSeconds(loop);
      if (gap <= 0) return null;
      final raw = state.speed *
          (_engine.engineTime() - state.t0!).inMicroseconds /
          Duration.microsecondsPerSecond;
      if (raw < loop.start) return null;
      final r = (raw - loop.start) % (span + gap);
      if (r < span) return null;
      final beatSec = _beatDurAt(loop.start).inMicroseconds / 1e6;
      final n = 1 + ((r - span) / beatSec).floor();
      return n.clamp(1, 4);
    }
    return null;
  }

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
    final loopCount =
        state.countPerLoop && effectiveLoop != null;
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
      countPerLoop: loopCount,
      beatDur: loopCount ? _beatDurAt(effectiveLoop.start) : null,
      pickCountSound: () => _countSound,
      beats: _metroBeats,
      pickMetroSound: (accent) => accent ? _metroStrong : _metroWeak,
      demoEnabled: state.demoEnabled,
      demoVolume: state.demoVolume,
      metroEnabled: state.metroEnabled,
      metroVolume: state.metroVolume,
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
