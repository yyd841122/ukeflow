import '../../data/chord_library.dart';

/// 弦枕上方的开/闷标记。
enum StringMark { open, mute }

/// 一个品位点：第 [string] 根弦、图窗内第 [row] 行（1 = 窗口第一品）、按弦手指。
class Dot {
  const Dot({required this.string, required this.row, required this.finger});

  final int string;
  final int row;
  final int finger;

  @override
  bool operator ==(Object other) =>
      other is Dot &&
      other.string == string &&
      other.row == row &&
      other.finger == finger;

  @override
  int get hashCode => Object.hash(string, row, finger);
}

/// 一条横按：第 [row] 行、从第 [from] 到第 [to] 弦（含两端）。
class Barre {
  const Barre({required this.row, required this.from, required this.to});

  final int row;
  final int from;
  final int to;

  @override
  bool operator ==(Object other) =>
      other is Barre && other.row == row && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(row, from, to);
}

/// 指法 → 和弦图几何的纯函数。绘制与数据一致的保证点：
/// 弦序（0=G 最左）、品位行（窗口相对）、空弦/闷音标记、横按跨度都从这里出。
/// CustomPainter 只做笔画，不含判断。
class ChordDiagramLayout {
  ChordDiagramLayout(ChordFingering fingering, {this.fretsOnChord = 4})
    : baseFret = fingering.baseFret,
      showsNut = fingering.baseFret == 1,
      marks = List<StringMark?>.generate(4, (i) {
        final fret = fingering.frets[i];
        if (fret == 0) return StringMark.open;
        if (fret == -1) return StringMark.mute;
        return null;
      }),
      dots = <Dot>[
        for (var i = 0; i < 4; i++)
          if (fingering.frets[i] >= 1)
            Dot(string: i, row: fingering.frets[i], finger: fingering.fingers[i]),
      ],
      barres = _barres(fingering);

  /// 图窗内行数（chords-db fretsOnChord）。
  final int fretsOnChord;

  /// 窗口起始品位；1 时画粗琴枕，>1 时侧边标注数字。
  final int baseFret;

  final bool showsNut;
  final List<StringMark?> marks;
  final List<Dot> dots;

  /// 全部横按（数据可含多条，如 A7sus4 的 [1,2]）。
  final List<Barre> barres;

  /// 每条横按取品位相符弦的最小到最大下标；弦不相邻时也整体横跨
  /// （中间弦上有更高品位点盖在其上，与和弦图惯例一致）。
  static List<Barre> _barres(ChordFingering fingering) => [
    for (final row in fingering.barres)
      if ([
        for (var i = 0; i < 4; i++)
          if (fingering.frets[i] == row) i,
      ] case final strings when strings.isNotEmpty)
        Barre(row: row, from: strings.first, to: strings.last),
  ];
}
