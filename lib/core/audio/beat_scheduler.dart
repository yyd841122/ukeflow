import 'dart:async';

import 'audio_engine.dart';
import 'beat_scheduling.dart';

/// 节拍调度驱动器:把 [BeatSchedule] 纯函数决策接到引擎上。
///
/// 40ms 轮询 + 400ms 提前量窗口(均为 spike B 真机验证参数,写死不外露)。
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
  final _pending = <(EngineVoice, Duration)>[];

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

  /// 从引擎当前时刻起跑,并立即过一次窗(第 0 拍即刻可闻)。
  void start({required int bpm}) {
    stop();
    _schedule = BeatSchedule(
      t0: engine.engineTime(),
      nextBeat: 0,
      periodMs: 60000 / bpm,
    );
    // 先建定时器再首过:首过抛错时 catch 里的 stop() 才能取消它。
    _timer = Timer.periodic(pollInterval, (_) => _pass());
    _pass();
  }

  /// 运行中换 BPM 即时生效(相位保持重锚定);未运行时忽略。
  void changeBpm(int bpm) {
    final s = _schedule;
    if (s == null || !running) return;
    _schedule = s.reanchored(engine.engineTime(), 60000 / bpm);
    _pass();
  }

  /// 停止:取消轮询,停掉尚未发声的预定,清空时间轴。
  void stop() {
    _timer?.cancel();
    _timer = null;
    final now = engine.engineTime();
    for (final (voice, time) in _pending) {
      if (time > now) engine.stop(voice);
    }
    _pending.clear();
    _schedule = null;
  }

  void _pass() {
    final s = _schedule;
    if (s == null) return;
    try {
      final now = engine.engineTime();
      final (next, due) = s.scheduleDue(now: now, lookahead: BeatSchedule.defaultLookahead);
      _schedule = next;
      for (final (beat, time) in due) {
        final sound = pickSound(beat);
        if (sound == null) continue;
        _pending.add((engine.playClocked(sound, time), time));
      }
      // 清理 5 秒前的旧记录,长跑不积内存(已响 voice 的 stop 是空操作)。
      const keep = Duration(seconds: 5);
      while (_pending.isNotEmpty && _pending.first.$2 < now - keep) {
        _pending.removeAt(0);
      }
    } catch (error) {
      stop();
      onError?.call(error);
    }
  }
}
