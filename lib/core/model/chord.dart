/// 和弦域模型（GLOSSARY「和弦指法」）：数据形态来自 chords-db ukulele.json。
library;

/// 一个和弦指法的一种按法（chords-db 的 position）。
///
/// 弦序：下标 0..3 = G C E A（4 弦 → 1 弦）。
/// 品位语义：[baseFret] 为图窗起始品位（1 = 琴枕）；[frets] 与 [barres]
/// 存的是窗口内相对品位（baseFret=1 时即绝对品位，与源数据一致，已对全量
/// midi 验证）。绘制时由 ChordDiagramLayout 统一加偏移。
class ChordFingering {
  const ChordFingering({
    required this.frets,
    required this.fingers,
    required this.baseFret,
    required this.barres,
    this.midi,
  });

  /// 4 项。-1 闷音（×）、0 空弦（○）、1..n 窗口相对品位。
  final List<int> frets;

  /// 4 项。0 = 不按，1..4 = 手指编号。
  final List<int> fingers;

  /// 图窗起始品位，1 = 第一品（画琴枕）。
  final int baseFret;

  /// 横按品位（窗口相对，可有多条），空列表 = 无横按。
  final List<int> barres;

  /// 各弦 midi 音高（源数据可选字段；示范音工单据此算频率）。
  final List<int>? midi;
}

/// 一个和弦：根音 + 后缀 + 全部指法按法。
class Chord {
  const Chord({
    required this.root,
    required this.suffix,
    required this.fingerings,
  });

  final String root;
  final String suffix;
  final List<ChordFingering> fingerings;

  /// 显示名：major 省略后缀（C），minor 缩为 m（Am），其余直接拼接（G7、Cmaj7）。
  /// 源数据小三是全拼 minor 而小七却是缩写 m7，此处归一。
  String get label => switch (suffix) {
    'major' => root,
    'minor' => '${root}m',
    _ => '$root$suffix',
  };

  /// 主指法：按新手友好度排序取最前（数据源的首个指法未必是入门按法，
  /// 如数据里 Asus2 首选是 5 品横按）。第一品窗口 > 空弦多 > 品位和低，
  /// 并列时保持数据序。
  ChordFingering get primaryFingering {
    (int, int, int) score(ChordFingering f) => (
      f.baseFret == 1 ? 0 : 1,
      -f.frets.where((x) => x == 0).length,
      f.frets.fold(0, (sum, x) => x > 0 ? sum + x : sum),
    );
    var best = fingerings.first;
    for (final f in fingerings.skip(1)) {
      final sf = score(f);
      final sb = score(best);
      if (sf.$1 < sb.$1 ||
          (sf.$1 == sb.$1 && (sf.$2 < sb.$2 || (sf.$2 == sb.$2 && sf.$3 < sb.$3)))) {
        best = f;
      }
    }
    return best;
  }
}

/// 和弦库数据坏损：加载期当场报错（含和弦与指法上下文），不带病进入 UI。
/// 继承 Error（而非 Exception）：坏数据是缺陷不是瞬时故障，
/// 不参与 Riverpod 3 的自动重试——同一份资产重读多少遍结果都一样。
class ChordDataError extends Error {
  ChordDataError(this.message);

  final String message;

  @override
  String toString() => 'ChordDataError: $message';
}
