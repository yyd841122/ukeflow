import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/score/flowing_timeline.dart';
import 'package:ukeflow/core/score/reference_score.dart';

/// 流水时间线:画面位置唯一对照表与一帧决策(变色/相机/曲末)。
/// 边界场景移植自 codex flowing-timeline.test(开头休止、到点变色、
/// 恰在边界切换、曲末保留),几何与真谱连续性为本仓新增闸。
void main() {
  /// codex 同款三事件场景:曲头 2.25s 休止、单音、双音和弦,曲长 4s。
  ReferenceScore syntheticScore() {
    RefEvent event(int id, double start, double dur, List<int> noteIds) =>
        RefEvent(
          id: id,
          measureIndex: 0,
          voiceIndex: 0,
          startSeconds: start,
          durationSeconds: dur,
          notes: [
            for (final nid in noteIds)
              RefNote(
                id: nid,
                stringNo: 1,
                fret: 0,
                midi: 69,
                isTieDestination: false,
                tieOriginNoteId: null,
                isNaturalHarmonic: false,
                hasSlideOut: false,
                sourceString: 4,
              ),
          ],
          chord: null,
          brushType: 0,
          durationValue: 8,
          dots: 0,
          startTick: 0,
        );
    return ReferenceScore(
      title: '测试谱',
      artist: '',
      sourceTempo: 80,
      startingTempo: 80,
      keySignature: 0,
      tuning1to4: [69, 64, 60, 67],
      measures: [
        RefMeasure(
          index: 0,
          startSeconds: 0,
          durationSeconds: 4,
          tempo: 60,
          numerator: 4,
          denominator: 4,
          section: null,
        ),
      ],
      events: [
        event(1, 0, 2.25, const []),
        event(2, 2.25, 0.375, const [7]),
        event(3, 2.625, 1.375, const [8, 9]),
      ],
      durationSeconds: 4,
    );
  }

  group('一帧决策(codex 边界场景)', () {
    final score = syntheticScore();
    const pps = 120.0;
    final layout = FlowingLayout.fromScore(score, pixelsPerSecond: pps);
    const cursorX = 100.0;

    test('开头休止完整保留:0 秒无音变色,红线停在曲头', () {
      final frame = frameAt(score, layout, 0, cursorX);
      expect(frame.noteIds, isEmpty);
      expect(frame.finished, isFalse);
      // 相机恒等式:平移 + 位置 == 红线位置(画面唯一对照表的定义)。
      expect(frame.translateX + layout.positionAt(0), cursorX);
    });

    test('首音到线:2.25 秒恰逢事件,该音入变色集', () {
      final frame = frameAt(score, layout, 2.25, cursorX);
      expect(frame.noteIds, [7]);
      expect(frame.translateX + layout.positionAt(2.25), cursorX);
    });

    test('变色恰在边界切换:上一音尽、下一刻和弦整组亮', () {
      expect(frameAt(score, layout, 2.624, cursorX).noteIds, [7]);
      expect(frameAt(score, layout, 2.625, cursorX).noteIds, [8, 9]);
    });

    test('休止是活动事件:到点变色(休止占位红),但无音入变色集', () {
      final frame = frameAt(score, layout, 1.0, cursorX);
      expect(frame.event?.id, 1);
      expect(frame.noteIds, isEmpty);
    });

    test('曲末钳制:99 秒停在曲末,finished 置位,变色清空', () {
      final frame = frameAt(score, layout, 99, cursorX);
      expect(frame.seconds, 4);
      expect(frame.finished, isTrue);
      expect(frame.noteIds, isEmpty);
      expect(frame.translateX + layout.positionAt(4), cursorX);
    });
  });

  group('画面位置对照表(几何闸)', () {
    test('事件锚点恰在小节线+留白+小节内时间×斜率处,曲末锚点=终止线', () {
      final raw =
          File('assets/scores/sky-city-guistudy.json').readAsStringSync();
      final score = buildReferenceScore(jsonDecode(raw), pageTempoBpm: 80);
      final layout = FlowingLayout.fromScore(score, pixelsPerSecond: 100);
      for (final event in score.events) {
        final m = score.measures[event.measureIndex];
        final expected = layout.measureLeftX[event.measureIndex] +
            32.0 +
            (event.startSeconds - m.startSeconds) *
                layout.slopeOf(event.measureIndex);
        expect(layout.positionAt(event.startSeconds), closeTo(expected, 1e-9),
            reason: '事件 ${event.id} 锚点漂移');
      }
      expect(layout.positionAt(score.durationSeconds), layout.endX);
    });

    test('逐小节测宽:八分连排小节斜率抬到密度地板,稀疏小节保持基准', () {
      final raw =
          File('assets/scores/sky-city-guistudy.json').readAsStringSync();
      final score = buildReferenceScore(jsonDecode(raw), pageTempoBpm: 80);
      final layout = FlowingLayout.fromScore(score, pixelsPerSecond: 52);
      // 全曲最紧间隔 = 480 tick(相邻八分音):密度地板 = 24px/480tick
      // ×1280tick/s = 64px/s;基准 = 52px/s。
      var hasDense = false;
      // ignore: unused_local_variable
      var hasSparse = false;
      for (final m in score.measures) {
        final evs = score.events
            .where((e) => e.measureIndex == m.index)
            .map((e) => e.startTick)
            .toList();
        if (evs.length < 2) continue;
        var gapMin = 1 << 30;
        for (var i = 1; i < evs.length; i++) {
          gapMin = math.min(gapMin, evs[i] - evs[i - 1]);
        }
        if (gapMin <= 480) {
          // 密度地板斜率 = minGapPx/gapMin × 16×tempo(拍速逐小节,末段 82)。
          final expectedSlope = 24 / gapMin * 16 * m.tempo;
          expect(layout.slopeOf(m.index), closeTo(expectedSlope, 1e-6),
              reason: '小节 ${m.index + 1} 密(最紧 $gapMin tick)');
          hasDense = true;
        } else if (gapMin >= 960) {
          expect(layout.slopeOf(m.index), closeTo(52, 1e-6),
              reason: '小节 ${m.index + 1} 疏(最紧 $gapMin tick)');
          hasSparse = true;
        }
      }
      expect(hasDense, isTrue, reason: '真谱应存在八分连排小节');
    });

    test('连续性:锚点时间严格递增(禁同刻不同位);任意采样无跳变,单步不超最陡段斜率',
        () {
      final raw =
          File('assets/scores/sky-city-guistudy.json').readAsStringSync();
      final score = buildReferenceScore(jsonDecode(raw), pageTempoBpm: 80);
      final layout = FlowingLayout.fromScore(score, pixelsPerSecond: 145);
      // 真机教训闸(2026-11-08 小节头瞬移):锚点时间必须严格递增——
      // 同刻不同位的锚点对会让 positionAt 瞬移一整个留白宽。
      final anchors = layout.anchors;
      for (var i = 1; i < anchors.length; i++) {
        expect(anchors[i].time, greaterThan(anchors[i - 1].time),
            reason: '锚点 $i 时间不递增:${anchors[i - 1].time}');
      }
      // 最陡段斜率 = 最短锚点间隔段(跨留白段有意加速,但连续)。
      var maxSlope = 0.0;
      for (var i = 1; i < anchors.length; i++) {
        final dt = anchors[i].time - anchors[i - 1].time;
        final slope = (anchors[i].x - anchors[i - 1].x) / dt;
        if (slope > maxSlope) maxSlope = slope;
      }
      const dt = 0.001;
      var previous = layout.positionAt(0);
      for (var t = dt; t <= score.durationSeconds; t += dt) {
        final x = layout.positionAt(t);
        expect(x, greaterThanOrEqualTo(previous - 1e-9), reason: 't=$t 倒退');
        expect(x - previous, lessThan(maxSlope * dt + 1e-6),
            reason: 't=$t 跳变(超最陡段斜率)');
        previous = x;
      }
      // 段内线性:同小节相邻锚点(中间无其他锚点)取 20 对,中点=均值。
      final events = score.events;
      var checked = 0;
      for (var i = 0; i < events.length - 1 && checked < 20; i++) {
        if (events[i].measureIndex != events[i + 1].measureIndex) continue;
        final a = events[i].startSeconds;
        final b = events[i + 1].startSeconds;
        final mid = layout.positionAt((a + b) / 2);
        final ends = (layout.positionAt(a) + layout.positionAt(b)) / 2;
        expect(mid, closeTo(ends, 1e-6), reason: '锚点 $i 与 $i+1 之间非线性');
        checked++;
      }
      expect(checked, greaterThan(0));
    });

    test('小节头正拍首音:跨界采样无瞬移(旧小节末锚点方案必红)', () {
      // 合成场景:第 1 小节末音在 2.25s,第 2 小节首音恰在 3.0s(正拍)。
      RefEvent event(int id, int measure, double start, double dur,
              List<int> noteIds) =>
          RefEvent(
            id: id,
            measureIndex: measure,
            voiceIndex: 0,
            startSeconds: start,
            durationSeconds: dur,
            notes: [
              for (final nid in noteIds)
                RefNote(
                  id: nid,
                  stringNo: 1,
                  fret: 0,
                  midi: 69,
                  isTieDestination: false,
                  tieOriginNoteId: null,
                  isNaturalHarmonic: false,
                  hasSlideOut: false,
                  sourceString: 4,
                ),
            ],
            chord: null,
            brushType: 0,
            durationValue: 4,
            dots: 0,
            startTick: (start * 1280).round(),
          );
      final score = ReferenceScore(
        title: '跨界测试',
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
          event(1, 0, 0.0, 2.25, const []),
          event(2, 0, 2.25, 0.75, const [7]),
          event(3, 1, 3.0, 0.75, const [8]),
        ],
        durationSeconds: 6,
      );
      final layout = FlowingLayout.fromScore(score, pixelsPerSecond: 100);
      // 2.25→3.0s 间相机穿过 56px 留白:期望斜率由布局两端位置推出。
      const h = 0.0005;
      var previous = layout.positionAt(2.25);
      var maxStep = 0.0;
      for (var t = 2.25 + h; t <= 3.0 + 1e-9; t += h) {
        final x = layout.positionAt(t);
        final step = x - previous;
        if (step > maxStep) maxStep = step;
        previous = x;
      }
      final crossingSlope =
          (layout.positionAt(3.0) - layout.positionAt(2.25)) / 0.75;
      // 单步上限 = 斜率×h;旧方案在同刻锚点处一步瞬移 56px,必红。
      expect(maxStep, lessThan(crossingSlope * h + 1e-6),
          reason: '跨界出现瞬移:单步 $maxStep');
    });

    test('midiToFrequency:A4=440,八度翻倍', () {
      expect(midiToFrequency(69), 440.0);
      expect(midiToFrequency(81), closeTo(880, 1e-9));
    });
  });
}
