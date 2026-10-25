import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/model/tab_chart.dart';
import 'package:ukeflow/core/practice/score_sheet_layout.dart';

/// 谱面布局内核(工单 39 测试缝①):(组合定义) → 连续横带坐标 + 四层
/// 元素坐标 + 简谱符号推导 + 跟随高亮当位查询。纯函数,零引擎依赖。
/// 推导规则用合成旋律逐符号锁定;横带几何/当位查询用真数据(首曲)。
void main() {
  final charts = {for (final e in builtinTabChartCatalog) e.id: e.chart};
  final def = scoreSheetCatalog.single;
  final solo = charts[def.tabChartId]!;
  final melody = charts[def.melodyChartId]!;

  final l = ScoreSheetLayout(
    def: def,
    tabChart: solo,
    melodyChart: melody,
  );

  group('横带几何:时值即距离,和弦图居中压锚拍', () {
    test('stripX 分段线性:拍位×像素 + 带首留白 + 小节空气', () {
      final inset = ScoreSheetLayout.barInset;
      // 拍 0 在带首 + 一格空气(不压行首)。
      expect(l.stripX(0), ScoreSheetLayout.stripLeftPad + inset);
      // 跨小节线:整体再右移一格(小节加宽)。
      expect(l.stripX(4),
          ScoreSheetLayout.stripLeftPad + 4 * ScoreSheetLayout.stripPxPerBeat + 2 * inset);
      // 同小节内仍线性(时值即距离)。
      expect(l.stripX(4.5) - l.stripX(4), 0.5 * ScoreSheetLayout.stripPxPerBeat);
    });

    test('横带宽度收在主轴网格(27 小节)+ 右留白', () {
      expect(l.barCount, 27);
      expect(l.stripWidth, l.barX(27) + ScoreSheetLayout.stripRightPad);
    });

    test('和弦图居中压在其锚拍上,与带首留有距离(照印张对应关系)', () {
      // 首锚 E@4:中心在 stripX(4),不贴行首。
      final first = l.chordGlyphs.first;
      expect(first.anchor.label, 'E');
      expect(first.x,
          l.stripX(4) - ScoreSheetLayout.chordGlyphWidth / 2);
      expect(first.x, greaterThan(ScoreSheetLayout.stripLeftPad),
          reason: '和弦图与带首有距离');
      // 两两不叠且按拍序排布。
      for (var i = 1; i < l.chordGlyphs.length; i++) {
        expect(l.chordGlyphs[i].x,
            greaterThanOrEqualTo(l.chordGlyphs[i - 1].x +
                ScoreSheetLayout.chordGlyphWidth));
      }
    });

    test('TAB/简谱音点绝对坐标 = 拍位映射,简谱含对齐偏移', () {
      expect(l.tabPoints.first.note.beat, 4.0);
      expect(l.tabPoints.first.x, l.stripX(4.0));
      expect(l.numPoints.first.symbol.lyric, '你');
      expect(l.numPoints.first.x, l.stripX(20.0), reason: '你 = 旋律 0 + 20');
    });

    test('全休止小节只有前奏 bar 0', () {
      expect(l.emptyBars, [0]);
    });

    test('TAB 节奏带:符杆下垂、同拍组符杠横连、孤立组符尾(industry 画法)', () {
      // 主歌两拍单元 @20(距下组 0.5)= 八分:有杆有杠。
      final g20 = l.tabPoints.firstWhere((p) => p.note.beat == 20.0);
      expect(g20.groupDuration, 0.5);
      expect(
        l.rhythmBeams.any((bm) => bm.x0 <= g20.x && g20.x <= bm.x1),
        isTrue,
        reason: '连续八分组应符杠横连',
      );
      // b5 末音 ①8@18(距下组 2 拍)= 长音:裸长杆 + 延音,无杠无尾。
      final g18 = l.tabPoints.firstWhere((p) => p.note.beat == 18.0);
      expect(g18.groupDuration, 2.0);
      expect(g18.groupHoldBeats, isTrue);
      expect(g18.groupEndX, l.stripX(20.0));
      expect(l.rhythmBeams.any((bm) => bm.x0 == g18.x), isFalse);
      // 符尾只出现在无杠的可连组上。
      for (final f in l.rhythmFlags) {
        expect(
          l.rhythmBeams.any((bm) => f.x >= bm.x0 && f.x <= bm.x1),
          isFalse,
        );
      }
    });

    test('节奏带合成小节:四分裸杆/八分连杠/十六分双杠/孤立符尾', () {
      const synthetic = TabChart(
        title: '节奏用',
        tempo: 78,
        notes: [
          TabNote(string: 1, fret: 0, beat: 0), // 四分:裸杆
          TabNote(string: 1, fret: 0, beat: 1), // 八分 ┐同拍窗符杠
          TabNote(string: 1, fret: 0, beat: 1.5), // 八分 ┘
          TabNote(string: 1, fret: 0, beat: 2), // 十六分 ┐双杠
          TabNote(string: 1, fret: 0, beat: 2.25), // 十六分 ┘
          TabNote(string: 1, fret: 0, beat: 2.5), // 八分(裸杆,时值到 3.5)
          TabNote(string: 1, fret: 0, beat: 3.5), // 孤立八分:符尾 1
        ],
      );
      final rl = ScoreSheetLayout(
        def: def,
        tabChart: synthetic,
        melodyChart: synthetic,
      );
      expect(rl.rhythmStems, hasLength(7)); // 0/1/1.5/2/2.25/2.5/3.5
      // 四分裸杆:不在任何杠上。
      final x0 = rl.stripX(0);
      expect(rl.rhythmBeams.any((bm) => x0 >= bm.x0 && x0 <= bm.x1), isFalse);
      // 八分对 @1/@1.5 一条一级杠。
      expect(
        rl.rhythmBeams.where((bm) => bm.level == 1).map((bm) => bm.x0),
        contains(rl.stripX(1)),
      );
      // 十六分对 @2/@2.25 有二级杠。
      expect(
        rl.rhythmBeams.any((bm) =>
            bm.level == 2 &&
            bm.x0 == rl.stripX(2) &&
            bm.x1 == rl.stripX(2.25)),
        isTrue,
      );
      // 孤立八分 @3.5:符尾 1(不在同拍窗伙伴)。
      final flag35 = rl.rhythmFlags.firstWhere((f) => f.x == rl.stripX(3.5));
      expect(flag35.flags, 1);
    });

    test('连音×柱:扫弦段小节第 3 拍无攻击处(86/90/102/106)', () {
      expect(l.tiedColumns, [86.0, 90.0, 102.0, 106.0]);
      // 数据空档互证:这些拍确实无音。
      for (final beat in l.tiedColumns) {
        expect(l.tabPoints.where((p) => p.note.beat == beat), isEmpty);
      }
    });

    test('纵带坐标单源:静态带与当位覆盖层共用(间距改动只动内核)', () {
      // 真机教训:间距调整后覆盖层公式没跟上,当前音/歌词错位 8px。
      expect(ScoreSheetLayout.tabBandTop, 96.0); // 68 + 20 + 8
      expect(ScoreSheetLayout.tabBandBottom, 138.0); // 96 + 42
      expect(ScoreSheetLayout.rhythmBandTop, 144.0); // 底 + 6
      expect(ScoreSheetLayout.numBandTop, 171.0); // 68 + 20 + 58 + 25(节奏带)
      expect(
        ScoreSheetLayout.numCenterY,
        ScoreSheetLayout.numBandTop + 8 + ScoreSheetLayout.numFontSize / 2,
      );
      expect(
        ScoreSheetLayout.lyricCenterY,
        ScoreSheetLayout.numBandTop + ScoreSheetLayout.numBandHeight +
            ScoreSheetLayout.lyricBandHeight / 2,
      );
      // 层序:和弦带 < 琴弦 < 简谱 < 歌词。
      expect(ScoreSheetLayout.tabBandTop,
          lessThan(ScoreSheetLayout.numBandTop));
      expect(ScoreSheetLayout.numCenterY,
          lessThan(ScoreSheetLayout.lyricCenterY));
    });
  });

  group('简谱符号推导(合成旋律逐符号)', () {
    // 1=C 第一把位合成旋律:规则全覆盖(八分/十六分/附点/延音线/休止/长音)。
    final synthetic = TabChart(
      title: '推导用',
      tempo: 78,
      notes: [
        // 拍 0: 5(八分)~5(延音线,八分)——同音连线。
        const TabNote(string: 2, fret: 3, beat: 0, lyric: 'a'),
        const TabNote(string: 2, fret: 3, beat: 0.5),
        // 拍 1: 1(十六分,高音一点;①3 = C5)。
        const TabNote(string: 1, fret: 3, beat: 1, lyric: 'b'),
        // 拍 1.25: 5(附点八分=0.75)。
        const TabNote(string: 2, fret: 3, beat: 1.25),
        // 拍 2: 3(整拍)。
        const TabNote(string: 2, fret: 0, beat: 2, lyric: 'c'),
        // 拍 3: 7(整拍,高音零点;①2 = B4)。
        const TabNote(string: 1, fret: 2, beat: 3, lyric: 'd'),
        // 拍 4: 5(八分)+ 延续音拖 1 拍 + 休止 1.5(后继远跳)。
        const TabNote(string: 2, fret: 3, beat: 4, lyric: 'e'),
        const TabNote(string: 2, fret: 3, beat: 4.5),
        // 拍 7: 6(尾音,网格收在 bar 尽头)。
        const TabNote(string: 1, fret: 0, beat: 7, lyric: 'f'),
      ],
    );

    final notes = deriveNumberedNotes(synthetic);

    test('度数与八度点自音高推导,与 C 指位数据无关', () {
      expect(notes[0].degree, 5); // G4
      expect(notes[0].highDots, 0);
      expect(notes[0].lowDots, 0);
      expect(notes[2].degree, 1, reason: '①3 = C5 = 度 1');
      expect(notes[2].highDots, 1);
      expect(notes[3].degree, 5); // G4
      expect(notes[4].degree, 3); // E4
      expect(notes[5].degree, 7); // B4 = ①2
      expect(notes[5].highDots, 0);
      expect(notes[8].degree, 6); // A4 = ①0(f@7)
    });

    test('时值线:八分单线/十六分双线/附点/整拍横杠', () {
      expect(notes[0].underlines, 1, reason: '八分单线');
      expect(notes[2].underlines, 2, reason: '十六分双线');
      expect(notes[2].dotted, isFalse);
      expect(notes[3].underlines, 1);
      expect(notes[3].dotted, isTrue, reason: '0.75 = 附点八分');
      expect(notes[4].underlines, 0);
      expect(notes[4].dotted, isFalse);
      expect(notes[4].dashes, 0, reason: '整拍 = 素数');
      // 尾音 A4@7:网格收 8,d = 1.0。
      expect(notes[7].dashes, 0);
    });

    test('延音线弧:后继延续音(无缀字)出弧', () {
      expect(notes[0].arcOut, isTrue, reason: 'a → 同音延续');
      expect(notes[1].arcOut, isFalse);
      expect(notes[6].arcOut, isTrue, reason: 'e → 拖腔延续音');
    });

    test('休止 0:延续音满 1 拍封顶,余量出休止', () {
      // notes 顺序:0:a 1:tie(a) 2:b 3:dot8 4:c 5:d 6:e 7:tie(e) 8:f。
      // e@4(0.5)→ 延续@4.5,距下音 2.5:延续音记 1 拍,余 1.5 出 0。
      expect(notes[6].restAfter, isNull, reason: '本音(attack)不出休止');
      final tieOfE = notes[7];
      expect(tieOfE.lyric, isNull);
      expect(tieOfE.underlines, 0, reason: '封顶 1 拍 = 素四分');
      expect(tieOfE.restAfter, 1.5, reason: 'd=2.5 → 本音 1 拍 + 休止 1.5');
    });

    test('对齐偏移:mainBeat 落主轴拍(弧线端点按主轴坐标消费)', () {
      final aligned = deriveNumberedNotes(melody, alignBeats: 20);
      expect(aligned.first.mainBeat, 20.0, reason: '你 = 旋律拍 0 + 20');
      expect(aligned.last.mainBeat, 107.5, reason: '念 = 87.5 + 20');
      // 缺省不过偏移(合成旋律直接推导的既有用例不受影响)。
      expect(deriveNumberedNotes(melody).first.mainBeat, 0.0);
    });

    test('非自然音级当场报错(数据缺陷不静默进渲染)', () {
      const chromatic = TabChart(
        title: '坏数据',
        tempo: 78,
        notes: [TabNote(string: 1, fret: 1, beat: 0)], // ①1 = A#4
      );
      expect(() => deriveNumberedNotes(chromatic), throwsArgumentError);
    });

    test('真数据:旋律全曲可推导,副歌高置段(A5=6 一点)', () {
      final real = deriveNumberedNotes(melody, alignBeats: 20);
      expect(real, hasLength(168));
      final nian = real.last; // 念 = ①12 = A5,全曲最高。
      expect(nian.degree, 6);
      expect(nian.highDots, 1,
          reason: '八度点自实际音高(简谱 C4..B4 无点);印张点数=实际+1,目验知悉');
      final liang = real.firstWhere((n) => n.lyric == '两'); // G4 低起
      expect(liang.degree, 5);
      expect(liang.highDots, 0);
    });
  });

  group('TAB 印张 × 判定:落指形位画 ×,旋律音保持数字', () {
    bool pluckAt(double beat, int string) => l.tabPoints
        .firstWhere(
          (p) => p.note.beat == beat && p.note.string == string,
          orElse: () => throw TestFailure('找不到音 @$beat ④③②① 下标 $string'),
        )
        .isChordPluck;

    test('和弦堆/拨弦(品位=当前指形按位)判 ×', () {
      // b4 A 堆 @12.0:A=[2,1,0,0](④2③1②0)→ ④③② 全 ×。
      expect(pluckAt(12.0, 4), isTrue);
      expect(pluckAt(12.0, 3), isTrue);
      expect(pluckAt(12.0, 2), isTrue);
      // 前奏 b2 E 堆 @4.0:E=[4,4,4,2] → 全 ×。
      for (final p in l.tabPoints.where((p) => p.note.beat == 4.0)) {
        expect(p.isChordPluck, isTrue, reason: '${p.note}');
      }
    });

    test('旋律品位不落指形位 → 保持数字(false)', () {
      // b4 旋律 ①2=B4 @12.0(印张数字②):A 指形 ①=0 ≠ 2。
      expect(pluckAt(12.0, 1), isFalse);
      // b5 末音 ①8=F5 @18.0(印张数字⑧):E 指形 ①=2 ≠ 8。
      expect(pluckAt(18.0, 1), isFalse);
    });

    test('扫弦拍:落指形的 × 被事件遮蔽,旋律数字保留', () {
      // @84.0 卷弦段扫弦(下扫):四弦 × 全遮蔽。
      final strums84 = l.tabPoints.where((p) => p.note.beat == 84.0);
      expect(strums84, hasLength(4));
      for (final p in strums84) {
        expect(p.hiddenByStrum, isTrue, reason: '${p.note}');
      }
      // @12.0 堆+旋律(非扫弦):堆 × 保留、旋律 ①2 保留。
      final b12 = l.tabPoints.where((p) => p.note.beat == 12.0);
      expect(b12, hasLength(4));
      expect(b12.every((p) => !p.hiddenByStrum), isTrue);
      // 种类查询:卷弦 vs 上扫;@9.5 已改休止占位(不再是下扫)。
      expect(l.strumKindAt(4.0), ScoreStrumKind.roll);
      expect(l.strumKindAt(9.5), isNull, reason: '照印张为二拍休止占位');
      expect(l.strumKindAt(7.5), isNull, reason: '拍7.5 照印张为单音①2,非扫弦');
      expect(l.strumKindAt(12.0), isNull);
      // 休止事件:x 落在两个卷弦波浪之间(拍 7)。
      expect(l.restEvents.map((r) => r.beat), contains(7.0));
      final rest7 = l.restEvents.firstWhere((r) => r.beat == 7.0);
      expect(rest7.x, l.stripX(7.0));
    });

    test('主歌两拍单元(b6 起,拍 20+)逐音 ×', () {
      for (final p in l.tabPoints.where((p) => p.note.beat >= 20)) {
        expect(p.isChordPluck, isTrue, reason: '主歌单元应全 ×:${p.note}');
      }
    });
  });

  group('跟随高亮当位查询', () {
    test('预备期拍 0-20:有 TAB 当前音与当前和弦,简谱无当前音', () {
      final c = l.currentAt(19.5);
      expect(c.chordIndex, def.chords.indexWhere((ch) => ch.beat == 16),
          reason: '前奏末锚 E@16');
      expect(c.melodyIndex, -1, reason: '旋律 20 拍起');
      expect(c.tabIndex, greaterThanOrEqualTo(0));
    });

    test('主歌拍 21.5:和弦 E@20,简谱当前音=信@1.5(+20),歌词逐字', () {
      final c = l.currentAt(21.5);
      expect(c.chordIndex, def.chords.indexWhere((ch) => ch.beat == 20));
      final symbol = deriveNumberedNotes(melody, alignBeats: 20)[c.melodyIndex];
      expect(symbol.lyric, '信');
    });

    test('副歌拍 84.5:和弦 E@84,简谱当前音=三@64.5(+20)', () {
      final c = l.currentAt(84.5);
      expect(c.chordIndex, def.chords.indexWhere((ch) => ch.beat == 84));
      final symbol = deriveNumberedNotes(melody, alignBeats: 20)[c.melodyIndex];
      expect(symbol.lyric, '三');
    });

    test('曲末尾拍(>网格):钳到最后锚/音,不越界', () {
      final c = l.currentAt(120);
      expect(c.chordIndex, def.chords.length - 1);
      expect(c.tabIndex, l.tabPoints.length - 1);
      expect(c.melodyIndex, l.numPoints.length - 1);
      final c0 = l.currentAt(-1);
      expect(c0.chordIndex, -1);
      expect(c0.tabIndex, -1);
      expect(c0.melodyIndex, -1);
    });
  });

  test('布局确定性:同入参同输出(缓存几何不随调用漂移)', () {
    final b = ScoreSheetLayout(def: def, tabChart: solo, melodyChart: melody);
    expect(l.stripWidth, b.stripWidth);
    expect(l.tabPoints.map((p) => p.x), b.tabPoints.map((p) => p.x));
    expect(l.chordGlyphs.map((g) => g.x), b.chordGlyphs.map((g) => g.x));
  });
}
