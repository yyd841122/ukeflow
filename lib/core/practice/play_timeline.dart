/// 动作事件时间轴（GLOSSARY「跟练」的地基）：弹唱谱+节奏型+BPM（+变速）
/// 预编译出的全部动作事件，每个事件含引擎时刻。
///
/// 时间源唯一语义（ADR-0005）在此定型：
/// - 时间轴里的时刻是**相对时刻**（自时间轴原点 0 起），把它锚到引擎时钟
///   的哪一点（t0）由消费方（跟练控制器/示范试听）决定，编译器不知道
///   引擎存在；
/// - 事件时刻 = 逐事件「网格位置 × 单位毫秒」四舍五入，**不累加**——
///   与 core/audio `BeatSchedule.beatTime` 同一语义（spike B），保证
///   扫弦声与节拍声同源同刻：落在拍点的扫弦（偶数槽，槽 2k 即第 k 拍）
///   时刻恒等于该拍的 `beatTime`，任何变速下都成立（有测试守护）；
/// - 查询侧（practice_state.dart）只认调用方传入的引擎时刻，本文件
///   无任何时钟。
///
/// 纯函数、零引擎依赖（spec 测试接缝一），标准 flutter test 覆盖。
library;

import '../audio/beat_scheduling.dart'
    show beatsPerBar, requirePositiveFinite;
import '../model/strum_chart.dart';
import '../model/strum_pattern.dart';

/// 时间轴上的一个动作事件。[time] 为相对时间轴原点的时刻。
sealed class PlayEvent {
  const PlayEvent({required this.time});

  final Duration time;
}

/// 段落标记：进入一个段落（弹唱谱 [StrumSection]）。
class PlaySectionEvent extends PlayEvent {
  const PlaySectionEvent({
    required super.time,
    required this.sectionIndex,
    required this.section,
  });

  /// 在弹唱谱段落序列里的序号（自 0）。
  final int sectionIndex;
  final StrumSection section;
}

/// 歌词行：开始唱一行。
class PlayLyricEvent extends PlayEvent {
  const PlayLyricEvent({
    required super.time,
    required this.sectionIndex,
    required this.lineIndex,
    required this.line,
  });

  /// 所属段落在段落序列里的序号。
  final int sectionIndex;

  /// 行在段落内的序号（自 0）。
  final int lineIndex;
  final StrumLine line;
}

/// 一次扫弦（方向+和弦）。
class PlayStrumEvent extends PlayEvent {
  const PlayStrumEvent({
    required super.time,
    required this.barIndex,
    required this.slotInBar,
    required this.direction,
    required this.chord,
  });

  /// 全曲小节序号（自 0）。
  final int barIndex;

  /// 小节内八分槽位（0..7）。
  final int slotInBar;
  final StrumDirection direction;

  /// 该扫弦落在和弦库里的和弦名（可查指法/示范音）；
  /// 谱开头还没出现任何和弦记号时为 null（右手照扫，无和弦可依）。
  final String? chord;
}

/// 一首谱编译出的动作事件时间轴。
class PlayTimeline {
  /// 私有构造:分类视图（strums/lyrics/sections）一律从 [events] 单一
  /// 来源派生（编译顺序保证同刻 section→lyric→strum 定序、各自升序）,
  /// 外部无法再供给与视图发散/失序的列表。唯一构造入口是
  /// [compileTimeline]。
  PlayTimeline._(List<PlayEvent> events, {
    required this.periodMs,
    required this.totalBeats,
  })  : events = List.unmodifiable(events),
        strums = List.unmodifiable(
            [for (final event in events) if (event is PlayStrumEvent) event]),
        lyrics = List.unmodifiable(
            [for (final event in events) if (event is PlayLyricEvent) event]),
        sections = List.unmodifiable([
          for (final event in events) if (event is PlaySectionEvent) event
        ]);

  /// 全部事件，按时刻升序；同一时刻按 section→lyric→strum 定序。
  /// 示范试听（工单 11）按序遍历它预定发声。
  final List<PlayEvent> events;

