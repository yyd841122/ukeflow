import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/import/score_ir.dart';
import 'package:ukeflow/core/import/score_ir_validator.dart';
import 'package:ukeflow/core/model/chord.dart';

import '../../helpers/score_ir_fixtures.dart';

/// 导入校验缝(工单 42,spec 测试缝⑥):识谱源 → 逐条阻塞错误(人话)。
/// 合法基线必须零错误;每条规则用单字段变异各证「会拦」,错误消息按
/// 关键词点名(工单 44 导入页逐条列出吃的就是这些串)。
void main() {
  final good = validateScoreIr(validTinyIr());
  test('合法基线(闭合小谱)零阻塞', () {
    expect(good, isEmpty);
  });

  group('骨架与元信息', () {
    test('schemaVersion 不符', () {
      final ir = tinyScoreIr();
      final bad = ScoreIr(
        schemaVersion: 99,
        id: ir.id,
        title: ir.title,
        meter: ir.meter,
        tempoMap: ir.tempoMap,
        keyMap: ir.keyMap,
        measures: ir.measures,
        melodyAlignBeats: ir.melodyAlignBeats,
        tabChartId: ir.tabChartId,
        melodyChartId: ir.melodyChartId,
        melody: ir.melody,
        accompaniment: ir.accompaniment,
      );
      expect(bad.schemaVersion, isNot(scoreIrSchemaVersion));
      expect(
        validateScoreIr(bad).any((e) => e.contains('schemaVersion')),
        isTrue,
        reason: '须点名 schemaVersion',
      );
    });

    test('meter 每小节拍数非正', () {
      expect(
        validateScoreIr(mutate(meter: const ScoreIrMeter(beatsPerMeasure: 0, beatUnit: 4))),
        anyElement(contains('拍号')),
      );
    });

    test('tempoMap 为空 / bpm 非正 / 首条不在拍 0', () {
      expect(validateScoreIr(mutate(tempoMap: const [])), anyElement(contains('tempoMap')));
      expect(
        validateScoreIr(mutate(tempoMap: const [ScoreIrTempoChange(beat: 0, bpm: 0)])),
        anyElement(contains('bpm')),
      );
      expect(
        validateScoreIr(mutate(tempoMap: const [ScoreIrTempoChange(beat: 2, bpm: 78)])),
        anyElement(contains('拍 0')),
      );
    });

    test('keyMap 为空 / 调号空白 / 首条不在拍 0', () {
      expect(validateScoreIr(mutate(keyMap: const [])), anyElement(contains('keyMap')));
      expect(
        validateScoreIr(mutate(keyMap: const [ScoreIrKeyChange(beat: 0, key: ' ')])),
        anyElement(contains('调号')),
      );
      expect(
        validateScoreIr(mutate(keyMap: const [ScoreIrKeyChange(beat: 1, key: '1=E')])),
        anyElement(contains('拍 0')),
      );
    });

    test('多条变速/转调阻塞(v1 物化单速单调号,多条必静默丢)', () {
      expect(
        validateScoreIr(mutate(tempoMap: const [
          ScoreIrTempoChange(beat: 0, bpm: 78),
          ScoreIrTempoChange(beat: 8, bpm: 90),
        ])),
        anyElement(contains('变速')),
      );
      expect(
        validateScoreIr(mutate(keyMap: const [
          ScoreIrKeyChange(beat: 0, key: '1=E'),
          ScoreIrKeyChange(beat: 8, key: '1=A'),
        ])),
        anyElement(contains('静默丢')),
      );
    });

    test('小节骨架:number 不连续 / startBeat 与拍号×拍数不符', () {
      expect(
        validateScoreIr(mutate(measures: const [
          ScoreIrMeasure(number: 1, startBeat: 0),
          ScoreIrMeasure(number: 3, startBeat: 4),
        ])),
        anyElement(contains('小节号')),
      );
      expect(
        validateScoreIr(mutate(measures: const [
          ScoreIrMeasure(number: 1, startBeat: 0),
          ScoreIrMeasure(number: 2, startBeat: 5),
        ])),
        anyElement(contains('startBeat')),
      );
    });
  });

  group('声部逐音', () {
    test('旋律声部无音 / 弦号越界 / 品位为负 / 音域越界', () {
      final noMelody = validTinyIr();
      expect(
        validateScoreIr(ScoreIr(
          schemaVersion: noMelody.schemaVersion,
          id: noMelody.id,
          title: noMelody.title,
          meter: noMelody.meter,
          tempoMap: noMelody.tempoMap,
          keyMap: noMelody.keyMap,
          measures: noMelody.measures,
          melodyAlignBeats: noMelody.melodyAlignBeats,
          tabChartId: noMelody.tabChartId,
          melodyChartId: noMelody.melodyChartId,
          melody: const ScoreIrVoice(notes: []),
          accompaniment: noMelody.accompaniment,
        )),
        anyElement(contains('旋律')),
      );
      expect(
        validateScoreIr(mutateNote(const [], string: 5)),
        anyElement(contains('弦号')),
      );
      expect(
        validateScoreIr(mutateNote(const [], fret: -1)),
        anyElement(contains('品位')),
      );
      expect(
        validateScoreIr(mutateNote(const [], fret: scoreIrMaxFret + 1)),
        anyElement(contains('音域')),
      );
    });

    test('冗余 midi 与弦品换算不一致', () {
      expect(
        validateScoreIr(mutateNote(const [], midi: 60)),
        anyElement(contains('midi')),
      );
    });

    test('拍位为负 / 时值非正 / 歌词空白', () {
      expect(
        validateScoreIr(mutateNote(const [], beat: -1)),
        anyElement(contains('拍位')),
      );
      expect(
        validateScoreIr(mutateNote(const [], durationBeats: 0)),
        anyElement(contains('时值')),
      );
      expect(
        validateScoreIr(mutateNote(const [], lyric: ' ')),
        anyElement(contains('歌词')),
      );
    });

    test('同弦同刻冲突 / 录入序错乱', () {
      expect(
        validateScoreIr(mutateNote(const [ScoreIrNote(beat: 0, durationBeats: 0.5, string: 2, fret: 3, midi: 67)])),
        anyElement(contains('同弦同刻')),
      );
      expect(
        validateScoreIr(mutateNote(const [], beat: 2, keepFirst: true)),
        anyElement(contains('序')),
      );
    });
  });

  group('每声部每小节拍长闭合', () {
    test('小节内空洞(去休止不补)不闭合', () {
      // 旋律小节1:0(1)+1(0.5)+1.5(0.5)+休2×2 = 4;拿掉休止 = 差 2 拍。
      expect(
        validateScoreIr(mutate(melody: const ScoreIrVoice(notes: [
          ScoreIrNote(beat: 0, durationBeats: 1, string: 2, fret: 3, midi: 67),
          ScoreIrNote(beat: 1, durationBeats: 0.5, string: 2, fret: 0, midi: 64),
          ScoreIrNote(beat: 1.5, durationBeats: 0.5, string: 1, fret: 0, midi: 69),
        ]))),
        anyElement(contains('闭合')),
      );
    });

    test('事件重叠 / 跨小节溢出 / 窗内整小节空白', () {
      expect(
        validateScoreIr(mutate(melodyRests: const [ScoreIrRest(beat: 0.5, beats: 2)])),
        anyElement(contains('重叠')),
      );
      expect(
        validateScoreIr(mutateNote(const [], durationBeats: 5)),
        anyElement(contains('跨小节')),
      );
      // 伴奏声部中途断档:小节 1、3 有音,小节 2 整小节无事件。
      const hole = ScoreIrVoice(notes: [
        ScoreIrNote(beat: 0, durationBeats: 4, string: 4, fret: 4, midi: 71),
        ScoreIrNote(beat: 8, durationBeats: 4, string: 4, fret: 4, midi: 71),
      ]);
      expect(
        validateScoreIr(mutate(accompaniment: hole)),
        anyElement(contains('第 2 小节')),
      );
    });

    test('旋律层整体越过小节骨架(对齐后出界)', () {
      final ir = validTinyIr();
      final far = ScoreIr(
        schemaVersion: ir.schemaVersion,
        id: ir.id,
        title: ir.title,
        meter: ir.meter,
        tempoMap: ir.tempoMap,
        keyMap: ir.keyMap,
        measures: ir.measures,
        melodyAlignBeats: 40,
        tabChartId: ir.tabChartId,
        melodyChartId: ir.melodyChartId,
        melody: ir.melody,
        accompaniment: ir.accompaniment,
      );
      expect(validateScoreIr(far), anyElement(contains('小节骨架')));
    });
  });

  group('主轴事件表', () {
    test('和弦锚:拍位不升 / 指形结构坏 / 拍位出骨架', () {
      expect(
        validateScoreIr(mutate(chordAnchors: [
          validTinyIr().chordAnchors.first,
          validTinyIr().chordAnchors.first,
        ])),
        anyElement(contains('和弦锚')),
      );
      expect(
        validateScoreIr(mutate(chordAnchors: [
          ScoreIrChordAnchor(
            beat: 4,
            label: 'E',
            fingering: ChordFingering(
              frets: [4, 4],
              fingers: [0, 0, 0, 0],
              baseFret: 1,
              barres: [],
            ),
          ),
        ])),
        anyElement(contains('frets')),
      );
      expect(
        validateScoreIr(mutate(chordAnchors: [
          ScoreIrChordAnchor(
            beat: 40,
            label: 'E',
            fingering: validTinyIr().chordAnchors.first.fingering,
          ),
        ])),
        anyElement(contains('小节骨架')),
      );
    });

    test('扫弦拍位不升 / 滑音端点无音 / 显示休止拍位非正', () {
      expect(
        validateScoreIr(mutate(strums: const [
          ScoreIrStrumEvent(beat: 6, kind: ScoreStrumKind.roll),
          ScoreIrStrumEvent(beat: 4, kind: ScoreStrumKind.roll),
        ])),
        anyElement(contains('升序')),
      );
      expect(
        validateScoreIr(mutate(slides: const [ScoreIrSlideEvent(fromBeat: 4, toBeat: 4.5)])),
        anyElement(contains('滑音')),
      );
      expect(
        validateScoreIr(mutate(rests: const [ScoreIrRestEvent(beat: 7, beats: 0)])),
        anyElement(contains('休止')),
      );
    });

    test('不支持记号逐条阻塞,点名 kind', () {
      final errors = validateScoreIr(tinyScoreIr());
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('hammer-on') && e.contains('不支持')), isTrue);
    });
  });
}

