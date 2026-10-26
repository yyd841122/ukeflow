import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/import/score_ir_editor.dart';
import 'package:ukeflow/core/practice/score_sheet_layout.dart';
import 'package:ukeflow/features/play/score_sheet_view.dart';
import 'package:ukeflow/features/play/tab_chart_layout.dart';
import 'package:ukeflow/features/play/tab_chart_view.dart';

/// 工单 45 点选(纯函数缝):点位 → 音引用。横带/四线谱两套命中带与
/// 容差用真数据锁定;点空处返回 null(不误开面板)。
void main() {
  final charts = {for (final e in builtinTabChartCatalog) e.id: e.chart};
  final def = scoreSheetCatalog.single;
  final solo = charts[def.tabChartId]!;
  final melody = charts[def.melodyChartId]!;

  group('横带 pickStripNote', () {
    final layout = ScoreSheetLayout(
      def: def,
      tabChart: solo,
      melodyChart: melody,
    );

    test('琴弦层:音位 x + 对应弦线 y 命中伴奏音', () {
      final note = layout.tabNotes.first;
      final x = layout.stripX(note.beat);
      final y =
          ScoreSheetLayout.tabBandTop +
          (note.string - 1) * ScoreSheetLayout.tabLineGap;
      expect(
        pickStripNote(layout, Offset(x, y)),
        ScoreIrNoteRef(
          voice: ScoreIrVoiceKind.accompaniment,
          string: note.string,
          beat: note.beat,
        ),
      );
    });

    test('简谱层:度数字位命中旋律音', () {
      final note = layout.melodyNotes.first;
      final x = layout.stripX(note.beat + def.melodyAlignBeats);
      expect(
        pickStripNote(layout, Offset(x, ScoreSheetLayout.numCenterY)),
        ScoreIrNoteRef(
          voice: ScoreIrVoiceKind.melody,
          string: note.string,
          beat: note.beat,
        ),
      );
    });

    test('层外/带内空处返回 null', () {
      // 和弦图层(顶部)不在点选带。
      expect(pickStripNote(layout, const Offset(200, 20)), isNull);
      // 琴弦层内但远离任何音 x(带首留白)。
      expect(
        pickStripNote(layout, Offset(2, ScoreSheetLayout.tabBandTop)),
        isNull,
      );
    });
  });

  group('四线谱 pickTabNote', () {
    test('音点命中,同拍多音按纵距就近取弦', () {
      final layout = TabChartLayout(solo, pxPerBeat: 44);
      final note = layout.notes.first;
      final y = TabChartLayout.stringY(note.string);
      expect(
        pickTabNote(layout, Offset(layout.noteX(note.beat), y)),
        ScoreIrNoteRef(
          voice: ScoreIrVoiceKind.accompaniment,
          string: note.string,
          beat: note.beat,
        ),
      );
    });

    test('弦区外/空处返回 null', () {
      final layout = TabChartLayout(solo, pxPerBeat: 44);
      expect(pickTabNote(layout, const Offset(20, 2)), isNull);
      expect(
        pickTabNote(
          layout,
          Offset(TabChartLayout.firstPad - 5, TabChartLayout.stringY(2)),
        ),
        isNull,
      );
    });
  });
}
