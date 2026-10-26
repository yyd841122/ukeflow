import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/import/score_ir.dart';
import 'package:ukeflow/core/model/chord.dart';
import 'package:ukeflow/core/model/tab_chart.dart';

/// 工单 42 测试夹具:识谱源(ScoreIR)的深比较器 + 手编小 IR。
/// 比较器是「逐位相等」总闸的量尺——逐字段展开,不搭 toString 的便车
/// (模型无 ==,打印对不上时原因指不出坏字段)。

/// 逐音逐位:弦/品/拍位/歌词四元组完全一致(拍位 double 同位型)。
void expectTabNotesBitwiseEqual(
  List<TabNote> actual,
  List<TabNote> expected,
  String label,
) {
  expect(actual.length, expected.length,
      reason: '$label:音数不一致(实际 ${actual.length} / 期望 ${expected.length})');
  for (var i = 0; i < expected.length; i++) {
    final a = actual[i];
    final e = expected[i];
    expect(a.string, e.string, reason: '$label:第 $i 音弦号');
    expect(a.fret, e.fret, reason: '$label:第 $i 音品位');
    expect(a.beat, e.beat, reason: '$label:第 $i 音拍位(@${e.beat})');
    expect(a.lyric, e.lyric, reason: '$label:第 $i 音歌词(@${e.beat})');
  }
}

void expectFingeringEqual(ChordFingering actual, ChordFingering expected, String where) {
  expect(actual.frets, expected.frets, reason: '$where:frets');
  expect(actual.fingers, expected.fingers, reason: '$where:fingers');
  expect(actual.baseFret, expected.baseFret, reason: '$where:baseFret');
  expect(actual.barres, expected.barres, reason: '$where:barres');
  expect(actual.midi, expected.midi, reason: '$where:midi');
}

/// 组合定义逐字段(三源绑定/偏移/调号/五类事件表全量)。
void expectScoreSheetDefEqual(ScoreSheetDef actual, ScoreSheetDef expected) {
  expect(actual.id, expected.id, reason: 'def.id');
  expect(actual.title, expected.title, reason: 'def.title');
  expect(actual.artist, expected.artist, reason: 'def.artist');
  expect(actual.tabChartId, expected.tabChartId, reason: 'def.tabChartId');
  expect(actual.melodyChartId, expected.melodyChartId, reason: 'def.melodyChartId');
  expect(actual.melodyAlignBeats, expected.melodyAlignBeats, reason: 'def.melodyAlignBeats');
  expect(actual.keySignature, expected.keySignature, reason: 'def.keySignature');
  expect(actual.chords.length, expected.chords.length, reason: 'def.chords 数');
  for (var i = 0; i < expected.chords.length; i++) {
    expect(actual.chords[i].beat, expected.chords[i].beat, reason: 'chord[$i] beat');
    expect(actual.chords[i].label, expected.chords[i].label, reason: 'chord[$i] label');
    expectFingeringEqual(
        actual.chords[i].fingering, expected.chords[i].fingering, 'chord[$i]');
  }
  expect(actual.strums.length, expected.strums.length, reason: 'def.strums 数');
  for (var i = 0; i < expected.strums.length; i++) {
    expect(actual.strums[i].beat, expected.strums[i].beat, reason: 'strum[$i] beat');
    expect(actual.strums[i].kind, expected.strums[i].kind, reason: 'strum[$i] kind');
  }
  expect(actual.rests.length, expected.rests.length, reason: 'def.rests 数');
  for (var i = 0; i < expected.rests.length; i++) {
    expect(actual.rests[i].beat, expected.rests[i].beat, reason: 'rest[$i] beat');
    expect(actual.rests[i].beats, expected.rests[i].beats, reason: 'rest[$i] beats');
  }
  expect(actual.tremolos.length, expected.tremolos.length, reason: 'def.tremolos 数');
  for (var i = 0; i < expected.tremolos.length; i++) {
    expect(actual.tremolos[i].beat, expected.tremolos[i].beat, reason: 'tremolo[$i] beat');
  }
  expect(actual.slides.length, expected.slides.length, reason: 'def.slides 数');
  for (var i = 0; i < expected.slides.length; i++) {
    expect(actual.slides[i].fromBeat, expected.slides[i].fromBeat, reason: 'slide[$i] fromBeat');
    expect(actual.slides[i].toBeat, expected.slides[i].toBeat, reason: 'slide[$i] toBeat');
  }
}

