import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/chord_library.dart';
import 'package:ukeflow/features/chords/chord_diagram_layout.dart';

/// 工单 02 seam 2：指法 → 图几何的纯函数。
/// 期望值来自手算 worked example 与 chords-db 原始数据，与绘制实现无共谋。
ChordFingering fingering({
  required List<int> frets,
  List<int>? fingers,
  int baseFret = 1,
  List<int> barres = const [],
}) => ChordFingering(
  frets: frets,
  fingers: fingers ?? List.filled(4, 0),
  baseFret: baseFret,
  barres: barres,
);

void main() {
  group('F 和弦（真实数据 2010）', () {
    final layout = ChordDiagramLayout(
      fingering(frets: [2, 0, 1, 0], fingers: [2, 0, 1, 0]),
    );

    test('第一品窗口画琴枕，无偏移标签需求', () {
      expect(layout.showsNut, isTrue);
      expect(layout.baseFret, 1);
    });

    test('品位点：G 弦 2 品用指 2，E 弦 1 品用指 1', () {
      expect(layout.dots, const [
        Dot(string: 0, row: 2, finger: 2),
        Dot(string: 2, row: 1, finger: 1),
      ]);
    });

    test('空弦弦在弦枕上方标 ○，品位弦不标', () {
      expect(layout.marks, [null, StringMark.open, null, StringMark.open]);
    });

    test('无横按', () => expect(layout.barres, isEmpty));
  });

  group('C 横按指法（真实数据 baseFret=3 相对窗口）', () {
    final layout = ChordDiagramLayout(
      fingering(
        frets: [3, 2, 1, 1],
        fingers: [3, 2, 1, 1],
        baseFret: 3,
        barres: [1],
      ),
    );

    test('高于第一品的窗口不画琴枕', () {
      expect(layout.showsNut, isFalse);
      expect(layout.baseFret, 3);
    });

    test('品位点按窗口相对行落位', () {
      expect(layout.dots, const [
        Dot(string: 0, row: 3, finger: 3),
        Dot(string: 1, row: 2, finger: 2),
        Dot(string: 2, row: 1, finger: 1),
        Dot(string: 3, row: 1, finger: 1),
      ]);
    });

    test('横按落在第 1 行、横跨品位相符的弦 2..3', () {
      expect(layout.barres, const [Barre(row: 1, from: 2, to: 3)]);
    });
  });

  group('闷音与跨弦横按', () {
    test('闷音弦标 ×，不产生品位点', () {
      final layout = ChordDiagramLayout(
        fingering(frets: [-1, 2, 0, 0], fingers: [0, 2, 0, 0]),
      );
      expect(layout.marks[0], StringMark.mute);
      expect(layout.dots, const [Dot(string: 1, row: 2, finger: 2)]);
    });

    test('横按跨度取品位相符弦的最小到最大下标（真实 C 指法 0433/barre3）', () {
      final layout = ChordDiagramLayout(
        fingering(frets: [0, 4, 3, 3], fingers: [0, 2, 1, 1], barres: [3]),
      );
      expect(layout.barres, const [Barre(row: 3, from: 2, to: 3)]);
    });
  });
}
