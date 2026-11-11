import 'dart:async';

import '../../../core/audio/audio_engine.dart';

/// 一次同时拨响:相对时间轴原点的时刻 + 该刻要拨的全部音高(Hz)。
typedef FlowingAttack = ({Duration time, List<double> freqs});

/// 节拍器拍点(票04):音乐域时刻 + 是否小节头重拍(strong/weak 音色)。
typedef FlowingBeat = ({Duration time, bool accent});

/// 声音分路(票04):在途预定按路记账,静音/截尾按路停声。count 路是
/// 数四下 tick(票03,音量骑节拍音量但开关独立),不经分路静音。
enum _Channel { note, metro, count }

/// 一条在途预定:voice、引擎时刻与所属分路(过期清理、静音停声与
/// 停机善后用)。
typedef _PendingPlay = ({EngineVoice voice, Duration time, _Channel channel});

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
    this.countPerLoop = false,
    this.beatDur,
    this.pickCountSound,
    this.beats = const [],
    this.pickMetroSound,
    this.demoEnabled = true,
    this.demoVolume = 1.0,
    this.metroEnabled = false,
    this.metroVolume = 0.5,
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

  /// 循环每轮数四下(票03):每轮回跳后插 4 记数拍 tick(独立预备钟,
  /// 占真实时刻但不占曲谱时间——红线在 A 定住),下一轮整体后移一个
  /// gap(4 拍)。tick 与示范声同用 playScheduled 绝对时刻。
  final bool countPerLoop;

  /// 数拍节拍时长(音乐域 60/tempo;慢放由 [speed] 缩放)。null = 无数拍。
  final Duration? beatDur;

  /// 数拍音源查取(独立 tick 音色,非 KS 示范声);null/返回 null = 静默。
  final EngineSound? Function()? pickCountSound;

  /// 节拍器拍点序列(票04,音乐域升序;控制器从小节表预处理)。与示范
  /// 声同走一套循环/慢放变换——第二游标并走同一个 pass 循环,轮次推进
  /// (passBase)与截尾完全共享,拍点与红线同源同刻。
  final List<FlowingBeat> beats;

  /// 节拍音源查取(重拍 strong / 弱拍 weak);null/返回 null = 静默。
  final EngineSound? Function(bool accent)? pickMetroSound;

  /// 分路开关与音量(票04;可变字段,构造给初值——播放中即切由控制
  /// 器直改,不重建调度器不重锚,位置天然连续)。静音 = 不预定新声 +
  /// 停该路在途未响(已响尾音自然衰减);**游标照走、时钟照推**——
  /// 静音的是出声不是时间,红线与推进不受影响(测试锁定)。音量在预
  /// 定时刻定音,改音量只影响之后的预定(在途 ≤400ms 内的已排声保持
  /// 旧值)。
  bool demoEnabled;
  double demoVolume;
  bool metroEnabled;
  double metroVolume;

  /// 循环轮间音乐域 gap(countPerLoop 时的 4 拍;轮次推进与视图模回跳
  /// 公式的 cycle = 窗长 + gap 必须同源一致)。
  Duration get _gapMusic =>
      countPerLoop && beatDur != null ? beatDur! * 4 : Duration.zero;
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

  /// 节拍流游标(票04;与示范声同型:序推进、循环回跳重置)。
  int _nextMetro = 0;
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

  /// 第一个音乐时刻 ≥ [musicTime] 的拍点下标(二分,与攻击同型)。
  int _firstBeatIndexFrom(Duration musicTime) {
    var lo = 0;
    var hi = beats.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (beats[mid].time < musicTime) {
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
    // 节拍流同型跳过(票04:重建时已响拍点不重响)。
    while (_nextMetro < beats.length) {
      final time = t0 + _scaled(beats[_nextMetro].time);
      if (time < now - _maxLate ||
          (consumedUntil != null && time <= consumedUntil)) {
        _nextMetro++;
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
    _nextMetro = 0;
    _passBase = Duration.zero;
    _cutDoneBase = null;
    return pending;
  }

  /// 静音示范路(票04):停该路在途未响预定(已响尾音自然衰减)。
  /// 游标照走、时钟照推——静音的是出声不是时间。
  void silenceDemoPending() => _silenceChannel(_Channel.note);

  /// 静音节拍路(票04):只停节拍 tick;循环数拍(count 路)归数四下
  /// 开关管,不受此影响(音量仍骑节拍音量滑条,codex 同款)。
  void silenceMetroPending() => _silenceChannel(_Channel.metro);

  void _silenceChannel(_Channel channel) {
    Duration? now;
    try {
      now = engine.engineTime();
    } catch (_) {
      return; // 钟不可读:不动在途(停机/截尾路径兜底)。
    }
    final effective = now;
    // 只停未响在途(立静);已响尾音自然衰减——静音不是暂停,不该听得见。
    for (final entry in _pending
        .where((e) => e.channel == channel && e.time > effective)
        .toList()) {
      try {
        engine.stop(entry.voice);
      } catch (_) {}
    }
    _pending.removeWhere((e) => e.channel == channel && e.time > effective);
  }

  /// 预定一组同刻拨弦(和弦一事件多声;音量走示范路)。
  void _scheduleNote(FlowingAttack attack, Duration time) {
    if (!demoEnabled) return;
    final sounds = pickSound(attack.freqs);
    for (final sound in sounds) {
      if (sound == null) continue;
      _pending.add((
        voice: engine.playScheduled(sound, time, volume: demoVolume),
        time: time,
        channel: _Channel.note,
      ));
    }
  }

  /// 预定一记节拍 tick(重拍 strong/弱拍 weak,音量走节拍路)。
  void _scheduleMetro(FlowingBeat beat, Duration time) {
    if (!metroEnabled) return;
    final sound = pickMetroSound?.call(beat.accent);
    if (sound == null) return;
    _pending.add((
      voice: engine.playScheduled(sound, time, volume: metroVolume),
      time: time,
      channel: _Channel.metro,
    ));
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
        // 需要进下一轮:两流都越过窗口末(循环)或都走完(非循环)。
        // 节拍流与示范声同窗同轮次——拍点与红线/示范声同源同刻(票04)。
        final notePast =
            _next >= attacks.length || (b != null && attacks[_next].time >= b);
        final metroPast = _nextMetro >= beats.length ||
            (b != null && beats[_nextMetro].time >= b);
        if (notePast && metroPast) {
          if (b == null) break; // 非循环:示范声与节拍都奏毕。
          // 本轮窗口奏毕,进下一轮(纯音乐域推进,跨接缝提前预定)。
          final first = _firstIndexFrom(a!);
          final firstMetro = _firstBeatIndexFrom(a);
          final emptyNote =
              first >= attacks.length || attacks[first].time >= b;
          final emptyMetro =
              firstMetro >= beats.length || beats[firstMetro].time >= b;
          if (emptyNote && emptyMetro) {
            break; // 窗内无事件:无可推进项(截尾仍按时刻照做)。
          }
          // 回跳点(本轮 B 的绝对时刻)= 下一轮数拍的起拍。
          final wrapAt = t0 + _scaled(b + _passBase);
          _passBase += (b - a) + _gapMusic;
          _next = first;
          _nextMetro = firstMetro;
          // 数四下(票03):回跳后 4 记 tick,下一轮示范声整体后移一个
          // gap。tick 预定可远超 lookahead(playScheduled 绝对时刻,幂等
          // 停机由 _pending 收口);已过容差的跳过。音量骑节拍音量(票04,
          // codex 同款:预备 tick 属节拍通道,开关归「每轮数」)。
          if (_gapMusic > Duration.zero && pickCountSound != null) {
            final tickSound = pickCountSound!();
            if (tickSound != null) {
              for (var j = 0; j < 4; j++) {
                final at = wrapAt + _scaled(beatDur! * j);
                if (at < now - _maxLate) continue;
                _pending.add((
                  voice: engine.playScheduled(tickSound, at,
                      volume: metroVolume),
                  time: at,
                  channel: _Channel.count,
                ));
              }
            }
          }
        }
        // 双流合并取最早:示范声与节拍各按自身游标给候选,轮到谁预定谁
        // (并列按示范声先;处理顺序不影响绝对时刻)。候选越 lookahead
        // 即歇,下轮询再来。静音开关只拦「预定」,游标照走——静音的是
        // 出声不是时间(票04 红线,测试锁定)。
        final tNote = notePast
            ? null
            : t0 + _scaled(attacks[_next].time + _passBase);
        final tMetro = metroPast
            ? null
            : t0 + _scaled(beats[_nextMetro].time + _passBase);
        if (tNote == null && tMetro == null) break; // 防御:双流皆无候选。
        // 节拍优先于并列/更晚的示范声?(顺序处理,绝对时刻不受影响。)
        if (tMetro != null && (tNote == null || tMetro <= tNote)) {
          if (tMetro > limit) break;
          if (tMetro >= from) _scheduleMetro(beats[_nextMetro], tMetro);
          _nextMetro++;
        } else {
          // 双空已在上面的 break 排除;此支 tMetro 空或更晚,tNote 必非空。
          final note = tNote ?? (t0 + _scaled(attacks[_next].time + _passBase));
          if (note > limit) break;
          if (note >= from) _scheduleNote(attacks[_next], note);
          _next++;
        }
      }
      if (looping) {
        // 越 B 截尾:上一轮的 B 绝对时刻一到,停掉绝对时刻 < 回跳点的
        // 在途声(旧轮尾音,含刚过 B 未理的预定),新轮跨缝预定(时刻
        // ≥ 回跳点,含数拍 tick)保留。每轮只做一次。上一轮 base =
        // 新 base − 窗长 − gap(gap 为 0 即票02 原式)。
        final wrapAt =
            t0 + _scaled(b! + _passBase - (b - a!) - _gapMusic);
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
