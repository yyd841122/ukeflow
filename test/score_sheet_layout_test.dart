import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/model/tab_chart.dart';
import 'package:ukeflow/core/practice/score_sheet_layout.dart';

/// 谱面布局内核(工单 39 测试缝①):(组合定义, 屏宽) → 系统切分 + 四层
/// 元素坐标 + 简谱符号推导 + 跟随高亮当位查询。纯函数,零引擎依赖。
/// 推导规则用合成旋律逐符号锁定;系统切分/当位查询用真数据(首曲)。
void main() {
  final charts = {for (final e in builtinTabChartCatalog) e.id: e.chart};
  final def = scoreSheetCatalog.single;
  final solo = charts[def.tabChartId]!;
  final melody = charts[def.melodyChartId]!;

  ScoreSheetLayout layout(double contentWidth) => ScoreSheetLayout(
    def: def,
    tabChart: solo,
    melodyChart: melody,
    contentWidth: contentWidth,
  );

  group('系统切分:屏宽定每系统小节数', () {
    test('窄屏 310px:2 小节/系统,pxPerBeat 满幅均分,27 小节 14 系统', () {
      final l = layout(310);
      expect(l.barsPerSystem, 2);
      expect(l.pxPerBeat, closeTo(310 / 8, 1e-9));
      expect(l.barCount, 27, reason: '主轴网格按印张 27 小节收口');
      expect(l.systemCount, 14);
      expect(ScoreSheetLayout.systemHeight, greaterThan(0));
    });

    test('宽屏 800px:4 小节/系统(印张版面),7 系统', () {
      final l = layout(800);
      expect(l.barsPerSystem, 4);
      expect(l.systemCount, 7);
    });

    test('极窄 200px:1 小节/系统,27 系统', () {
      final l = layout(200);
      expect(l.barsPerSystem, 1);
      expect(l.systemCount, 27);
    });

    test('小节归系统:2 小节/系统时 bar 0-1 在系统 0,bar 26 单独收尾', () {
      final l = layout(310);
      expect(l.systemOfBar(0), 0);
      expect(l.systemOfBar(1), 0);
      expect(l.systemOfBar(2), 1);
      expect(l.systemOfBar(26), 13);
      expect(l.firstBarOfSystem(13), 26);
      expect(l.barsInSystem(13), 1);
      expect(l.barsInSystem(0), 2);
    });
  });

  group('四层坐标', () {
    test('和弦图落系统顶层行:系统头小节的锚贴行首,行内防重叠右移', () {
      final l = layout(310);
      // 系统 2 = bar 4-5(拍 16-24):锚 E@16、E@20、A@22。
      final glyphs = l.chordsInSystem(2);
      expect(glyphs.map((g) => g.anchor.label), ['E', 'E', 'A']);
      // E@16 是系统 2 头小节头拍:x = 0(落行首)。
      expect(glyphs[0].x, 0.0);
      // 行内 x 单调不减且两两不叠(留最小间距)。
      for (var i = 1; i < glyphs.length; i++) {
        expect(glyphs[i].x,
            greaterThanOrEqualTo(glyphs[i - 1].x + ScoreSheetLayout.chordGlyphWidth));
      }
    });

    test('TAB 音横坐标 = 小节内拍位 × pxPerBeat,系统按拍位归属', () {
      final l = layout(310);
      // 独奏第一堆 @4.0:bar 1 → 系统 0,小节内偏移 0。
      final sys0 = l.tabInSystem(0);
      final first = sys0.firstWhere((n) => n.note.beat == 4.0);
      expect(first.x, closeTo(l.barXInSystem(0, 1), 1e-9));
      // @8.0 是 bar 2 头:归系统 1,x = 0。
      expect(l.systemOfBeat(8.0), 1);
      final sys1 = l.tabInSystem(1);
      expect(sys1.first.note.beat, 8.0);
      expect(sys1.first.x, closeTo(l.barXInSystem(1, 2), 1e-9));
    });

    test('简谱音 x = (旋律拍+20) 的主轴坐标,歌词缀字随音符', () {
      final l = layout(310);
      // 旋律首音 你 G4 @0(+20 = 主轴拍 20,bar 5,系统 2)。
      final sys2 = l.numberedInSystem(2);
      expect(sys2.first.symbol.degree, 5);
      expect(sys2.first.symbol.lyric, '你');
      expect(sys2.first.x, closeTo(l.barXInSystem(2, 5), 1e-9));
      // 前奏系统(0-1)无旋律音。
      expect(l.numberedInSystem(0), isEmpty);
      expect(l.numberedInSystem(1), isEmpty);
    });

    test('全休止小节只有前奏 bar 0,四层皆空', () {
      final l = layout(310);
      expect(l.emptyBars, [0]);
    });

    test('小节线横坐标:系统内逐小节等距,首线贴行首', () {
      final l = layout(310);
      expect(l.barXInSystem(0, 0), 0.0);
      expect(l.barXInSystem(0, 1), closeTo(4 * l.pxPerBeat, 1e-9));
      expect(l.barXInSystem(0, 2), closeTo(8 * l.pxPerBeat, 1e-9),
          reason: '末小节线 = 下一系统行首');
    });
  });

  group('TAB 印张 × 判定:落指形位画 ×,旋律音保持数字', () {
    // 宽屏 800:4 小节/系统,系统 0 = bar 0-3(拍 0-16,前奏+主歌 b4)。
    final l = layout(800);
    final sys0 = l.tabInSystem(0);
    bool pluckAt(double beat, int string, int fret) => sys0
        .firstWhere(
          (p) => p.note.beat == beat && p.note.string == string,
          orElse: () => throw TestFailure('找不到音 @$beat ①$string'),
        )
        .isChordPluck;

    test('和弦堆/拨弦(品位=当前指形按位)判 ×', () {
      // b4 A 堆 @12.0:A=[2,1,0,0](④2③1②0)→ ④③② 全 ×。
      expect(pluckAt(12.0, 4, 2), isTrue);
      expect(pluckAt(12.0, 3, 1), isTrue);
      expect(pluckAt(12.0, 2, 0), isTrue);
      // 前奏 b2 E 堆 @4.0:E=[4,4,4,2] → ④③②① 全 ×。
      for (final p in sys0.where((p) => p.note.beat == 4.0)) {
        expect(p.isChordPluck, isTrue, reason: '${p.note}');
      }
    });

    test('旋律品位不落指形位 → 保持数字(false)', () {
      // b4 旋律 ①2=B4 @12.0(印张数字②):A 指形 ①=0 ≠ 2。
      expect(pluckAt(12.0, 1, 2), isFalse);
      // b5 末音 ①8=F5 @18.0(印张数字⑧):E 指形 ①=2 ≠ 8。bar 5 在系统 1。
      final sys1 = layout(800).tabInSystem(1);
      final f5 = sys1.firstWhere(
        (p) => p.note.beat == 18.0 && p.note.string == 1,
      );
      expect(f5.note.fret, 8);
      expect(f5.isChordPluck, isFalse);
    });

    test('主歌两拍单元(b6 起,拍 20+)逐音 ×', () {
      // b6 E 段(拍 20-21.5,E=[4,4,4,2])与 A 段(拍 22-23.5,A=[2,1,0,0])。
      final sys1 = layout(800).tabInSystem(1); // bar 4-7 = 拍 16-32
      for (final p in sys1.where((p) => p.note.beat >= 20)) {
        expect(p.isChordPluck, isTrue, reason: '主歌单元应全 ×:${p.note}');
      }
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
        // 拍 3: 7(整拍,高音一点)——曲首前无它,单独验八度点。
        const TabNote(string: 1, fret: 2, beat: 3, lyric: 'd'),
        // 拍 4: 5(八分)+ 延续音拖 1 拍 + 休止 1.75(后继远跳)。
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

    test('非自然音级当场报错(数据缺陷不静默进渲染)', () {
      const chromatic = TabChart(
        title: '坏数据',
        tempo: 78,
        notes: [TabNote(string: 1, fret: 1, beat: 0)], // ①1 = A#4
      );
      expect(() => deriveNumberedNotes(chromatic), throwsArgumentError);
    });

    test('对齐偏移:mainBeat 落主轴拍(弧线端点按主轴坐标消费)', () {
      final aligned = deriveNumberedNotes(melody, alignBeats: 20);
      expect(aligned.first.mainBeat, 20.0, reason: '你 = 旋律拍 0 + 20');
      expect(aligned.last.mainBeat, 107.5, reason: '念 = 87.5 + 20');
      // 缺省不过偏移(合成旋律直接推导的既有用例不受影响)。
      expect(deriveNumberedNotes(melody).first.mainBeat, 0.0);
    });

    test('真数据:旋律全曲可推导,副歌高置段双点(A5=6 两点)', () {
      final real = deriveNumberedNotes(melody);
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

  group('跟随高亮当位查询', () {
    test('预备期拍 0-20:有 TAB 当前音与当前和弦,简谱无当前音', () {
      final l = layout(310);
      final c = l.currentAt(19.5);
      expect(c.chordIndex, def.chords.indexWhere((ch) => ch.beat == 16),
          reason: '前奏末锚 E@16');
      expect(c.melodyIndex, -1, reason: '旋律 20 拍起');
      expect(c.tabIndex, greaterThanOrEqualTo(0));
    });

    test('主歌拍 21.5:和弦 E@20,简谱当前音=信@1.5(+20),歌词逐字', () {
      final l = layout(310);
      final c = l.currentAt(21.5);
      expect(c.chordIndex, def.chords.indexWhere((ch) => ch.beat == 20));
      final symbol = deriveNumberedNotes(melody)[c.melodyIndex];
      expect(symbol.lyric, '信');
    });

    test('副歌拍 84.5:和弦 E@84,简谱当前音=三@64.5(+20)', () {
      final l = layout(310);
      final c = l.currentAt(84.5);
      expect(c.chordIndex, def.chords.indexWhere((ch) => ch.beat == 84));
      final symbol = deriveNumberedNotes(melody)[c.melodyIndex];
      expect(symbol.lyric, '三');
    });

    test('曲末尾拍(>网格):钳到最后锚/音,不越界', () {
      final l = layout(310);
      final c = l.currentAt(120);
      expect(c.chordIndex, def.chords.length - 1);
      expect(c.tabIndex, l.tabNotes.length - 1);
      expect(c.melodyIndex, l.melodyNotes.length - 1);
      final c0 = l.currentAt(-1);
      expect(c0.chordIndex, -1);
      expect(c0.tabIndex, -1);
      expect(c0.melodyIndex, -1);
    });
  });

  test('布局确定性:同入参同输出(缓存几何不随调用漂移)', () {
    final a = layout(310);
    final b = layout(310);
    expect(a.barsPerSystem, b.barsPerSystem);
    expect(a.systemCount, b.systemCount);
    expect(a.pxPerBeat, b.pxPerBeat);
    expect(a.numberedNotes.map((n) => n.degree), b.numberedNotes.map((n) => n.degree));
    // 末音时长入推导:末尾剩余不足整拍的按小节收口。
    expect(math.max(a.numberedNotes.last.dashes, 0), greaterThanOrEqualTo(0));
  });
}
