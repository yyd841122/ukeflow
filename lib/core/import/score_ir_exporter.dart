/// 识谱源导出器(工单 42):既有组合结构(ScoreSheetDef + 双 TabChart)→
/// ScoreIr。**金标准方向的纯函数**——内置金标准(爱你不是两三天)经
/// 「导出 → 物化」与原常量逐位相等(总闸,测试缝⑤);工作台的 builtin
/// 参考 JSON(工单 51 金标准对照模式)也由本导出器生成。
///
/// 时值推导约定(印张节奏符号不可从拍位唯一恢复,内置数据本无时值):
/// - 逐音 `durationBeats` = 距下一音的 gap,小节末音收到小节线——与
///   谱面简谱推导(deriveNumberedNotes「时值 = 距下音 gap」)同规;
/// - 声部休止 = 音间气口簿记:小节内首音前的静默与整小节静默落声部
///   休止,音间静默由前一音的时值表达(不另立休止)。
/// 导入源不受此约定约束:工作台给的 durationBeats/休止照录,校验器按
/// 「每声部每小节拍长闭合」核对。证据恒 null(内置数据无识别出处),
/// review 缺省(人工对照记录在案,无可填时刻)。
library;

import 'dart:math' as math;

import '../audio/beat_scheduling.dart' show beatsPerBar;
import '../chart/score_sheet_defs.dart';
import '../model/tab_chart.dart';
import '../model/uke_string.dart';
import 'score_ir.dart';

/// 组合定义 + 双层谱 → 识谱源。[melodyChart] 拍位为旋律层本地拍位
/// (与 TabChart 数据同域,主轴定位由 def.melodyAlignBeats 记录)。
ScoreIr exportScoreIr({
  required ScoreSheetDef def,
  required TabChart tabChart,
  required TabChart melodyChart,
}) {
  if (tabChart.notes.isEmpty || melodyChart.notes.isEmpty) {
    throw ArgumentError('空谱不导出(两声部都必须有音)');
  }
  final meterBeats = beatsPerBar.toDouble();
  // 主轴小节骨架:全事件最晚拍(旋律 + 对齐偏移)收进骨架。
  var maxBeat = 0.0;
  for (final n in tabChart.notes) {
    maxBeat = math.max(maxBeat, n.beat);
  }
  for (final n in melodyChart.notes) {
    maxBeat = math.max(maxBeat, n.beat + def.melodyAlignBeats);
  }
  for (final c in def.chords) {
    maxBeat = math.max(maxBeat, c.beat);
  }
  for (final s in def.strums) {
    maxBeat = math.max(maxBeat, s.beat);
  }
  for (final r in def.rests) {
    maxBeat = math.max(maxBeat, r.beat);
  }
  for (final t in def.tremolos) {
    maxBeat = math.max(maxBeat, t.beat);
  }
  for (final s in def.slides) {
    maxBeat = math.max(maxBeat, s.toBeat);
  }
  final measureCount = _measureCountOf(maxBeat, meterBeats);

  return ScoreIr(
    schemaVersion: scoreIrSchemaVersion,
    id: def.id,
    title: def.title,
    artist: def.artist,
    meter: ScoreIrMeter(beatsPerMeasure: beatsPerBar, beatUnit: 4),
    tempoMap: [ScoreIrTempoChange(beat: 0, bpm: tabChart.tempo)],
    keyMap: [ScoreIrKeyChange(beat: 0, key: def.keySignature)],
    measures: [
      for (var m = 1; m <= measureCount; m++)
        ScoreIrMeasure(number: m, startBeat: (m - 1) * meterBeats),
    ],
    melodyAlignBeats: def.melodyAlignBeats,
    tabChartId: def.tabChartId,
    melodyChartId: def.melodyChartId,
    melody: _tileVoice(melodyChart.notes),
    accompaniment: _tileVoice(tabChart.notes),
    rests: [
      for (final r in def.rests)
        ScoreIrRestEvent(beat: r.beat, beats: r.beats),
    ],
    slides: [
      for (final s in def.slides)
        ScoreIrSlideEvent(fromBeat: s.fromBeat, toBeat: s.toBeat),
    ],
    tremolos: [for (final t in def.tremolos) ScoreIrTremoloEvent(beat: t.beat)],
    strums: [
      for (final s in def.strums)
        ScoreIrStrumEvent(beat: s.beat, kind: s.kind),
    ],
    chordAnchors: [
      for (final c in def.chords)
        ScoreIrChordAnchor(
          beat: c.beat,
          label: c.label,
          fingering: c.fingering,
        ),
    ],
  );
}

/// 声部切片:逐音时值 = 距下音 gap(同拍堆同一时值槽,小节末音收到
/// 小节线),静默落声部休止(小节首音前 / 整小节;音间静默由前一音
/// 时值表达)。输出序 = (beat, 录入序) 时序视图。
ScoreIrVoice _tileVoice(List<TabNote> rawNotes) {
  final sorted = sortedTabNotes(rawNotes);
  final meter = beatsPerBar.toDouble();
  final measureCount = _measureCountOf(sorted.last.beat, meter);
  final notes = <ScoreIrNote>[];
  final rests = <ScoreIrRest>[];
  var next = 0;
  for (var m = 0; m < measureCount; m++) {
    final ms = m * meter;
    final me = ms + meter;
    final start = next;
    while (next < sorted.length && sorted[next].beat < me) {
      next++;
    }
    final inMeasure = sorted.sublist(start, next);
    if (inMeasure.isEmpty) {
      rests.add(ScoreIrRest(beat: ms, beats: meter));
      continue;
    }
    for (var i = 0; i < inMeasure.length; i++) {
      final n = inMeasure[i];
      // 小节内首音前的静默落声部休止;音间静默由前一音时值表达(不另立)。
      if (i == 0 && n.beat > ms) {
        rests.add(ScoreIrRest(beat: ms, beats: n.beat - ms));
      }
      // 时值 = 距下一**不同拍**的 gap(同拍堆是同一时值槽,堆内成员
      // 同值),小节末音收到小节线。
      var nextBeat = me;
      for (var j = i + 1; j < inMeasure.length; j++) {
        if (inMeasure[j].beat > n.beat) {
          nextBeat = inMeasure[j].beat;
          break;
        }
      }
      notes.add(ScoreIrNote(
        beat: n.beat,
        durationBeats: nextBeat - n.beat,
        string: n.string,
        fret: n.fret,
        midi: UkeString.byNumber(n.string).midi + n.fret,
        lyric: n.lyric,
      ));
    }
  }
  return ScoreIrVoice(notes: notes, rests: rests);
}

/// 最晚拍 → 小节数:拍恰落小节线归入下一小节(floor+1),不用 ceil——
/// ceil 会把正好压线的末音排到骨架之外(静默丢,评审 2026-10-26)。
int _measureCountOf(double lastBeat, double meterBeats) =>
    (lastBeat ~/ meterBeats) + 1;
