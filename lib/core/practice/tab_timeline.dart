/// 逐音事件时间轴:指弹谱+BPM(+变速)预编译出的全部单音事件,
/// 每个事件含引擎时刻。GLOSSARY「动作事件时间轴」的指弹对应物——
/// 但两者是**各自独立的时间轴**(ADR-0003:指弹谱与弹唱谱不统一,
/// sealed 事件族也不跨谱共用):弹唱时间轴装扫弦/歌词/段落,本时间轴
/// 只装单音,消费方是指弹跟练与逐音示范(工单 12/13)。
///
/// 时间源语义与工单 08 完全同型(同一纪律,两处测试各自锁定):
/// - 时刻是**相对量**(自时间轴原点 0),锚定 t0 由消费方决定,编译器
///   不知道引擎存在;
/// - 事件时刻 = 逐事件「拍位 × 有效拍长」四舍五入,**不累加**——与
///   core/audio `BeatSchedule.beatTime` 同一取整边界,拍上的音与节拍
///   声同源同刻;
/// - 纯函数、零引擎依赖,标准 flutter test 覆盖,本文件无任何时钟。
library;

import 'dart:math' as math;

import '../audio/beat_scheduling.dart' show beatsPerBar, effectivePeriodMs;
import '../model/tab_chart.dart';

/// 时间轴上的一个单音事件。[time] 为相对时间轴原点的时刻。
class TabNoteEvent {
  const TabNoteEvent({
    required this.time,
    required this.string,
    required this.fret,
    required this.frequency,
  });

  final Duration time;

  /// 弦号(1..4,GLOSSARY「弦号」)与品位(0 = 空弦),四线谱高亮与
  /// 逐音示范声共用(工单 13)。
  final int string;
  final int fret;

  /// 该音基频(Hz),KS 拨弦音源直接可用——时刻与音高在编译期一次算定,
  /// 消费方不再各自换算(单一来源)。
  final double frequency;

  @override
  String toString() => 'TabNoteEvent($string 弦 $fret 品 @$time)';
}

/// 一首指弹谱编译出的逐音事件时间轴。
class TabTimeline {
  /// 私有构造:notes 一律从 [compileTabTimeline] 产出(按时刻升序,
  /// 同刻保持录入序),外部无法供给失序列表。
  TabTimeline._(
    List<TabNoteEvent> notes, {
    required this.periodMs,
    required this.totalBeats,
  }) : notes = List.unmodifiable(notes);

  /// 全部单音事件,按时刻升序(同一时刻按录入序,谱面原样的先后
  /// 就是演奏指示)。
  final List<TabNoteEvent> notes;

  /// 有效拍长(毫秒,四分)= 60000/BPM/变速比,与弹唱时间轴同义。
  final double periodMs;

  /// 全曲拍数 = [tabTotalBeats](末音保有整拍、上取整到整小节线)。
  /// 曲末判定(工单 13)与四线谱小节线共用这一定义。
  final int totalBeats;

  /// 名义曲长(末小节奏完)。
  Duration get totalDuration =>
      Duration(milliseconds: (totalBeats * periodMs).round());
}

/// 指弹谱的全曲拍数:最后一个音保有整拍(ceil(末音拍)+1,半拍上收),
/// 再上取整到整小节线(4/4)——曲末判定与四线谱小节线共用,单一来源。
/// 空谱为 0。
int tabTotalBeats(TabChart chart) {
  if (chart.notes.isEmpty) return 0;
  final end = chart.notes.map((n) => n.beat).reduce(math.max).ceil() + 1;
  return (end / beatsPerBar).ceil() * beatsPerBar;
}

/// 时间轴编译器:指弹谱+BPM(+变速)→ [TabTimeline]。
///
/// 录入序不保证时序,编译期按拍位稳定排序(同拍保持录入序——谱面
/// 先后就是同时拨响的指示);事件时刻逐事件四舍五入不累加(见库注释)。
TabTimeline compileTabTimeline({
  required TabChart chart,
  required double bpm,
  double speed = 1.0,
}) {
  // 入参校验与拍周期换算走 beat_scheduling 的单一来源(与弹唱
  // compileTimeline 同缝,release 也生效,不靠 assert)。
  final periodMs = effectivePeriodMs(bpm: bpm, speed: speed);

  Duration noteTime(double beat) =>
      Duration(milliseconds: (beat * periodMs).round());

  return TabTimeline._(
    [
      // 录入序不保证时序,按 (拍位,录入序) 复合键稳定排序(同拍保持
      // 录入序——谱面先后就是同时拨响的指示;sortedTabNotes 单一来源)。
      for (final note in sortedTabNotes(chart.notes))
        TabNoteEvent(
          time: noteTime(note.beat),
          string: note.string,
          fret: note.fret,
          frequency: note.frequency,
        ),
    ],
    periodMs: periodMs,
    totalBeats: tabTotalBeats(chart),
  );
}