/// 单字段变异帮手:基线之上换掉一个部件。
ScoreIr mutate({
  ScoreIrMeter? meter,
  List<ScoreIrTempoChange>? tempoMap,
  List<ScoreIrKeyChange>? keyMap,
  List<ScoreIrMeasure>? measures,
  ScoreIrVoice? melody,
  List<ScoreIrRest>? melodyRests,
  ScoreIrVoice? accompaniment,
  List<ScoreIrRestEvent>? rests,
  List<ScoreIrSlideEvent>? slides,
  List<ScoreIrTremoloEvent>? tremolos,
  List<ScoreIrStrumEvent>? strums,
  List<ScoreIrChordAnchor>? chordAnchors,
}) {
  final base = validTinyIr();
  return ScoreIr(
    schemaVersion: base.schemaVersion,
    id: base.id,
    title: base.title,
    artist: base.artist,
    meter: meter ?? base.meter,
    tempoMap: tempoMap ?? base.tempoMap,
    keyMap: keyMap ?? base.keyMap,
    measures: measures ?? base.measures,
    melodyAlignBeats: base.melodyAlignBeats,
    tabChartId: base.tabChartId,
    melodyChartId: base.melodyChartId,
    melody: melody ?? (melodyRests == null ? base.melody
        : ScoreIrVoice(notes: base.melody.notes, rests: melodyRests)),
    accompaniment: accompaniment ?? base.accompaniment,
    rests: rests ?? base.rests,
    slides: slides ?? base.slides,
    tremolos: tremolos ?? base.tremolos,
    strums: strums ?? base.strums,
    chordAnchors: chordAnchors ?? base.chordAnchors,
  );
}

