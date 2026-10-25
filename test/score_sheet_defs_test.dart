import 'package:flutter_test/flutter_test.dart';

import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';

/// 组合定义(ADR-0008)数据完整性:三源 id 可解析、和弦行拍锚有序合法、
/// 指形照工单 37 台账。数据坏损在这里当场红,不进渲染层。
void main() {
  final charts = {for (final e in builtinTabChartCatalog) e.id: e.chart};

  test('每份组合定义:TAB/旋律两层 id 都对得上内置指弹谱,对齐偏移为整拍', () {
    for (final def in scoreSheetCatalog) {
      expect(charts[def.tabChartId], isNotNull,
          reason: '${def.id}:TAB 伴奏层 id 缺谱');
      expect(charts[def.melodyChartId], isNotNull,
          reason: '${def.id}:简谱旋律层 id 缺谱');
      expect(def.melodyAlignBeats, greaterThanOrEqualTo(0));
      expect(def.melodyAlignBeats % 0.5, 0.0,
          reason: '${def.id}:旋律对齐偏移应为半拍整数');
    }
  });

  test('爱你不是两三天:主轴=独奏谱 485 音 78bpm,旋律 168 音 +20 对齐', () {
    final def = scoreSheetCatalog.single;
    expect(def.id, 'ai-ni-bu-shi-liang-san-tian-solo');
    expect(def.title, '爱你不是两三天');
    expect(def.keySignature, '1=E');
    final tab = charts[def.tabChartId]!;
    final melody = charts[def.melodyChartId]!;
    expect(tab.tempo, 78);
    expect(tab.notes.length, 485);
    expect(melody.notes.length, 168);
    // 恒定偏移:旋律任一音 +20 必须落在主轴网格内(抽样首尾)。
    final melodyBeats = melody.notes.map((n) => n.beat).toList()..sort();
    expect(melodyBeats.first + def.melodyAlignBeats, 20.0);
    expect(melodyBeats.last + def.melodyAlignBeats, 107.5);
  });

  test('和弦行拍锚:升序不重拍、全部落在主轴网格内', () {
    final def = scoreSheetCatalog.single;
    final tab = charts[def.tabChartId]!;
    for (var i = 1; i < def.chords.length; i++) {
      expect(def.chords[i].beat, greaterThan(def.chords[i - 1].beat),
          reason: '拍锚须严格升序:@${def.chords[i].beat}');
    }
    for (final anchor in def.chords) {
      expect(anchor.beat, greaterThanOrEqualTo(0));
      expect(anchor.beat, lessThan(108), reason: '${anchor.label}@${anchor.beat}');
      expect(anchor.beat % 2.0, 0.0, reason: '和弦逐 2 拍一换:${anchor.label}');
      expect(tab.notes.every((n) => n.beat >= 0), isTrue);
    }
  });

  test('和弦行覆盖:前奏/主歌/副歌/尾句关键锚逐个在位(照工单 37 台账)', () {
    final def = scoreSheetCatalog.single;
    String at(double beat) {
      final hits = def.chords.where((c) => c.beat == beat).toList();
      expect(hits, hasLength(1), reason: '拍 $beat 应恰有一个锚');
      return hits.single.label;
    }

    // 前奏 b2-5:E-A-B-Bsus4-A-B-E(工单 37 前奏台账名字列)。
    expect(at(4), 'E');
    expect(at(6), 'A');
    expect(at(8), 'B');
    expect(at(10), 'Bsus4');
    expect(at(12), 'A');
    expect(at(14), 'B');
    expect(at(16), 'E');
    // 主歌两遍:|E A|B C#m7|A B|E|(b6-9 → 拍 20-36)。
    expect(at(20), 'E');
    expect(at(22), 'A');
    expect(at(24), 'B');
    expect(at(26), 'C#m7');
    expect(at(28), 'A');
    expect(at(30), 'B');
    expect(at(32), 'E');
    expect(at(36), 'E');
    expect(at(42), 'C#m7');
    expect(at(48), 'E');
    // 移位句 |E|A B|C#m7 A|B E|(b14-17 → 拍 52-68)。
    expect(at(52), 'E');
    expect(at(56), 'A');
    expect(at(58), 'B');
    expect(at(60), 'C#m7');
    expect(at(62), 'A');
    expect(at(64), 'B');
    expect(at(66), 'E');
    // 副歌A |A E|G#7 C#m7|A B|B 卷弦收|(b18-21 → 拍 68-84)。
    expect(at(68), 'A');
    expect(at(70), 'E');
    expect(at(72), 'G#7');
    expect(at(74), 'C#m7');
    expect(at(76), 'A');
    expect(at(78), 'B');
    expect(at(80), 'B');
    // 副歌B 高置段 |E|G#7 C#m7|A E|(b22-24 → 拍 84-96)。
    expect(at(84), 'E');
    expect(at(88), 'G#7');
    expect(at(90), 'C#m7');
    expect(at(92), 'A');
    expect(at(94), 'E');
    // 尾 |F#m D7|E|G#7|(b25-27 → 拍 96-108)。
    expect(at(96), 'F#m');
    expect(at(98), 'D7');
    expect(at(100), 'E');
    expect(at(104), 'G#7');
    // 小节1(拍 0-4)全休止,无锚。
    expect(def.chords.every((c) => c.beat >= 4), isTrue);
  });

  test('指形形状照工单 37 台账(frets ④③②① 序):E=4442 A=2100 B=4322 '
      'C#m7=4444 G#7=1323 F#m=2120 D7={①3③2} 闷音柱 Bsus4=4444', () {
    final def = scoreSheetCatalog.single;
    (List<int>, List<int>) shapeOf(String label) {
      final anchors = def.chords.where((c) => c.label == label).toList();
      expect(anchors, isNotEmpty, reason: '缺 $label 锚');
      final f = anchors.first.fingering;
      return (f.frets, f.barres);
    }

    void expectShape(String label, List<int> frets, List<int> barres) {
      final (actualFrets, actualBarres) = shapeOf(label);
      expect(actualFrets, frets, reason: '$label 品位(④③②①)');
      expect(actualBarres, barres, reason: '$label 横按');
    }

    // 闷音柱 × = -1;横按只 C#m7/Bsus4(4444 同形)。数字串 ④ 弦起读,
    // 与谱卡逐音互证(E 堆 ④4③4②4①2 =「4442」)。
    expectShape('E', [4, 4, 4, 2], []);
    expectShape('A', [2, 1, 0, 0], []);
    expectShape('B', [4, 3, 2, 2], []);
    expectShape('C#m7', [4, 4, 4, 4], [4]);
    expectShape('G#7', [1, 3, 2, 3], []);
    expectShape('F#m', [2, 1, 2, 0], []);
    expectShape('D7', [-1, 2, -1, 3], []);
    expectShape('Bsus4', [4, 4, 4, 4], [4]);
    // 同名锚指形一致(数据不漂移)。
    for (final label in ['E', 'A', 'B', 'C#m7', 'G#7', 'F#m', 'D7', 'Bsus4']) {
      final anchors = def.chords.where((c) => c.label == label).toList();
      expect(
        anchors.map((c) => c.fingering.frets).toSet(),
        hasLength(1),
        reason: '$label 各锚指形应一致',
      );
    }
  });

  test('扫弦事件表:每个事件拍都有同拍 ≥3 音且落指形的组(与谱卡互证)', () {
    final def = scoreSheetCatalog.single;
    final tab = charts[def.tabChartId]!;
    final shapes = <String, List<int>>{};
    for (final c in def.chords) {
      shapes.putIfAbsent(c.label, () => c.fingering.frets);
    }
    String chordAt(double beat) {
      String? hit;
      for (final c in def.chords) {
        if (c.beat <= beat) hit = c.label;
      }
      return hit!;
    }

    for (final e in def.strums) {
      final group = tab.notes.where((n) => n.beat == e.beat).toList();
      expect(group.length, greaterThanOrEqualTo(3),
          reason: '@${e.beat} 应为扫弦组');
      final shape = shapes[chordAt(e.beat)]!;
      final plucks = group
          .where((n) => shape[4 - n.string] == n.fret)
          .length;
      expect(plucks, greaterThanOrEqualTo(3),
          reason: '@${e.beat} 扫弦组至少 3 弦落指形');
    }
    // 主歌(拍 20-68)无扫弦(全拨堆)。
    expect(def.strums.where((e) => e.beat >= 20 && e.beat < 68), isEmpty);
    // b4 @12.0(堆+旋律①2)不是扫弦。
    expect(def.strums.any((e) => e.beat == 12.0), isFalse);
    // 休止事件:b2 卷弦 A 后八分休止(拍 7)、b3 下扫位为二拍休止占位(9.5)。
    expect(def.rests.map((r) => (r.beat, r.beats)),
        containsAll([(7.0, 0.5), (9.5, 2.0)]));
    expect(def.strums.any((e) => e.beat == 9.5), isFalse,
        reason: '下扫位照印张为休止占位');
    // 2026-10-25 印张像素实测:b3 拍 9.5-10.5 整段休止;b4@14 为卷弦;
    // b5 无上扫箭头;b22@82 为椭圆框震音柱(非下扫)。
    expect(
      def.strums.where((e) => e.beat >= 9.5 && e.beat < 10.5),
      isEmpty,
      reason: '二拍休止区间内无扫弦',
    );
    expect(def.strums.firstWhere((e) => e.beat == 14.0).kind,
        ScoreStrumKind.roll, reason: '@14 印张为波浪(卷弦)');
    expect(def.strums.where((e) => e.beat == 17.0 || e.beat == 17.5),
        isEmpty, reason: 'b5 印张无上扫箭头');
    expect(def.strums.any((e) => e.beat == 82.0), isFalse,
        reason: '@82 为震音柱');
    expect(def.tremolos.map((t) => t.beat), [82.0]);
    // 数据侧:休止区间内无音(误读堆音已删,发声与印张一致)。
    final charts2 = {
      for (final e in builtinTabChartCatalog) e.id: e.chart,
    };
    final solo2 = charts2[def.tabChartId]!;
    expect(solo2.notes.where((n) => n.beat >= 9.5 && n.beat < 10.5),
        isEmpty, reason: '拍 9.5-10.5 照印张为休止');
    // 升序不重拍。
    for (var i = 1; i < def.strums.length; i++) {
      expect(def.strums[i].beat, greaterThan(def.strums[i - 1].beat));
    }
  });
}