  /// 按类视图：仅扫弦 / 仅歌词行 / 仅段落标记，各自按时刻升序。
  /// 练习状态查询（practice_state.dart）对它们做二分查找。
  final List<PlayStrumEvent> strums;
  final List<PlayLyricEvent> lyrics;
  final List<PlaySectionEvent> sections;

  /// 有效拍长（毫秒，四分）＝ 60000/BPM/变速比。节拍网格随变速伸缩，
  /// 节拍声与视觉拍都从它推导（复用 core/audio 的 beatAt/BeatScheduler）。
  final double periodMs;

  /// 全曲拍数＝小节×4。节拍声的 [BeatScheduler.totalBeats] 与曲末判定共用。
  final int totalBeats;

  /// 名义曲长（最后一小节奏完）。曲末判定认节拍网格（见
  /// practiceStateAt），与名义曲长至差一次四舍五入。
  Duration get totalDuration =>
      Duration(milliseconds: (totalBeats * periodMs).round());
}

/// 时间轴编译器：弹唱谱+节奏型+BPM（+变速）→ [PlayTimeline]。
///
/// **小节分配约定**（文本谱没有小节线，这是编译的唯一裁量处）：
/// - 每个和弦记号独占一小节——行内 k 个和弦记号，该行占 k 小节，
///   第 k 个记号从第 k 小节起生效；
/// - 没有和弦记号的行占一小节，延续当前和弦；
/// - 小节内扫弦完全由节奏型决定：节奏型每小节循环一遍，槽位即
///   小节内的八分位置，扫弦携带该小节的和弦。
PlayTimeline compileTimeline({
  required StrumChart chart,
  required StrumPattern pattern,
  required double bpm,
  double speed = 1.0,
}) {
  // 入参校验抛 ArgumentError(release 也生效,不靠 assert):非正/非有限
  // 的 BPM 与变速比会让有效拍长爆炸(负值倒轴、0/NaN 取整炸、溢出塌缩)。
  requirePositiveFinite(bpm, 'bpm', 'BPM');
  requirePositiveFinite(speed, 'speed', '变速比（产品范围 50%–100%）');
  final periodMs = 60000 / bpm / speed;
  if (periodMs.isInfinite) {
    throw ArgumentError.value(periodMs, 'periodMs', '有效拍长非有限（BPM×变速比过小）');
  }
  final slotMs = periodMs / 2;

  // 逐事件四舍五入，不累加（与本文件头注释的定型语义一致）。
  Duration slotTime(int globalSlot) =>
      Duration(milliseconds: (globalSlot * slotMs).round());

  final events = <PlayEvent>[];
  final strokes = pattern.strokes;

  var bar = 0;
  String? currentChord;
  for (var si = 0; si < chart.sections.length; si++) {
    final section = chart.sections[si];
    events.add(PlaySectionEvent(
      time: slotTime(bar * eighthsPerBar),
      sectionIndex: si,
      section: section,
    ));

    for (var li = 0; li < section.lines.length; li++) {
      final line = section.lines[li];
      events.add(PlayLyricEvent(
        time: slotTime(bar * eighthsPerBar),
        sectionIndex: si,
        lineIndex: li,
        line: line,
      ));

      for (final barChord in _lineBarChords(line, currentChord)) {
        currentChord = barChord;
        for (final (slot, stroke) in strokes) {
          events.add(PlayStrumEvent(
            time: slotTime(bar * eighthsPerBar + slot),
            barIndex: bar,
            slotInBar: slot,
            direction: stroke,
            chord: currentChord,
          ));
        }
        bar++;
      }
    }
  }

  return PlayTimeline._(events, periodMs: periodMs, totalBeats: bar * beatsPerBar);
}

/// 行→小节分配（**编译的唯一裁量处**）：行内 k 个和弦记号独占 k 小节
/// （第 i 小节生效第 i 个记号的和弦），无和弦记号的行占一小节、延续
/// [currentChord]。返回本行逐小节的生效和弦（长度即该行小节数）。
List<String?> _lineBarChords(StrumLine line, String? currentChord) =>
    line.chords.isEmpty
        ? [currentChord]
        : [for (final mark in line.chords) mark.name];
