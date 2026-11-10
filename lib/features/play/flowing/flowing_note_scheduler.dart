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
    this.loopStart,
    this.loopEnd,
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

  /// AB 循环窗口(音乐秒,票02;两者齐备且 start < end 才生效)。B 独占:
  /// 响到 B 即回 A;越 B 时刻把「绝对时刻 < 回跳点」的在途声全停(旧轮
  /// 尾音截断,不叠上一轮余音),新轮已跨缝预定的声保留——A 点不重音
  /// 不漏音。循环中 [duration] 曲末检查不生效(循环直到用户停)。
  final Duration? loopStart;
  final Duration? loopEnd;
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

  /// 循环轮次的音乐域累计偏移(k·窗口长;纯音乐域推进——越过 B 的攻击
  /// 即触发进下一轮,提前至多一个 lookahead 跨接缝预定,接缝零空拍;
  /// 与视图的模回跳公式出自同一 t0,音画结构同源)。
  Duration _passBase = Duration.zero;

  /// 已做过截尾的轮次基线(每轮越 B 只截一次)。
  Duration? _cutDoneBase;

  bool get _loopActive {
    final a = loopStart;
    final b = loopEnd;
    return a != null && b != null && b > a;
  }

  /// 第一个音乐时刻 ≥ [musicTime] 的攻击下标(二分)。
  int _firstIndexFrom(Duration musicTime) {
    var lo = 0;
    var hi = attacks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (attacks[mid].time < musicTime) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

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
    _passBase = Duration.zero;
    _cutDoneBase = null;
    return pending;
  }

  void _pass() {
    final t0 = _t0;
    if (t0 == null) return;
    try {
      final now = engine.engineTime();
      final from = now - _maxLate;
      final limit = now + _lookahead;
      final looping = _loopActive;
      final a = looping ? loopStart! : null;
      final b = looping ? loopEnd! : null;
      while (true) {
        // 需要进下一轮:攻击走完(循环永不走完)或越过 B。
        var needPass = _next >= attacks.length;
        if (!needPass && b != null && attacks[_next].time >= b) needPass = true;
        if (needPass) {
          if (b == null) break; // 非循环:攻击奏毕。
          // 本轮窗口奏毕,进下一轮(纯音乐域推进,跨接缝提前预定)。
          final first = _firstIndexFrom(a!);
          if (first >= attacks.length || attacks[first].time >= b) {
            break; // 窗内无攻击:无可推进项(截尾仍按时刻照做)。
          }
          _passBase += b - a;
          _next = first;
        }
        final time = t0 + _scaled(attacks[_next].time + _passBase);
        if (time > limit) break;
        if (time >= from) {
          final sounds = pickSound(attacks[_next].freqs);
          for (final sound in sounds) {
            if (sound == null) continue;
            _pending.add((voice: engine.playScheduled(sound, time), time: time));
          }
        }
        _next++;
      }
      if (looping) {
        // 越 B 截尾:上一轮的 B 绝对时刻一到,停掉绝对时刻 < 回跳点的
        // 在途声(旧轮尾音,含刚过 B 未理的预定),新轮跨缝预定(时刻
        // ≥ 回跳点)保留。每轮只做一次。
        final wrapAt =
            t0 + _scaled(b! + _passBase - (b - a!));
        if (now >= wrapAt && _cutDoneBase != _passBase) {
          _cutDoneBase = _passBase;
          for (final entry in _pending) {
            if (entry.time < wrapAt) {
              try {
                engine.stop(entry.voice);
              } catch (_) {}
            }
          }
          _pending.removeWhere((e) => e.time < wrapAt);
        }
      } else {
        final end = duration;
        if (end != null && !_finishedFired && now >= t0 + _scaled(end)) {
          _finishedFired = true;
          stop(silenceRinging: false);
          onFinished?.call();
          return;
        }
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
