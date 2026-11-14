import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/model/tab_chart.dart';
import 'package:ukeflow/core/practice/score_sheet_layout.dart';

import 'helpers/score_sheet_fixture.dart';

/// 谱面布局内核(工单 39 测试缝①):(组合定义) → 连续横带坐标 + 四层
/// 元素坐标 + 简谱符号推导 + 跟随高亮当位查询。纯函数,零引擎依赖。
/// ADR-0013 删内置曲后,横带几何/当位查询改用合成组合夹具
/// (helpers/score_sheet_fixture.dart):2 小节,锚/卷弦/休止/滑音/震音/
/// 堆/长音组各一,断言逐符号锁定,不再依赖真实歌曲数据。
void main() {
  final l = ScoreSheetLayout(
    def: sheetFixtureDef,
    tabChart: sheetFixtureTab,
    melodyChart: sheetFixtureMelody,
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

    test('横带宽度收在主轴网格(2 小节)+ 右留白', () {
      expect(l.barCount, 2);
      expect(l.stripWidth, l.barX(2) + ScoreSheetLayout.stripRightPad);
    });

    test('和弦图压在其锚拍右侧 12px,与带首留有距离', () {
      // 唯一锚 C@4:中心在拍位右侧 12px,不贴行首。
      final first = l.chordGlyphs.first;
      expect(first.anchor.label, 'C');
      expect(first.x,
          l.stripX(4) +
              ScoreSheetLayout.chordRightNudge -
              ScoreSheetLayout.chordGlyphWidth / 2);
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
      expect(l.numPoints.first.x, l.stripX(4.0), reason: '你 = 旋律 0 + 4');
    });

    test('全休止小节只有前奏 bar 0', () {
      expect(l.emptyBars, [0]);
    });

    test('TAB 节奏带:符杆下垂、同拍组符杠横连、长音组裸杆延音', () {
      // 堆@4(距下组 0.5)= 八分:有杆有杠。
      final g4 = l.tabPoints.firstWhere((p) => p.note.beat == 4.0);
      expect(g4.groupDuration, 0.5);
      expect(
        l.rhythmBeams.any((bm) => bm.x0 <= g4.x && g4.x <= bm.x1),
        isTrue,
        reason: '连续八分组应符杠横连',
      );
      // ①5@5(距下组 2 拍)= 长音:裸长杆 + 延音,无杠无尾。
      final g5 = l.tabPoints.firstWhere((p) => p.note.beat == 5.0);
      expect(g5.groupDuration, 2.0);
      expect(g5.groupHoldBeats, isTrue);
      expect(g5.groupEndX, l.stripX(7.0));
      expect(l.rhythmBeams.any((bm) => bm.x0 == g5.x), isFalse);
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
        def: sheetFixtureDef,
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

    test('连音×柱:扫弦段小节第 3 拍无攻击处(@6)', () {
      expect(l.tiedColumns, [6.0]);
      // 数据空档互证:该拍确实无音。
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
    const synthetic = TabChart(
      title: '推导用',
      tempo: 78,
      notes: [
        // 拍 0: 5(八分)~5(延音线,八分)——同音连线。
        TabNote(string: 2, fret: 3, beat: 0, lyric: 'a'),
        TabNote(string: 2, fret: 3, beat: 0.5),
        // 拍 1: 1(十六分,高音一点;①3 = C5)。
        TabNote(string: 1, fret: 3, beat: 1, lyric: 'b'),
        // 拍 1.25: 5(附点八分=0.75)。
        TabNote(string: 2, fret: 3, beat: 1.25),
        // 拍 2: 3(整拍)。
        TabNote(string: 2, fret: 0, beat: 2, lyric: 'c'),
        // 拍 3: 7(整拍,高音零点;①2 = B4)。
        TabNote(string: 1, fret: 2, beat: 3, lyric: 'd'),
        // 拍 4: 5(八分)+ 延续音拖 1 拍 + 休止 1.5(后继远跳)。
        TabNote(string: 2, fret: 3, beat: 4, lyric: 'e'),
        TabNote(string: 2, fret: 3, beat: 4.5),
        // 拍 7: 6(尾音,网格收在 bar 尽头)。
        TabNote(string: 1, fret: 0, beat: 7, lyric: 'f'),
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
      final aligned = deriveNumberedNotes(sheetFixtureMelody, alignBeats: 4);
      expect(aligned.first.mainBeat, 4.0, reason: '你 = 旋律拍 0 + 4');
      expect(aligned.last.mainBeat, 7.0, reason: '末 = 3 + 4');
      // 缺省不过偏移(合成旋律直接推导的既有用例不受影响)。
      expect(deriveNumberedNotes(sheetFixtureMelody).first.mainBeat, 0.0);
    });

    test('非自然音级当场报错(数据缺陷不静默进渲染)', () {
      const chromatic = TabChart(
        title: '坏数据',
        tempo: 78,
        notes: [TabNote(string: 1, fret: 1, beat: 0)], // ①1 = A#4
      );
      expect(() => deriveNumberedNotes(chromatic), throwsArgumentError);
    });

    test('夹具旋律全曲可推导,八度点自实际音高', () {
      final real = deriveNumberedNotes(sheetFixtureMelody, alignBeats: 4);
      expect(real, hasLength(2));
      expect(real.first.degree, 5, reason: '②3 = G4');
      expect(real.first.highDots, 0);
      expect(real.last.degree, 7, reason: '①2 = B4');
      expect(real.last.highDots, 0);
    });
  });

  group('TAB 指形 × 判定:落指形位画 ×,旋律音保持数字', () {
    bool pluckAt(double beat, int string) => l.tabPoints
        .firstWhere(
          (p) => p.note.beat == beat && p.note.string == string,
          orElse: () => throw TestFailure('找不到音 @$beat ④③②① 下标 $string'),
        )
        .isChordPluck;

    test('和弦堆(品位=当前指形按位)判 ×', () {
      // C=[0,1,0,3](④0③1②0①3)→ @4/@7 堆四音全 ×。
      for (final p in l.tabPoints.where((p) => p.note.beat == 4.0)) {
        expect(p.isChordPluck, isTrue, reason: '${p.note}');
      }
      for (final p in l.tabPoints.where((p) => p.note.beat == 7.0)) {
        expect(p.isChordPluck, isTrue, reason: '${p.note}');
      }
    });

    test('旋律品位不落指形位 → 保持数字(false)', () {
      // 滑音对 ①7@4.5、①5@5:C 形 ①=3 ≠ 7/5。
      expect(pluckAt(4.5, 1), isFalse);
      expect(pluckAt(5.0, 1), isFalse);
    });

    test('扫弦拍:落指形的 × 被事件遮蔽;无扫弦拍 × 保留', () {
      // @4 卷弦段扫弦:四弦 × 全遮蔽。
      final strums4 = l.tabPoints.where((p) => p.note.beat == 4.0);
      expect(strums4, hasLength(4));
      for (final p in strums4) {
        expect(p.hiddenByStrum, isTrue, reason: '${p.note}');
      }
      // @7 堆(非扫弦拍):堆 × 保留。
      final b7 = l.tabPoints.where((p) => p.note.beat == 7.0);
      expect(b7, hasLength(4));
      expect(b7.every((p) => !p.hiddenByStrum), isTrue);
      // 种类查询:卷弦 vs 无。
      expect(l.strumKindAt(4.0), ScoreStrumKind.roll);
      expect(l.strumKindAt(4.5), isNull);
      expect(l.strumKindAt(5.0), isNull);
      expect(l.strumKindAt(6.0), isNull);
      expect(l.strumKindAt(7.0), isNull);
      // 休止事件:x 落在拍 6.5。
      expect(l.restEvents.map((r) => r.beat), contains(6.5));
      final rest65 = l.restEvents.firstWhere((r) => r.beat == 6.5);
      expect(rest65.x, l.stripX(6.5));
      expect(rest65.beats, 0.5);
      // 滑音记号与震音记号 x 预计算。
      expect(l.slideMarks.map((s) => (s.x0, s.x1)),
          [(l.stripX(4.5), l.stripX(5.0))]);
      expect(l.tremoloMarks.map((t) => t.beat), [7.0]);
    });
  });

  group('跟随高亮当位查询', () {
    test('拍 4.2:锚 C@4 在奏,当前 TAB=堆,当前简谱=你@4', () {
      final c = l.currentAt(4.2);
      expect(c.chordIndex, 0, reason: '唯一锚 C@4');
      expect(
        c.tabIndex,
        l.tabPoints.lastIndexWhere((p) => p.note.beat <= 4.2),
      );
      expect(c.melodyIndex, 0, reason: '你 = 0 + 4 ≤ 4.2');
    });

    test('拍 7.5:简谱当前音=末@7', () {
      final c = l.currentAt(7.5);
      expect(c.chordIndex, 0);
      expect(
        c.tabIndex,
        l.tabPoints.lastIndexWhere((p) => p.note.beat <= 7.5),
      );
      expect(c.melodyIndex, 1, reason: '末 = 3 + 4 = 7');
    });

    test('曲末尾拍(>网格):钳到最后锚/音,不越界;负拍全 -1', () {
      final c = l.currentAt(100);
      expect(c.chordIndex, sheetFixtureDef.chords.length - 1);
      expect(c.tabIndex, l.tabPoints.length - 1);
      expect(c.melodyIndex, l.numPoints.length - 1);
      final c0 = l.currentAt(-1);
      expect(c0.chordIndex, -1);
      expect(c0.tabIndex, -1);
      expect(c0.melodyIndex, -1);
    });
  });

  test('布局确定性:同入参同输出(缓存几何不随调用漂移)', () {
    final b = ScoreSheetLayout(
      def: sheetFixtureDef,
      tabChart: sheetFixtureTab,
      melodyChart: sheetFixtureMelody,
    );
    expect(l.stripWidth, b.stripWidth);
    expect(l.tabPoints.map((p) => p.x), b.tabPoints.map((p) => p.x));
    expect(l.chordGlyphs.map((g) => g.x), b.chordGlyphs.map((g) => g.x));
  });
}
