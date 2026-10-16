import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_tab_charts.dart';

/// 工单 12 内容缝:内置指弹曲录入正确性。
/// 音位期望值是独立真值(入门 C 调第一把位的标准指位:①3=C5、②3=G4、
/// ③0=C4、③2=D4),逐音抽查旋律走向,渲染「对照谱面数据」的数据面在此锁死。
void main() {
  test('清单按序产出两首入门曲,id 与曲名对应', () {
    final charts = loadBuiltinTabCharts();

    expect(charts, hasLength(builtinTabChartCatalog.length));
    for (var i = 0; i < charts.length; i++) {
      expect(charts[i].id, builtinTabChartCatalog[i].id);
    }
    expect([for (final c in charts) c.chart.title], ['小星星', '欢乐颂']);
  });

  test('小星星:42 音 12 小节,乐句走向与指位抽查', () {
    final song = loadBuiltinTabCharts()
        .singleWhere((c) => c.id == 'xiao-xing-xing')
        .chart;

    // 一段 14 音(4+3+4+3)× 3 段 = 42;末音拍 46 → 曲末 48(12 小节)。
    expect(song.notes, hasLength(42));
    expect(song.tempo, 90);

    // 「一闪一闪亮晶晶」:C4 C4 G4 G4 = ③0 ③0 ②3 ②3(C 与 G 同八度,
    // 旋律上行五度;审计 2026-10-16 #10 修:旧数据 ①3=C5 垮八度)。
    expect(song.notes.take(4).map((n) => (n.string, n.fret)), [
      (3, 0),
      (3, 0),
      (2, 3),
      (2, 3),
    ]);
    expect(song.notes.take(2).map((n) => n.frequency),
        everyElement(closeTo(261.6255653005986, 1e-9)));
    expect(song.notes[28].frequency, closeTo(261.6255653005986, 1e-9),
        reason: '再现段开头同修:C4');
    // 「满天都是小星星」句尾:C4 = ③0 @拍14(二拍长音)。
    final bar4 = song.notes.where((n) => n.beat >= 12 && n.beat < 16).toList();
    expect(bar4.last.string, 3);
    expect(bar4.last.fret, 0);
    expect(bar4.last.beat, 14);

    // 末音回落主音 C4 @拍46,曲末整小节收。
    expect(song.notes.last.fret, 0);
    expect(song.notes.last.beat, 46);
    expect(song.notes.last.frequency, closeTo(261.6255653005986, 1e-9));

    // 歌词逐音一字恰好对齐:每句 7 字对 7 音,42 音全带词。
    final lyrics = song.notes.map((n) => n.lyric).toList();
    expect(lyrics.whereType<String>(), hasLength(42));
    expect(lyrics.take(7).join(), '一闪一闪亮晶晶');
    expect(lyrics.sublist(7, 14).join(), '满天都是小星星');
    expect(lyrics.sublist(14, 21).join(), '挂在天上放光明');
    expect(lyrics.sublist(21, 28).join(), '好像许多小眼睛');
    expect(lyrics.sublist(28, 35).join(), '一闪一闪亮晶晶');
    expect(lyrics.sublist(35).join(), '满天都是小星星');
  });

  test('欢乐颂:30 音 8 小节,附点节奏落在半拍位', () {
    final song = loadBuiltinTabCharts()
        .singleWhere((c) => c.id == 'huan-le-song')
        .chart;

    expect(song.notes, hasLength(30));
    expect(song.tempo, 100);

    // 开头 Mi Mi Fa Sol:E4 E4 F4 G4 = ②0 ②0 ②1 ②3。
    expect(song.notes.take(4).map((n) => (n.string, n.fret)), [
      (2, 0),
      (2, 0),
      (2, 1),
      (2, 3),
    ]);
    // 第 4 小节附点:E(1.5拍)@12、D@13.5(半拍位)、D(2拍)@14。
    final bar4 = song.notes.where((n) => n.beat >= 12 && n.beat < 16).toList();
    expect(bar4.map((n) => (n.string, n.fret, n.beat)), [
      (2, 0, 12.0),
      (3, 2, 13.5),
      (3, 2, 14.0),
    ]);
    // 末小节附点收束:D@28、C@29.5、C(2拍)@30。
    expect(song.notes.last.beat, 30.0);
    expect(song.notes.last.string, 3);
    expect(song.notes.last.fret, 0);

    // 歌词逐音缀字:30 音全带词,四句各 8/7/8/7 字;附点音位对
    // 「照(附点四分)大(半拍)地(二拍长音)」「圣 殿 里」。
    final lyrics = song.notes.map((n) => n.lyric).toList();
    expect(lyrics.whereType<String>(), hasLength(30));
    expect(lyrics.take(8).join(), '欢乐女神圣洁美丽');
    expect(lyrics.sublist(8, 15).join(), '灿烂光芒照大地');
    expect(lyrics.sublist(15, 23).join(), '我们心中充满热情');
    expect(lyrics.sublist(23).join(), '来到你的圣殿里');
    expect(song.notes.where((n) => n.beat == 13.5).single.lyric, '大');
    expect(song.notes.where((n) => n.beat == 29.5).single.lyric, '殿');
  });
}
