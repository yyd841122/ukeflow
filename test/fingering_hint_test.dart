import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/score/flowing_engraving.dart';
import 'package:ukeflow/core/score/flowing_timeline.dart';
import 'package:ukeflow/core/score/reference_score.dart';
import 'package:ukeflow/features/play/flowing/fingering_diagram.dart';
import 'package:ukeflow/features/play/flowing/fingering_hint.dart';

/// 按法提示(票05):模型语义 + 与画面数字单一来源锁定 + 小图组件。
void main() {
  ReferenceScore miniScore() {
    RefNote note(int id, int stringNo, int fret,
            {bool tie = false, int origin = -1, bool harmonic = false}) =>
        RefNote(
          id: id,
          stringNo: stringNo,
          fret: fret,
          midi: 69,
          isTieDestination: tie,
          tieOriginNoteId: origin >= 0 ? origin : null,
          isNaturalHarmonic: harmonic,
          hasSlideOut: false,
          sourceString: 4,
        );
    RefEvent event(int id, double start, double dur, List<RefNote> notes) =>
        RefEvent(
          id: id,
          measureIndex: 0,
          voiceIndex: 0,
          startSeconds: start,
          durationSeconds: dur,
          notes: notes,
          chord: null,
          brushType: 0,
          durationValue: 8,
          dots: 0,
          startTick: 0,
        );
    return ReferenceScore(
      title: '提示测试谱',
      artist: '',
      sourceTempo: 80,
      startingTempo: 80,
      keySignature: 0,
      tuning1to4: [69, 64, 60, 67],
      measures: [
        for (var i = 0; i < 2; i++)
          RefMeasure(
            index: i,
            startSeconds: i * 3,
            durationSeconds: 3,
            tempo: 80,
            numerator: 4,
            denominator: 4,
            section: null,
          ),
      ],
      events: [
        // e1 普通单音;e2 空弦+泛音;e3 整组延音(无新按法);e4 休止。
        event(1, 0, 0.5, [note(100, 1, 3)]),
        event(2, 1.0, 0.5, [note(200, 1, 0), note(201, 2, 5, harmonic: true)]),
        event(3, 2.0, 0.5,
            [note(300, 1, 3, tie: true, origin: 100)]),
        event(4, 3.0, 0.5, const []),
      ],
      durationSeconds: 6,
    );
  }

  group('按法提示语义(票05;codex 同款:当前=最后越过事件)', () {
    test('曲头未越过任何事件:当前无法提示,下一步 = 首事件', () {
      final pair = fingeringHintsAt(miniScore(), -0.5);
      expect(pair.current.showable, isFalse);
      expect(pair.next!.notes.map((n) => n.summary), ['1弦 3 品']);
    });

    test('事件中:当前/下一步各就各位', () {
      final pair = fingeringHintsAt(miniScore(), 0.2);
      expect(pair.current.notes.map((n) => n.summary), ['1弦 3 品']);
      expect(pair.next!.notes.length, 2);
    });

    test('空弦与泛音:文本样式与画面数字同款', () {
      final pair = fingeringHintsAt(miniScore(), 1.2);
      expect(pair.current.notes.map((n) => n.summary),
          ['1弦 空弦', '2弦 <5> 品']);
      expect(pair.current.summary, '1弦 空弦 · 2弦 <5> 品');
    });

    test('间隙期:当前 = 刚弹过的(手上还按着),下一步 = 后继', () {
      final pair = fingeringHintsAt(miniScore(), 1.7); // e1 已尽、e2 未到前?1.7 在 e2(1.0-1.5) 后 e3(2.0) 前。
      expect(pair.current.notes.map((n) => n.summary),
          ['1弦 空弦', '2弦 <5> 品'], reason: '最后越过事件是 e2');
      expect(pair.next!.showable, isFalse,
          reason: 'e3 整组延音 → 下一步卡显示无法提示');
    });

    test('整组延音为当前:无法提示(不猜测)', () {
      final pair = fingeringHintsAt(miniScore(), 2.2);
      expect(pair.current.showable, isFalse, reason: 'e3 整组延音');
      expect(pair.next, isNotNull);
      expect(pair.next!.showable, isFalse, reason: 'e4 休止');
    });

    test('曲末:下一步为 null;越过曲长仍取最后事件', () {
      final end = fingeringHintsAt(miniScore(), 6.0);
      expect(end.next, isNull);
      final beyond = fingeringHintsAt(miniScore(), 10.0);
      expect(beyond.current.showable, isFalse, reason: 'e4 休止');
      expect(beyond.next, isNull);
    });

    test('tieChords 注入(缓存路径)与缺省一致', () {
      final score = miniScore();
      final ties = tieChordIds(score);
      final a = fingeringHintsAt(score, 2.2);
      final b = fingeringHintsAt(score, 2.2, tieChords: ties);
      expect(a.current.showable, b.current.showable);
      expect(ties, {3}, reason: '只有 e3 整组延音');
    });
  });

  group('单一来源锁定:画面数字与提示卡同判定', () {
    test('《天空之城》全事件:提示可提示性与位表逐一吻合排版数字', () {
      final raw =
          File('assets/scores/sky-city-guistudy.json').readAsStringSync();
      final score = buildReferenceScore(jsonDecode(raw), pageTempoBpm: 80);
      final engraving = FlowingEngraving.build(
        score,
        layout: FlowingLayout.fromScore(score, pixelsPerSecond: 100),
        plan: buildEngravingPlan(score),
        geometry: const FlowingGeometry(),
      );
      final glyphsById = {
        for (final g in engraving.eventGlyphs) g.event.id: g,
      };
      final noteById = {
        for (final e in score.events)
          for (final n in e.notes) n.id: n,
      };
      final ties = tieChordIds(score);
      var hintable = 0;
      for (final e in score.events) {
        final hint = fingeringHintsAt(score, e.startSeconds + 1e-6,
                tieChords: ties)
            .current;
        final glyphs = glyphsById[e.id]!;
        expect(hint.showable, glyphs.digits.isNotEmpty,
            reason: '事件 ${e.id} 提示卡与画面数字可见性不一致');
        expect(
          hint.notes.map((n) => (n.stringNo, n.fret)).toList(),
          [
            for (final d in glyphs.digits)
              (noteById[d.noteId]!.stringNo, noteById[d.noteId]!.fret),
          ],
          reason: '事件 ${e.id} 位表与数字内容不一致',
        );
        if (hint.showable) hintable++;
      }
      expect(hintable, greaterThan(300), reason: '真谱绝大多数事件可提示');
    });
  });

  testWidgets('FingeringDiagram:空表显示「无法提示」,有位正常作画', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          FingeringDiagram(notes: [], width: 126),
          FingeringDiagram(notes: [FingeringNote(stringNo: 1, fret: 3, isNaturalHarmonic: false)], width: 126),
        ]),
      ),
    ));
    expect(find.text('无法提示'), findsOneWidget);
  });
}
