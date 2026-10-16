import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/chord_library.dart';
import 'package:ukeflow/features/chords/chord_tips.dart';

/// 工单 02 seam 1：ChordLibrary.parse —— fixture 驱动的解析与校验。
/// 期望值来自手写 fixture 里的已知字面量，与实现无共谋。
String fixture(String name) =>
    File('test/fixtures/chords/$name').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChordLibrary.parse 好数据', () {
    late ChordLibrary lib;
    setUpAll(() => lib = ChordLibrary.parse(fixture('good.json')));

    test('全量和弦可枚举，顺序为文件根音顺序', () {
      expect(lib.chords.map((c) => c.label), containsAll(<String>['C', 'C7', 'Am7']));
    });

    test('指法字段原样保真（品位/手指/空弦/闷音/横按/相对窗口）', () {
      final c = lib.chords.singleWhere((c) => c.label == 'C');
      final open = c.fingerings[0];
      expect(open.frets, [0, 0, 0, 3]);
      expect(open.fingers, [0, 0, 0, 3]);
      expect(open.baseFret, 1);
      expect(open.barres, isEmpty);
      expect(open.midi, [67, 60, 64, 72]);

      // baseFret=3 的相对窗口按法原样保留（品位值不换算，画图时才加偏移）。
      final barre = c.fingerings[1];
      expect(barre.frets, [3, 2, 1, 1]);
      expect(barre.baseFret, 3);
      expect(barre.barres, [1]);
    });

    test('闷音 -1 与缺失 midi 均允许', () {
      final am7 = lib.chords.singleWhere((c) => c.label == 'Am7');
      expect(am7.fingerings.single.frets, [-1, 2, 0, 0]);
      expect(am7.fingerings.single.midi, isNull);
    });
  });

  group('ChordLibrary.parse 坏数据可见报错', () {
    const cases = [
      ('bad_json.json', 'JSON'),
      ('bad_strings.json', '弦'),
      ('bad_fret.json', '品位'),
      ('bad_finger.json', '手指'),
      ('bad_barre.json', '横按'),
      ('bad_length.json', '4 根弦'),
      ('bad_basefret.json', '起始品位'),
      ('bad_no_positions.json', 'positions'),
      ('bad_fretsonchord.json', '品位窗'),
      ('bad_midi_length.json', 'midi'),
      // 空 positions 数组过校验会在 primaryFingering 崩(审计30 #21);
      // midi 越界会进合成算音高(审计30 #22)。
      ('bad_empty_positions.json', '至少要有一个指法'),
      ('bad_midi_range.json', 'midi 越界'),
    ];
    for (final (name, keyword) in cases) {
      test('$name 抛 ChordDataException 且报错含上下文（$keyword）', () {
        expect(
          () => ChordLibrary.parse(fixture(name)),
          throwsA(
            isA<ChordDataError>().having(
              (e) => e.message,
              'message',
              contains(keyword),
            ),
          ),
        );
      });
    }
  });

  group('内置 chords-db 资产', () {
    test('真实 ukulele.json 通过校验且含新手套件', () async {
      final text = await rootBundle.loadString('assets/chords/ukulele.json');
      final lib = ChordLibrary.parse(text);
      expect(lib.chords.length, greaterThanOrEqualTo(20));
      const beginnerKit = [
        'C', 'G', 'Am', 'F', 'G7', 'Em', 'Dm', 'D', 'E7', 'A7',
      ];
      final labels = lib.chords.map((c) => c.label).toSet();
      for (final label in beginnerKit) {
        expect(labels, contains(label), reason: '新手套件缺 $label');
      }
    });
  });

group('Chord.primaryFingering', () {
  ChordFingering f(List<int> frets, {int baseFret = 1}) => ChordFingering(
    frets: frets,
    fingers: [1, 1, 1, 1],
    baseFret: baseFret,
    barres: const [],
  );

  test('优先第一品窗口，其次空弦多，再次品位和低', () {
    final chord = Chord(
      root: 'A',
      suffix: 'sus2',
      fingerings: [
        f([1, 3, 4, 1], baseFret: 2), // 高把位横按
        f([4, 4, 5, 7], baseFret: 4), // 更高把位
        f([2, 0, 0, 0]), // 第一品多空弦
      ],
    );
    expect(chord.primaryFingering.frets, [2, 0, 0, 0]);
  });

  test('并列时保持数据序取最前', () {
    final chord = Chord(
      root: 'C',
      suffix: 'major',
      fingerings: [f([0, 0, 0, 3]), f([3, 2, 1, 1], baseFret: 3)],
    );
    expect(chord.primaryFingering, same(chord.fingerings.first));
  });

  test('真实资产：C 的主指法是 0003', () async {
    final text = await rootBundle.loadString('assets/chords/ukulele.json');
    final lib = ChordLibrary.parse(text);
    final c = lib.chords.singleWhere((c) => c.label == 'C');
    expect(c.primaryFingering.frets, [0, 0, 0, 3]);
  });
});

group('内容一致性', () {
  test('常用套件每个和弦都有人工撰写的要点文案', () {
    for (final label in commonChordKit) {
      expect(
        curatedChordTips.containsKey(label),
        isTrue,
        reason: '常用套件 $label 缺要点文案，会静默退化成通用提示',
      );
    }
  });
});
}
