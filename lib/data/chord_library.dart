import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/model/chord.dart';

export '../core/model/chord.dart' show Chord, ChordDataError, ChordFingering;

/// 内置和弦库（chords-db ukulele.json，MIT）。
class ChordLibrary {
  const ChordLibrary(this.chords);

  final List<Chord> chords;

  /// 全库和弦名集合（Chord.label）：谱面校验的白名单（ADR-0006）。
  Set<String> get labels => {for (final chord in chords) chord.label};

  /// 和弦图品位窗行数。绘制契约：解析拒绝 ≠ 4 的 fretsOnChord。
  static const fretsOnChord = 4;

  /// 解析并校验 chords-db ukulele JSON。任何坏数据抛 [ChordDataError]。
  static ChordLibrary parse(String text) {
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException catch (e) {
      throw ChordDataError('和弦库 JSON 解析失败: ${e.message}');
    }
    if (root is! Map<String, Object?>) {
      throw ChordDataError('和弦库 JSON 顶层应为对象');
    }

    final main = _map(root['main'], 'main');
    final strings = _int(_field(main, 'strings', 'main'), 'main.strings');
    if (strings != 4) {
      throw ChordDataError('main.strings=$strings：和弦库应为 4 弦尤克里里数据');
    }
    final window = _int(
      _field(main, 'fretsOnChord', 'main'),
      'main.fretsOnChord',
    );
    if (window != fretsOnChord) {
      throw ChordDataError('main.fretsOnChord=$window：当前和弦图固定 $fretsOnChord 品位窗');
    }

    final chordsJson = _map(root['chords'], 'chords');
    final chords = <Chord>[];
    for (final entry in chordsJson.entries) {
      final list = _list(entry.value, 'chords.${entry.key}');
      for (final chordJson in list) {
        chords.add(_chord(_map(chordJson, 'chords.${entry.key}'), window));
      }
    }
    return ChordLibrary(chords);
  }

  static Chord _chord(Map<String, Object?> json, int fretsOnChord) {
    final key = _string(_field(json, 'key', '和弦'), 'key');
    final suffix = _string(_field(json, 'suffix', '和弦 $key'), 'suffix');
    final ctx = '和弦 $key$suffix';
    final positions = _list(_field(json, 'positions', ctx), '$ctx positions');
    final fingerings = <ChordFingering>[];
    for (var i = 0; i < positions.length; i++) {
      fingerings.add(
        _fingering(_map(positions[i], '$ctx 第 $i 个指法'), '$ctx 第 $i 个指法', fretsOnChord),
      );
    }
    return Chord(root: key, suffix: suffix, fingerings: fingerings);
  }

  static ChordFingering _fingering(
    Map<String, Object?> json,
    String ctx,
    int fretsOnChord,
  ) {
    final frets = _ints(_field(json, 'frets', ctx), '$ctx frets');
    if (frets.length != 4) {
      throw ChordDataError('$ctx：指法应有 4 根弦的数据（实际 ${frets.length}）');
    }
    for (final fret in frets) {
      if (fret < -1 || fret > fretsOnChord) {
        throw ChordDataError('$ctx：品位越界 $fret（允许 -1..$fretsOnChord）');
      }
    }
    final fingers = _ints(_field(json, 'fingers', ctx), '$ctx fingers');
    if (fingers.length != 4) {
      throw ChordDataError('$ctx：手指编号应有 4 根弦的数据（实际 ${fingers.length}）');
    }
    for (final finger in fingers) {
      if (finger < 0 || finger > 4) {
        throw ChordDataError('$ctx：手指编号越界 $finger（允许 0..4）');
      }
    }
    final baseFret = _int(_field(json, 'baseFret', ctx), '$ctx baseFret');
    if (baseFret < 1) {
      throw ChordDataError('$ctx：起始品位 baseFret=$baseFret 应 ≥ 1');
    }
    final barres = _ints(_opt(json, 'barres') ?? const <Object>[], '$ctx barres');
    for (final barre in barres) {
      if (barre < 1 || barre > fretsOnChord) {
        throw ChordDataError('$ctx：横按品位越界 $barre（允许 1..$fretsOnChord）');
      }
    }
    final midiJson = _opt(json, 'midi');
    final midi = midiJson == null ? null : _ints(midiJson, '$ctx midi');
    if (midi != null && midi.length != frets.length) {
      throw ChordDataError('$ctx：midi 应有 ${frets.length} 根弦的数据（实际 ${midi.length}）');
    }
    return ChordFingering(
      frets: frets,
      fingers: fingers,
      baseFret: baseFret,
      barres: barres,
      midi: midi,
    );
  }

  static Object _field(Map<String, Object?> map, String name, String ctx) {
    final value = map[name];
    if (value == null) throw ChordDataError('$ctx：缺少字段 $name');
    return value;
  }

  static Object? _opt(Map<String, Object?> map, String name) => map[name];

  static Map<String, Object?> _map(Object? value, String ctx) =>
      value is Map<String, Object?> ? value : throw ChordDataError('$ctx 应为对象');

  static List<Object?> _list(Object? value, String ctx) =>
      value is List<Object?> ? value : throw ChordDataError('$ctx 应为数组');

  static String _string(Object? value, String name) => value is String
      ? value
      : throw ChordDataError('$name 应为字符串');

  static int _int(Object? value, String name) => value is int
      ? value
      : throw ChordDataError('$name 应为整数');

  static List<int> _ints(Object? value, String ctx) {
    final list = _list(value, ctx);
    return [
      for (var i = 0; i < list.length; i++)
        _int(list[i], '$ctx[$i]'),
    ];
  }
}

/// 全局和弦库：首次读取时从内置资产加载并校验。
final chordLibraryProvider = FutureProvider<ChordLibrary>((ref) async {
  final text = await rootBundle.loadString('assets/chords/ukulele.json');
  return ChordLibrary.parse(text);
});
