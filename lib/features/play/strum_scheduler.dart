import 'dart:async';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/beat_scheduling.dart' show BeatSchedule;
import '../../core/audio/beat_scheduler.dart' show BeatScheduler;
import '../../core/audio/pluck_player.dart' show PluckPlayer;
import '../../core/model/strum_pattern.dart' show StrumDirection;
import '../../core/practice/play_timeline.dart';

/// 一条在途预定:voice 与其引擎时刻(过期清理与停机判定用)。
typedef _PendingStrum = ({EngineVoice voice, Duration time});

/// 示范扫弦声调度器(工单 10 参考音=扫弦):把 [PlayTimeline] 的扫弦
/// 事件接到引擎 playClocked——每事件按弦位错峰预定一组拨弦。
///
/// 调度纪律与 core/audio `BeatScheduler` 相同(40ms 轮询 + 400ms 提前量
/// + 40ms 迟到容差,spike B 真机验证参数;Timer 只当轮询触发器,一切
/// 时刻读引擎时钟,ADR-0005)。锚点 t0 与节拍网格同源(由跟练控制器
/// 一次给定):变速/暂停恢复后由控制器以新锚点重建本调度器,事件时刻
/// (编译进时间轴的相对量)不在这里重算——声画同刻靠时间轴单一来源。
class StrumScheduler {
  StrumScheduler({
    required this.engine,
    required this.strums,
    required this.pickStrings,
    this.onError,
  });

  /// 轮询与过窗参数:与节拍调度器同源引用(spike B 验证值 + 工单 24
  /// 有界策略)——调度纪律只此一份,调参两驱动器一起动。
  static const pollInterval = BeatScheduler.pollInterval;
  static final Duration _lookahead = BeatSchedule.defaultLookahead;
  static final Duration _maxLate = BeatSchedule.defaultMaxLate;

  /// 每次扫弦的弦间错峰间隔:与和弦示范音同一物理语义,单一来源。
  static const _strumGap = PluckPlayer.strumGap;

  final AudioEngine engine;

  /// 时间轴扫弦事件(按时刻升序;调用方从 PlayTimeline.strums 取)。
  final List<PlayStrumEvent> strums;

  /// 和弦名+扫弦方向 → 弦音表(4 弦→1 弦序,闷音弦为 null 占时位)。
  /// 方向供音源层定声(下/上扫音色区分,工单 11,见 PluckPlayer.strumMs);
  /// 和弦查不到(和弦库缺位等降级路径)返回 null,该事件静默越过。
  /// 音源须已预注入(PluckPlayer.preloadStrumSounds),过窗调度是同步
  /// 路径、免 await。
  final List<EngineSound?>? Function(String chord, StrumDirection direction)
      pickStrings;

  /// 引擎调用失败上报(调用方据此停机并提示)。
  final void Function(Object error)? onError;

  final _pending = <_PendingStrum>[];

  Timer? _timer;

  /// 锚点(时间轴原点的引擎时刻)与首个未预定事件下标;未启动为 null。
  Duration? _t0;
  int _next = 0;

  bool get running => _timer != null;

  /// 已预定(含越过)的事件数;曲末判定与测试观察用。
  int get scheduledCount => _next;

  /// 从锚点 [t0] 起跑,并立即过一次窗。锚点处已过期(超迟到容差)的
  /// 事件越过不回放——暂停恢复后由控制器以重锚 t0 重建本调度器,恢复
  /// 窗前的扫弦按「已随暂停消逝」处理,绝不回放。
  void start({required Duration t0}) {
    stop(); // 与 BeatScheduler.start 同契约:重复 start 不叠加在途状态
    _t0 = t0;
    _next = 0;
    // 锚点前的过期事件直接越过:事件时刻 = t0+time,早于 now−容差即弃。
    final now = engine.engineTime();
    while (_next < strums.length &&
        t0 + strums[_next].time < now - _maxLate) {
      _next++;
    }
    _timer = Timer.periodic(pollInterval, (_) => _pass());
    _pass();
  }

  /// 停止:取消轮询,停掉尚未发声的预定,清空调度状态。
  void stop() {
    _stopPending(_clearScheduleState());
  }

  /// 清空调度状态(取消轮询、清锚点与在途记录),返回被丢弃的记录供
  /// 引擎侧善后;不碰引擎(与 BeatScheduler._clearScheduleState 同纪律:
  /// 先清状态再做引擎清理,出错路径不致状态残留)。
  List<_PendingStrum> _clearScheduleState() {
    _timer?.cancel();
    _timer = null;
    final pending = List.of(_pending);
    _pending.clear();
    _t0 = null;
    _next = 0;
    return pending;
  }

  /// 停掉 [pending] 中尚未发声的预定;各步独立容错(引擎异常时恢复
  /// 路径不得再抛)。
  void _stopPending(List<_PendingStrum> pending) {
    if (pending.isEmpty) return;
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
  }

  void _pass() {
    final t0 = _t0;
    if (t0 == null) return;
    try {
      final now = engine.engineTime();
      final from = now - _maxLate;
      final limit = now + _lookahead;
      while (_next < strums.length) {
        final event = strums[_next];
        final time = t0 + event.time;
        if (time > limit) break;
        if (time >= from) _scheduleStrum(event, time);
        _next++;
      }
      // 清理 5 秒前的旧记录,长跑不积内存(已响 voice 的 stop 是空操作)。
      const keep = Duration(seconds: 5);
      while (_pending.isNotEmpty && _pending.first.time < now - keep) {
        _pending.removeAt(0);
      }
    } catch (error) {
      // 错误恢复与 BeatScheduler._pass 同纪律:先清调度状态,再做引擎
      // 清理(各步独立容错),onError 必达原错误。
      _stopPending(_clearScheduleState());
      onError?.call(error);
    }
  }

  /// 预定一次扫弦:弦音表按方向定序(下扫 4 弦→1 弦、上扫反向——拨片
  /// 物理扫过弦序)且按方向定声(方向传入定声缝),逐弦错峰
  /// [PluckPlayer.strumGap] 等价间隔。静默弦位同样占时位(不发声),
  /// 与和弦示范音同一物理语义。
  void _scheduleStrum(PlayStrumEvent event, Duration time) {
    final strings = event.chord == null
        ? null
        : pickStrings(event.chord!, event.direction);
    if (strings == null) return;
    final order =
        event.direction == StrumDirection.down ? strings : strings.reversed;
    var slot = Duration.zero;
    for (final sound in order) {
      if (sound != null) {
        _pending.add((voice: engine.playClocked(sound, time + slot), time: time + slot));
      }
      slot += _strumGap;
    }
  }
}