void expectVoiceEqual(ScoreIrVoice actual, ScoreIrVoice expected, String which) {
  expect(actual.notes.length, expected.notes.length,
      reason: '$which:音数不一致');
  for (var i = 0; i < expected.notes.length; i++) {
    final a = actual.notes[i];
    final e = expected.notes[i];
    expect(a.beat, e.beat, reason: '$which note[$i] beat');
    expect(a.durationBeats, e.durationBeats, reason: '$which note[$i] durationBeats');
    expect(a.string, e.string, reason: '$which note[$i] string');
    expect(a.fret, e.fret, reason: '$which note[$i] fret');
    expect(a.midi, e.midi, reason: '$which note[$i] midi');
    expect(a.lyric, e.lyric, reason: '$which note[$i] lyric');
    expect(a.evidence, e.evidence, reason: '$which note[$i] evidence');
  }
  expect(actual.rests.length, expected.rests.length, reason: '$which:声部休止数');
  for (var i = 0; i < expected.rests.length; i++) {
    expect(actual.rests[i].beat, expected.rests[i].beat, reason: '$which rest[$i] beat');
    expect(actual.rests[i].beats, expected.rests[i].beats, reason: '$which rest[$i] beats');
    expect(actual.rests[i].evidence, expected.rests[i].evidence,
        reason: '$which rest[$i] evidence');
  }
}

/// 识谱源全量深比较。
void expectScoreIrEqual(ScoreIr actual, ScoreIr expected) {
  expect(actual.schemaVersion, expected.schemaVersion, reason: 'schemaVersion');
  expect(actual.id, expected.id, reason: 'id');
  expect(actual.title, expected.title, reason: 'title');
  expect(actual.artist, expected.artist, reason: 'artist');
  expect(actual.meter.beatsPerMeasure, expected.meter.beatsPerMeasure,
      reason: 'meter.beatsPerMeasure');
  expect(actual.meter.beatUnit, expected.meter.beatUnit, reason: 'meter.beatUnit');
  expect(actual.tempoMap.length, expected.tempoMap.length, reason: 'tempoMap 数');
  for (var i = 0; i < expected.tempoMap.length; i++) {
    expect(actual.tempoMap[i].beat, expected.tempoMap[i].beat, reason: 'tempoMap[$i] beat');
    expect(actual.tempoMap[i].bpm, expected.tempoMap[i].bpm, reason: 'tempoMap[$i] bpm');
  }
  expect(actual.keyMap.length, expected.keyMap.length, reason: 'keyMap 数');
  for (var i = 0; i < expected.keyMap.length; i++) {
    expect(actual.keyMap[i].beat, expected.keyMap[i].beat, reason: 'keyMap[$i] beat');
    expect(actual.keyMap[i].key, expected.keyMap[i].key, reason: 'keyMap[$i] key');
  }
  expect(actual.measures.length, expected.measures.length, reason: 'measures 数');
  for (var i = 0; i < expected.measures.length; i++) {
    expect(actual.measures[i].number, expected.measures[i].number,
        reason: 'measure[$i] number');
    expect(actual.measures[i].startBeat, expected.measures[i].startBeat,
        reason: 'measure[$i] startBeat');
  }
  expect(actual.melodyAlignBeats, expected.melodyAlignBeats, reason: 'melodyAlignBeats');
  expect(actual.tabChartId, expected.tabChartId, reason: 'tabChartId');
  expect(actual.melodyChartId, expected.melodyChartId, reason: 'melodyChartId');
  expectVoiceEqual(actual.melody, expected.melody, 'melody');
  expectVoiceEqual(actual.accompaniment, expected.accompaniment, 'accompaniment');
  expect(actual.rests.length, expected.rests.length, reason: '显示休止数');
  for (var i = 0; i < expected.rests.length; i++) {
    expect(actual.rests[i].beat, expected.rests[i].beat, reason: '显示休止[$i] beat');
    expect(actual.rests[i].beats, expected.rests[i].beats, reason: '显示休止[$i] beats');
    expect(actual.rests[i].evidence, expected.rests[i].evidence, reason: '显示休止[$i] evidence');
  }
  expect(actual.slides.length, expected.slides.length, reason: 'slides 数');
  for (var i = 0; i < expected.slides.length; i++) {
    expect(actual.slides[i].fromBeat, expected.slides[i].fromBeat, reason: 'slide[$i] fromBeat');
    expect(actual.slides[i].toBeat, expected.slides[i].toBeat, reason: 'slide[$i] toBeat');
  }
  expect(actual.tremolos.length, expected.tremolos.length, reason: 'tremolos 数');
  for (var i = 0; i < expected.tremolos.length; i++) {
    expect(actual.tremolos[i].beat, expected.tremolos[i].beat, reason: 'tremolo[$i] beat');
  }
  expect(actual.strums.length, expected.strums.length, reason: 'strums 数');
  for (var i = 0; i < expected.strums.length; i++) {
    expect(actual.strums[i].beat, expected.strums[i].beat, reason: 'strum[$i] beat');
    expect(actual.strums[i].kind, expected.strums[i].kind, reason: 'strum[$i] kind');
  }
  expect(actual.chordAnchors.length, expected.chordAnchors.length, reason: 'chordAnchors 数');
  for (var i = 0; i < expected.chordAnchors.length; i++) {
    expect(actual.chordAnchors[i].beat, expected.chordAnchors[i].beat,
        reason: 'chordAnchor[$i] beat');
    expect(actual.chordAnchors[i].label, expected.chordAnchors[i].label,
        reason: 'chordAnchor[$i] label');
    expectFingeringEqual(
        actual.chordAnchors[i].fingering, expected.chordAnchors[i].fingering,
        'chordAnchor[$i]');
  }
  expect(
    [for (final u in actual.unsupportedSymbols) u.kind],
    [for (final u in expected.unsupportedSymbols) u.kind],
    reason: 'unsupportedSymbols kinds',
  );
  for (var i = 0; i < expected.unsupportedSymbols.length; i++) {
    expect(actual.unsupportedSymbols[i].kind, expected.unsupportedSymbols[i].kind,
        reason: 'unsupported[$i] kind');
    expect(actual.unsupportedSymbols[i].beat, expected.unsupportedSymbols[i].beat,
        reason: 'unsupported[$i] beat');
  }
  expect(actual.review?.reviewedAt, expected.review?.reviewedAt, reason: 'review');
}

