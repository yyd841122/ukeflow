import 'dart:async';

import '../../../core/audio/audio_engine.dart';

/// 一次同时拨响:相对时间轴原点的时刻 + 该刻要拨的全部音高(Hz)。
typedef FlowingAttack = ({Duration time, List<double> freqs});

/// 一条在途预定:voice 与其引擎时刻(过期清理与停机善后用)。
typedef _PendingPlay = ({EngineVoice voice, Duration time});

/// 流水示范声调度器:把练习时间表的节拍事件接到引擎 playScheduled——
/// 一事件一组同刻拨弦,与画面变色出自同一份时间表、同一个曲头锚
/// (ADR-0005「音画同源」:示范声与变色同刻是结构保证)。
///
/// 调度纪律与 core/audio `BeatScheduler`、tab 跟练 `TabNoteScheduler`
/// 完全同型(40ms 轮询 + 400ms 提前量 + 40ms 迟到容差,spike B 真机
/// 验证参数;Timer 只当轮询触发器,一切时刻读引擎时钟)。延音尾音不重
/// 拨(attack 预处理已剔除),事件即声,一事件一组预定。
class FlowingNoteScheduler {
  FlowingNoteScheduler({
    required this.engine,
    required this.pickSound,
    required this.attacks,
    this.duration,
    this.speed = 1.0,
    this.onFinished,
    this.onError,
    this.pollInterval = const Duration(milliseconds: 40),
  });

  final AudioEngine engine;

  /// 一组音高 → 已注入音源列表(同步查取,免 await;某音缺位则该音
  /// 静默越过,其余照响——降级只降音,不丢拍)。
  final List<EngineSound?> Function(List<double> freqs) pickSound;

  /// 拨弦攻击序列(按时刻升序;由控制器从练习时间表预处理得出:
  /// 休止无攻击、延音尾音剔除、和弦并发一组)。
  final List<FlowingAttack> attacks;

  /// 曲末时刻(相对时间轴原点的**音乐秒**);到达后触发一次 [onFinished]。
  final Duration? duration;

  /// 慢放倍率(票01 三档 0.5/0.75/1.0):只缩放时刻轴——音乐时刻 m 的
  /// 攻击在引擎时刻 t0 + m/speed 响;KS 音色基频不变,节距照旧。
  final double speed;
  final void Function()? onFinished;
  final void Function(Object error)? onError;

  /// 轮询周期(测试注入短周期;生产 40ms)。
  final Duration pollInterval;

  static const _lookahead = Duration(milliseconds: 400);
  static const _maxLate = Duration(milliseconds: 40);

  final _pending = <_PendingPlay>[];
  Timer? _timer;
  Duration? _t0;
  int _next = 0;
  bool _finishedFired = false;

  bool get running => _timer != null;

  /// 音乐时长 → 引擎时长(慢放 = 除以速度;速度 1 时零开销直通)。
  Duration _scaled(Duration musicTime) => speed == 1.0
      ? musicTime
      : Duration(microseconds: (musicTime.inMicroseconds / speed).round());

  /// 锚点(时间轴原点的引擎时刻);未启动为 null。视图按
  /// 「(引擎时刻 − t0)」读当前音乐秒——视觉不进调度(ADR-0005)。
  Duration? get t0 => _t0;

  /// 已预定(含越过)的攻击数;测试观察用。
  int get scheduledCount => _next;

  /// 遥测:攻击总数 / 已消费数 / 在途预定数。
  int get total => attacks.length;
  int get consumedCount => _next;
  int get pendingCount => _pending.length;

  /// 从锚点 [t0] 起跑并立即首过;契约与 TabNoteScheduler.start 相同:
  /// 重复 start 不叠加在途状态;锚点前过期(超容差)攻击越过不回放;
  /// [consumedUntil] 为重建时的已消费截止线(恢复窗前已响音不重放)。
  void start({required Duration t0, Duration? consumedUntil}) {
    stop(silenceRinging: false);
    _t0 = t0;
    _next = 0;
    _finishedFired = false;
    final now = engine.engineTime();
    while (_next < attacks.length) {
      final time = t0 + _scaled(attacks[_next].time);
      if (time < now - _maxLate ||
          (consumedUntil != null && time <= consumedUntil)) {
        _next++;
      } else {
        break;
      }
    }
    _timer = Timer.periodic(pollInterval, (_) => _pass());
    _pass();
  }

  /// 停止:取消轮询与在途预定。[silenceRinging] = 连已响未衰减的
  /// 尾音一并停(暂停/拖动用,立静);false 时只停未响预定(曲末用,
  /// 尾音自然衰减)。
  void stop({required bool silenceRinging}) {
    final pending = _clearScheduleState();
    if (pending.isEmpty) return;
    Duration? now;
    try {
      now = engine.engineTime();
    } catch (_) {}
    for (final entry in pending) {
      if (!silenceRinging && (now == null || entry.time <= now)) continue;
      try {
        engine.stop(entry.voice);
      } catch (_) {}
    }
  }

  List<_PendingPlay> _clearScheduleState() {
    _timer?.cancel();
    _timer = null;
    final pending = List.of(_pending);
    _pending.clear();
    _t0 = null;
    _next = 0;
    return pending;
  }

  void _pass() {
    final t0 = _t0;
    if (t0 == null) return;
    try {
      final now = engine.engineTime();
      final from = now - _maxLate;
      final limit = now + _lookahead;
      while (_next < attacks.length) {
        final attack = attacks[_next];
        final time = t0 + _scaled(attack.time);
        if (time > limit) break;
        if (time >= from) {
          final sounds = pickSound(attack.freqs);
          for (final sound in sounds) {
            if (sound == null) continue;
            _pending.add((voice: engine.playScheduled(sound, time), time: time));
          }
        }
        _next++;
      }
      final end = duration;
      if (end != null && !_finishedFired && now >= t0 + _scaled(end)) {
        _finishedFired = true;
        stop(silenceRinging: false);
        onFinished?.call();
        return;
      }
      // 清理 5 秒前的旧记录,长跑不积内存。
      const keep = Duration(seconds: 5);
      while (_pending.isNotEmpty && _pending.first.time < now - keep) {
        _pending.removeAt(0);
      }
    } catch (error) {
      // 错误恢复与 BeatScheduler/StrumScheduler 同纪律:先清调度状态
      // 再做引擎清理(各步独立容错),onError 必达原错误。
      stop(silenceRinging: false);
      onError?.call(error);
    }
  }
}
