import 'dart:async';

import 'audio_engine.dart';
import 'beat_scheduling.dart';

/// 一条在途预定:拍号、voice、引擎时刻(拍号供变速重排定位)。
typedef _PendingPlay = ({int beat, EngineVoice voice, Duration time});

/// 节拍调度驱动器:把 [BeatSchedule] 纯函数决策接到引擎上。
///
/// 40ms 轮询 + 400ms 提前量窗口(均为 spike B 真机验证参数,调度器
/// 写死;纯函数缝上的 lookahead/maxLate 可调,但本类只显式传自己的值)。
/// Timer 只当轮询触发器,一切时刻读引擎时钟(ADR-0005:Timer 自身
/// 不参与任何时刻计算,快慢漂移不影响节拍网格)。
class BeatScheduler {
  BeatScheduler({
    required this.engine,
    required this.pickSound,
    this.onError,
  });

  /// 轮询周期。spike B 验证值。
  static const pollInterval = Duration(milliseconds: 40);

  /// 按拍序号选音源(节拍器:4/4 强弱拍;返回 null 表示该拍静默)。
  final EngineSound? Function(int beat) pickSound;

  /// 引擎调用失败上报(调用方据此停机并提示)。
  final void Function(Object error)? onError;

  final AudioEngine engine;

  /// 已预定未清理的发声记录(拍号供变速重排:取消未响拍时定位最早要
  /// 按新网格重排的拍)。
  final _pending = <_PendingPlay>[];

  Timer? _timer;
  BeatSchedule? _schedule;

  bool get running => _timer != null;

  /// 已预定拍数(下一未预定拍序号)。
  int get scheduledCount => _schedule?.nextBeat ?? 0;

  /// 视觉层锚点:时间轴起点与拍周期;未运行时 null。
  ({Duration t0, double periodMs})? get anchor {
    final s = _schedule;
    return s == null ? null : (t0: s.t0, periodMs: s.periodMs);
  }

  /// 从引擎当前时刻起跑,并立即过一次窗(第 0 拍即刻可闻)。已知残余
  /// 风险:t0 与首过是引擎时钟的两次读数,若启动瞬间线程停顿超过迟到
  /// 容差(40ms)则第 0 拍被跳过——旧实现必响第 0 拍,但那正是无界追赶
  /// 的缝;此情仅引擎线程异常停顿时发生,接受之。
  /// [totalBeats] 给定时走出最后一拍不再预定(跟练曲末无幻拍声,
  /// 与 practiceStateAt 的曲末判定同界);null = 连续(节拍器/训练器)。
  /// [bpm] 非正抛 [ArgumentError](控制器钳制是调用方的职责,公共缝自守)。
  void start({required int bpm, int? totalBeats}) {
    _requireBpm(bpm);
    stop();
    _schedule = BeatSchedule(
      t0: engine.engineTime(),
      nextBeat: 0,
      periodMs: 60000 / bpm,
      totalBeats: totalBeats,
    );
    // 先建定时器再首过:首过抛错时 catch 里的 stop() 才能取消它。
    _timer = Timer.periodic(pollInterval, (_) => _pass());
    _pass();
  }

  /// 运行中换 BPM 即时生效(相位保持重锚定,已排队未响拍按新网格重排,
  /// 不与旧网格倒挂);未运行时忽略。[bpm] 非正抛 [ArgumentError]。
  void changeBpm(int bpm) {
    _requireBpm(bpm);
    final s = _schedule;
    if (s == null || !running) return;
    final now = engine.engineTime();
    var next = s.reanchored(now, 60000 / bpm);
    // 重锚有界:取消旧网格已预定、尚未发声的拍,rewind 到最早被取消的
    // 拍号,交还正常过窗按新网格重排(拍号与拍内相位保持)——大跨度变速
    // (如 40→208)不重排时,旧拍会排在新网格拍之后,倒挂出格。
    // 各取消独立容错(与 _pass 恢复路径同一纪律):单个 stop 失败不得
    // 让 changeBpm 半途抛出、留下半更新状态。
    int? earliestCancelled;
    for (final entry in _pending) {
      if (entry.time > now) {
        try {
          engine.stop(entry.voice);
        } catch (_) {}
        if (earliestCancelled == null || entry.beat < earliestCancelled) {
          earliestCancelled = entry.beat;
        }
      }
    }
    if (earliestCancelled != null) {
      _pending.removeWhere((entry) => entry.time > now);
      next = next.withNextBeat(earliestCancelled);
    }
    _schedule = next;
    _pass();
  }

  static void _requireBpm(int bpm) {
    if (bpm <= 0) throw ArgumentError.value(bpm, 'bpm', 'BPM 必须为正');
  }

  /// 停止:取消轮询,停掉尚未发声的预定,清空时间轴。
  void stop() {
    final pending = _clearScheduleState();
    final now = engine.engineTime();
    for (final entry in pending) {
      if (entry.time > now) engine.stop(entry.voice);
    }
  }

  /// 清空本地调度状态(取消轮询、清预定记录与时间轴),返回被丢弃的
  /// 预定记录供引擎侧善后;不碰引擎。先清状态再做引擎清理,出错路径
  /// (见 _pass)不致状态残留。
  List<_PendingPlay> _clearScheduleState() {
    _timer?.cancel();
    _timer = null;
    final pending = List.of(_pending);
    _pending.clear();
    _schedule = null;
    return pending;
  }

  void _pass() {
    final s = _schedule;
    if (s == null) return;
    try {
      final now = engine.engineTime();
      final (next, due) = s.scheduleDue(
        now: now,
        lookahead: BeatSchedule.defaultLookahead,
        maxLate: pollInterval,
      );
      _schedule = next;
      for (final (beat, time) in due) {
        final sound = pickSound(beat);
        if (sound == null) continue;
        _pending.add((beat: beat, voice: engine.playClocked(sound, time), time: time));
      }
      // 清理 5 秒前的旧记录,长跑不积内存(已响 voice 的 stop 是空操作)。
      const keep = Duration(seconds: 5);
      while (_pending.isNotEmpty && _pending.first.time < now - keep) {
        _pending.removeAt(0);
      }
    } catch (error) {
      // 错误恢复:先清调度状态,再做引擎清理——清理各步独立容错,任何
      // 一步失败都不得再抛、掩盖原 error 或跳过 onError。
      final pending = _clearScheduleState();
      Duration? now;
      try {
        now = engine.engineTime();
      } catch (_) {}
      for (final entry in pending) {
        if (now == null || entry.time <= now) continue;
        try {
          engine.stop(entry.voice);
        } catch (_) {}
      }
      onError?.call(error);
    }
  }
}
