import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/model/tab_chart.dart';
import 'package:ukeflow/core/practice/dual_track_timeline.dart';
import 'package:ukeflow/core/practice/tab_timeline.dart';

/// 混播编译内核(工单 39 测试缝②):组合定义 → 双轨逐音事件时间轴。
/// 旋律轨播放侧 +4 半音合流 E 调在编译处落定(4 半音 = 同弦整数品上移,
/// frequency 随品位自动正确);显示不变,各谱卡单独跟练仍原调不动。
void main() {
  final charts = {for (final e in builtinTabChartCatalog) e.id: e.chart};
  final def = scoreSheetCatalog.single;
  final solo = charts[def.tabChartId]!;
  final melody = charts[def.melodyChartId]!;

  group('双轨合并谱', () {
    final merged = buildDualTrackChart(def, solo, melody);

    test('两轨全量合并:496 伴奏音原样 + 168 旋律音移位', () {
      expect(merged.notes.length, solo.notes.length + melody.notes.length);
    });

    test('伴奏轨原样:逐音等值(同弦同品同拍)', () {
      for (final note in solo.notes) {
        expect(
          merged.notes.any((n) =>
              n.string == note.string &&
              n.fret == note.fret &&
              n.beat == note.beat),
          isTrue,
          reason: '伴奏音丢失:$note',
        );
      }
    });

    test('旋律轨:拍位 +20 对齐主轴,fret +4(= +4 半音)发声合流 E 调', () {
      const shift = dualTrackSemitoneShift;
      for (final note in melody.notes) {
        final moved = merged.notes.firstWhere(
          (n) =>
              n.string == note.string &&
              n.fret == note.fret + shift &&
              n.beat == note.beat + def.melodyAlignBeats,
          orElse: () => throw TestFailure('旋律音移位丢失:$note'),
        );
        expect(
          moved.frequency,
          closeTo(note.frequency * _ratio(shift), 1e-6),
          reason: '+4 半音 = ×2^(4/12)',
        );
      }
    });

    test('合并谱过校验:fret 非负、拍位合法(旋律最高 ①12→①16 合法)', () {
      expect(() => validateTabChart(merged, context: 'dual-track'),
          returnsNormally);
      final maxFret = merged.notes.map((n) => n.fret).reduce(math.max);
      expect(maxFret, 16, reason: 'A5=①12 +4 = ①16(C#6),全谱最高品');
    });
  });

  test('拍位对齐:编译后旋律轨事件与伴奏轨同拍事件同刻(主轴 +20 恒定)', () {
    final merged = buildDualTrackChart(def, solo, melody);
    final timeline = compileTabTimeline(
      chart: merged,
      bpm: merged.tempo.toDouble(),
    );
    final period = timeline.periodMs;

    // 旋律首音 你 G4@0 → 主轴拍 20;主轴拍 20 恰是主歌 E 堆头拍(伴奏音)。
    final at20 = timeline.notes
        .where((e) => e.time.inMilliseconds == (20 * period).round())
        .toList();
    expect(at20.length, greaterThan(1), reason: '伴奏堆与旋律音同刻在位');
    // 合流后旋律音(②7=B4)与伴奏堆音不同频——同刻不同轨,不打架。
    final freqs = at20.map((e) => e.frequency).toSet();
    expect(freqs.length, greaterThan(1));
  });

  test('合流后旋律轨音高域:F#4(D4 上移)起、C#6(①16)顶,KS 音源域内', () {
    final melodyShiftedFreqs = [
      for (final n in melody.notes)
        n.frequency * _ratio(dualTrackSemitoneShift),
    ];
    final minF = melodyShiftedFreqs.reduce(math.min);
    final maxF = melodyShiftedFreqs.reduce(math.max);
    expect(minF, closeTo(369.99, 1.0), reason: 'F#4 = 旋律最低 D4(③2)+4 半音');
    expect(maxF, closeTo(1108.73, 1.0), reason: 'C#6 = ①16');
    expect(maxF, lessThan(1400), reason: 'KS 音源域内,不超发声明');
  });
}

double _ratio(int semitones) => math.pow(2, semitones / 12).toDouble();
