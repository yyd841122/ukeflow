import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/score/reference_score.dart';

/// 一手数据回归闸（codex 真机核验报告为基准，非本实现输出）：
/// 51 小节、317 非空事件、557 音、152.8536585 秒、首声 2.25 秒、
/// 调弦 [69,64,60,67]、页速 80、末段 82、13 延音、4 自然泛音。
///
/// 任何一条失守都说明转换器改坏了——先修代码，不许改基准。
void main() {
  final raw = File('assets/scores/sky-city-guistudy.json').readAsStringSync();
  final source = jsonDecode(raw);
  late ReferenceScore score;

  setUpAll(() {
    score = buildReferenceScore(source, pageTempoBpm: 80);
  });

  group('《天空之城》一手数据转换回归（基准=codex 真机核验）', () {
    test('规模：51 小节 / 317 事件 / 557 音', () {
      expect(score.measures.length, 51);
      expect(score.events.length, 317);
      expect(score.events.expand((e) => e.notes).length, 557);
    });

    test('时间：曲长 152.8536585 秒，首声 2.25 秒（前三拍休止保留）', () {
      expect(score.durationSeconds, closeTo(152.8536585, 0.0005));
      expect(
        score.events.firstWhere((e) => e.notes.isNotEmpty).startSeconds,
        closeTo(2.25, 1e-9),
      );
    });

    test('速度：文件 96 存档不用，页速 80 生效，末段 82', () {
      expect(score.sourceTempo, 96);
      expect(score.startingTempo, 80);
      expect(score.measures.first.tempo, 80);
      expect(score.measures.last.tempo, 82);
      // 只有含变速自动化的小节换速：第 1..49 小节恒 80，第 50 小节起 82。
      expect(
        score.measures.map((m) => m.tempo).toSet(),
        unorderedEquals(<int>[80, 82]),
      );
    });

    test('调弦与音高：1→4 = A4 E4 C4 G4，midi = 调弦 + 品', () {
      expect(score.tuning1to4, [69, 64, 60, 67]);
      for (final note in score.events.expand((e) => e.notes)) {
        expect(note.stringNo, inInclusiveRange(1, 4));
        expect(note.fret, greaterThanOrEqualTo(0));
        expect(note.midi, score.tuning1to4[note.stringNo - 1] + note.fret);
      }
    });

    test('延音 13 个、自然泛音 4 个，延音起点可回查', () {
      final notes = score.events.expand((e) => e.notes).toList();
      final ties = notes.where((n) => n.isTieDestination).toList();
      final harmonics = notes.where((n) => n.isNaturalHarmonic).toList();
      expect(ties.length, 13);
      expect(harmonics.length, 4);
      final allIds = notes.map((n) => n.id).toSet();
      for (final tie in ties) {
        expect(tie.tieOriginNoteId, isNotNull);
        expect(allIds.contains(tie.tieOriginNoteId), isTrue,
            reason: '延音尾音 ${tie.id} 的起点 ${tie.tieOriginNoteId} 必须存在');
      }
    });

    test('段落标记：2=Part A、18=Part B、26=Part C、34=Part A、50=Ending', () {
      final sections = <int, String>{
        for (final m in score.measures)
          if (m.section != null) m.index + 1: m.section!,
      };
      expect(sections, {
        2: 'Part A',
        18: 'Part B',
        26: 'Part C',
        34: 'Part A',
        50: 'Ending',
      });
    });

    test('时间轴连续性：事件落在本小节内，小节首尾相接无缝', () {
      for (final event in score.events) {
        final m = score.measures[event.measureIndex];
        expect(event.startSeconds, greaterThanOrEqualTo(m.startSeconds - 1e-9));
        expect(event.startSeconds + event.durationSeconds,
            lessThanOrEqualTo(m.startSeconds + m.durationSeconds + 1e-9));
      }
      for (var i = 1; i < score.measures.length; i++) {
        expect(score.measures[i].startSeconds,
            closeTo(score.measures[i - 1].startSeconds + score.measures[i - 1].durationSeconds, 1e-9));
      }
    });

    test('守门：改出反复记号必须明确拒绝，不静默通过', () {
      final mutated = jsonDecode(raw) as Map;
      (mutated['masterBars'] as List)[5]['isRepeatStart'] = true;
      expect(
        () => buildReferenceScore(mutated, pageTempoBpm: 80),
        throwsA(isA<ScoreImportException>()
            .having((e) => e.message, 'message', contains('反复'))),
      );
    });
  });
}