/// 手编小识谱源(2 小节 4/4,**拍长闭合合法**:旋律占小节 1,伴奏占
/// 小节 2):旋律 3 音 +1 声部休止,伴奏 2 音 +1 声部休止;显示休止/
/// 滑音/震音/扫弦/和弦锚各一——JSON 序列化与校验器变异测试的基线。
ScoreIr tinyScoreIr() => ScoreIr(
      schemaVersion: scoreIrSchemaVersion,
      id: 'test-tiny-solo',
      title: '测试小谱',
      artist: '测试者',
      meter: const ScoreIrMeter(beatsPerMeasure: 4, beatUnit: 4),
      tempoMap: const [ScoreIrTempoChange(beat: 0, bpm: 78)],
      keyMap: const [ScoreIrKeyChange(beat: 0, key: '1=E')],
      measures: const [
        ScoreIrMeasure(number: 1, startBeat: 0),
        ScoreIrMeasure(number: 2, startBeat: 4),
      ],
      melodyAlignBeats: 4,
      tabChartId: 'test-tiny-solo',
      melodyChartId: 'test-tiny-melody',
      melody: const ScoreIrVoice(
        notes: [
          ScoreIrNote(
            beat: 0,
            durationBeats: 1,
            string: 2,
            fret: 3,
            midi: 67,
            lyric: '你',
            evidence: ScoreIrEvidence(
              page: 1,
              bbox: [12, 34, 56, 78],
              source: 'p1-melody-m01.png',
              confidence: 0.97,
            ),
          ),
          ScoreIrNote(beat: 1, durationBeats: 0.5, string: 2, fret: 0, midi: 64),
          ScoreIrNote(beat: 1.5, durationBeats: 0.5, string: 1, fret: 0, midi: 69),
        ],
        rests: [ScoreIrRest(beat: 2, beats: 2)],
      ),
      accompaniment: const ScoreIrVoice(
        notes: [
          ScoreIrNote(beat: 4, durationBeats: 1, string: 4, fret: 4, midi: 71),
          ScoreIrNote(beat: 5, durationBeats: 0.5, string: 3, fret: 4, midi: 64),
        ],
        rests: [ScoreIrRest(beat: 5.5, beats: 2.5)],
      ),
      rests: const [ScoreIrRestEvent(beat: 7, beats: 0.5)],
      slides: const [ScoreIrSlideEvent(fromBeat: 4, toBeat: 5)],
      tremolos: const [ScoreIrTremoloEvent(beat: 6)],
      strums: const [
        ScoreIrStrumEvent(beat: 4, kind: ScoreStrumKind.roll),
      ],
      chordAnchors: const [
        ScoreIrChordAnchor(
          beat: 4,
          label: 'E',
          fingering: ChordFingering(
            frets: [4, 4, 4, 2],
            fingers: [0, 0, 0, 0],
            baseFret: 1,
            barres: [],
          ),
        ),
      ],
      unsupportedSymbols: const [
        ScoreIrUnsupportedSymbol(
          kind: 'hammer-on',
          beat: 5.5,
          note: '印张弧线,校对台须先消解',
        ),
      ],
      review: const ScoreIrReview(reviewedAt: '2026-10-26T10:00:00.000'),
    );

/// 校验器基线:[tinyScoreIr] 去掉不支持记号——合法可物化的最小源,
/// 校验测试在此之上做单字段变异(每次恰好多出/消掉一条阻塞错误)。
ScoreIr validTinyIr() {
  final t = tinyScoreIr();
  return ScoreIr(
    schemaVersion: t.schemaVersion,
    id: t.id,
    title: t.title,
    artist: t.artist,
    meter: t.meter,
    tempoMap: t.tempoMap,
    keyMap: t.keyMap,
    measures: t.measures,
    melodyAlignBeats: t.melodyAlignBeats,
    tabChartId: t.tabChartId,
    melodyChartId: t.melodyChartId,
    melody: t.melody,
    accompaniment: t.accompaniment,
    rests: t.rests,
    slides: t.slides,
    tremolos: t.tremolos,
    strums: t.strums,
    chordAnchors: t.chordAnchors,
    unsupportedSymbols: const [],
    review: t.review,
  );
}
