import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/chord_library.dart';
import 'package:ukeflow/features/chords/chord_tips.dart';

/// 文案 ↔ 数据一致性守护（G7 文案事故的永久防波堤）：
/// 「按法要点」遵循固定语法，解析出每根弦的（品位, 手指）后与
/// chords-db 真实资产的主指法逐项比对，多写、漏写、写错都算失败。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fingerNames = {
    '食指': 1, '中指': 2, '无名指': 3, '小指': 4,
  };
  // 弦标句式「圈号+音名」(④G ③C ②E ①A,与指法图弦标一致)。
  final glyphByLetter = const {'G': '④', 'C': '③', 'E': '②', 'A': '①'};
  final stringRefRe = RegExp(r'([①②③④])([GCEA])');
  final frettedRe = RegExp(
    r'(食指|中指|无名指|小指)?按 ([①②③④])([GCEA])弦 (\d) 品(（(食指|中指|无名指|小指)）)?',
  );
  final barreRe = RegExp(r'食指横按 ((?:[①②③④][GCEA](?:、)?)+)弦的 (\d) 品');
  final openRe = RegExp(r'((?:[①②③④][GCEA](?:、)?)+)弦空');

  /// 圈号必须与音名配对(④G 而非 ①G)——写反了新手会按错弦。
  void checkPair(RegExpMatch m, int glyphGroup, int letterGroup) =>
      expect(
        glyphByLetter[m.group(letterGroup)!],
        m.group(glyphGroup)!,
        reason: '弦标 ${m.group(0)} 的圈号与音名不配对',
      );

  /// 从语法化文案解析 (弦名 → (绝对品位, 手指)) 与空弦集合。
  (Map<String, (int, int)>, Set<String>) parseEssence(String essence) {
    final fretted = <String, (int, int)>{};
    var rest = essence;
    for (final m in barreRe.allMatches(rest)) {
      for (final c in stringRefRe.allMatches(m.group(1)!)) {
        checkPair(c, 1, 2);
        fretted[c.group(2)!] = (int.parse(m.group(2)!), 1);
      }
      rest = rest.replaceFirst(m.group(0)!, '');
    }
    for (final m in frettedRe.allMatches(rest)) {
      final fingerName = m.group(1) ?? m.group(6);
      checkPair(m, 2, 3);
      fretted[m.group(3)!] = (
        int.parse(m.group(4)!),
        fingerNames[fingerName!]!,
      );
    }
    final opens = <String>{};
    for (final m in openRe.allMatches(rest)) {
      for (final c in stringRefRe.allMatches(m.group(1)!)) {
        checkPair(c, 1, 2);
        opens.add(c.group(2)!);
      }
    }
    if (rest.contains('四根弦全部空')) {
      opens.addAll(const ['G', 'C', 'E', 'A']);
    } else if (rest.contains('其余')) {
      opens.addAll(
        {'G', 'C', 'E', 'A'}.where((s) => !fretted.containsKey(s)),
      );
    }
    return (fretted, opens);
  }

  test('25 条要点文案与真实资产主指法逐项一致', () async {
    final text = await rootBundle.loadString('assets/chords/ukulele.json');
    final lib = ChordLibrary.parse(text);
    final byLabel = {for (final c in lib.chords) c.label: c};
    expect(byLabel.keys, containsAll(commonChordKit));

    for (final label in commonChordKit) {
      final essence = curatedChordTips[label]!.$1;
      final f = byLabel[label]!.primaryFingering;
      final dataFretted = <String, (int, int)>{
        for (var i = 0; i < 4; i++)
          if (f.frets[i] >= 1)
            const ['G', 'C', 'E', 'A'][i]: (f.frets[i] + f.baseFret - 1, f.fingers[i]),
      };
      final dataOpens = <String>{
        for (var i = 0; i < 4; i++)
          if (f.frets[i] == 0) const ['G', 'C', 'E', 'A'][i],
      };
      final (saidFretted, saidOpens) = parseEssence(essence);
      expect(
        saidFretted,
        dataFretted,
        reason: '$label 要点的指弦声明与数据不符\n文案：$essence',
      );
      expect(saidOpens, dataOpens, reason: '$label 要点的空弦声明与数据不符');
    }
  });

  group('genericChordTips 横按手指派生(审计30 #24)', () {
    ChordFingering fingering(List<int> frets, List<int> fingers,
            {List<int> barres = const [], int baseFret = 1}) =>
        ChordFingering(
          frets: frets,
          fingers: fingers,
          baseFret: baseFret,
          barres: barres,
        );

    test('横按手指从指法数据派生,不再永远写食指', () {
      // 横按品位(窗口内 1)上的手指标是 2(中指):文案必须说中指
      // (④弦 2 品由无名指按、①②③弦 1 品中指横按的形状)。
      final tip = genericChordTips(fingering(
        [2, 1, 1, 1],
        [3, 2, 2, 2],
        barres: [1],
      ));
      expect(tip, contains('中指横按'));
      expect(tip, isNot(contains('食指横按')));
    });

    test('食指横按仍是食指(既有文案不回退)', () {
      final tip = genericChordTips(fingering(
        [3, 1, 1, 1],
        [3, 1, 1, 1],
        barres: [1],
      ));
      expect(tip, contains('食指横按'));
    });

    test('无横按不提横按', () {
      final tip = genericChordTips(fingering([0, 2, 3, 0], [0, 2, 4, 0]));
      expect(tip, isNot(contains('横按')));
    });
  });

}