/// 旋律首音(或叠加音)变异:换弦/品/midi/拍位/时值/歌词。
/// [keepFirst] = 保留原首音并把变异值落到第二个音(证录入序错乱);
/// [extra] 非空 = 在首音前插入(证同弦同刻冲突)。
ScoreIr mutateNote(
  List<ScoreIrNote> extra, {
  int? string,
  int? fret,
  int? midi,
  double? beat,
  double? durationBeats,
  String? lyric,
  bool keepFirst = false,
}) {
  final base = validTinyIr();
  final first = base.melody.notes.first;
  final patched = ScoreIrNote(
    beat: beat ?? first.beat,
    durationBeats: durationBeats ?? first.durationBeats,
    string: string ?? first.string,
    fret: fret ?? first.fret,
    midi: midi ?? first.midi,
    lyric: lyric ?? first.lyric,
  );
  final notes = keepFirst
      ? [first, patched, ...base.melody.notes.skip(1)]
      : [...extra, patched, ...base.melody.notes.skip(1)];
  return ScoreIr(
    schemaVersion: base.schemaVersion,
    id: base.id,
    title: base.title,
    artist: base.artist,
    meter: base.meter,
    tempoMap: base.tempoMap,
    keyMap: base.keyMap,
    measures: base.measures,
    melodyAlignBeats: base.melodyAlignBeats,
    tabChartId: base.tabChartId,
    melodyChartId: base.melodyChartId,
    melody: ScoreIrVoice(notes: notes, rests: base.melody.rests),
    accompaniment: base.accompaniment,
    rests: base.rests,
    slides: base.slides,
    tremolos: base.tremolos,
    strums: base.strums,
    chordAnchors: base.chordAnchors,
  );
}
