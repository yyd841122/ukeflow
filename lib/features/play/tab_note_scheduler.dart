import 'dart:async';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/beat_scheduling.dart' show BeatSchedule;
import '../../core/audio/beat_scheduler.dart' show BeatScheduler;
import '../../core/practice/tab_timeline.dart';

/// 一条在途预定:voice 与其引擎时刻(过期清理与停机判定用)。
typedef _PendingNote = ({EngineVoice voice, Duration time});

/// 逐音示范声调度器(工单 13):把 [TabTimeline] 的单音事件接到引擎
/// playClocked——每事件预定一声拨弦,与四线谱高亮出自同一份时间轴、
/// 同一个曲头锚,「示范声与高亮同刻」是结构保证(ADR-0005)。
///
/// 调度纪律与 core/audio `BeatScheduler`、`StrumScheduler` 相同(40ms
/// 轮询 + 400ms 提前量 + 40ms 迟到容差,spike B 真机验证参数;Timer
/// 只当轮询触发器,一切时刻读引擎时钟)。锚点 t0 与节拍网格同源(由
/// 跟练控制器一次给定):变速/暂停恢复后由控制器以新锚点重建本调度器,
/// 事件时刻(编译进时间轴的相对量)不在这里重算。单音无扫弦的弦间
/// 错峰,事件即声,一事件一预定。
class TabNoteScheduler {
  TabNoteScheduler({
    required this.engine,
    required this.notes,
    required this.pickSound,
    this.onError,
  });

  /// 轮询与过窗参数:与节拍/扫弦调度器同源引用(spike B 验证值)——
  /// 调度纪律只此一份,调参三驱动器一起动。
  static const pollInterval = BeatScheduler.pollInterval;
  static final Duration _lookahead = BeatSchedule.defaultLookahead;
  static final Duration _maxLate = BeatSchedule.defaultMaxLate;

  final AudioEngine engine;

  /// 时间轴单音事件(按时刻升序;调用方从 TabTimeline.notes 取)。
  final List<TabNoteEvent> notes;

  /// 单音 → 音源(音高查预注入的 KS 音源)。查不到(音源缺位等降级
  /// 路径)返回 null,该事件静默越过。过窗调度同步调用,免 await。
  final EngineSound? Function(TabNoteEvent note) pickSound;

  /// 引擎调用失败上报(调用方据此停机并提示)。
  final void Function(Object error)? onError;

  final _pending = <_PendingNote>[];

  Timer? _timer;

  /// 锚点(时间轴原点的引擎时刻)与首个未预定事件下标;未启动为 null。
  Duration? _t0;
  int _next = 0;

  bool get running => _timer != null;

  /// 已预定(含越过)的事件数;测试观察用。
  int get scheduledCount => _next;

  /// 从锚点 [t0] 起跑,并立即过一次窗。锚点处已过期(超迟到容差)的
  /// 事件越过不回放——暂停恢复后由控制器以重锚 t0 重建本调度器,恢复
  /// 窗前的音按「已随暂停消逝」处理,绝不回放。与 BeatScheduler.start
  /// 同契约:重复 start 不叠加在途状态。
  void start({required Duration t0}) {
    stop();
    _t0 = t0;
    _next = 0;
    // 锚点前的过期事件直接越过:事件时刻 = t0+time,早于 now−容差即弃。
    final now = engine.engineTime();
    while (_next < notes.length && t0 + notes[_next].time < now - _maxLate) {
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
  /// 引擎侧善后;不碰引擎(与 BeatScheduler/StrumScheduler 同纪律:
  /// 先清状态再做引擎清理,出错路径不致状态残留)。
  List<_PendingNote> _clearScheduleState() {
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
  void _stopPending(List<_PendingNote> pending) {
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
      while (_next < notes.length) {
        final note = notes[_next];
        final time = t0 + note.time;
        if (time > limit) break;
        if (time >= from) {
          final sound = pickSound(note);
          if (sound != null) {
            _pending.add((voice: engine.playClocked(sound, time), time: time));
          }
        }
        _next++;
      }
      // 清理 5 秒前的旧记录,长跑不积内存(已响 voice 的 stop 是空操作)。
      const keep = Duration(seconds: 5);
      while (_pending.isNotEmpty && _pending.first.time < now - keep) {
        _pending.removeAt(0);
      }
    } catch (error) {
      // 错误恢复与 BeatScheduler/StrumScheduler 同纪律:先清调度状态,
      // 再做引擎清理(各步独立容错),onError 必达原错误。
      _stopPending(_clearScheduleState());
      onError?.call(error);
    }
  }
}
