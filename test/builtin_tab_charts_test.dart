import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/practice/tab_timeline.dart';
import 'package:ukeflow/core/model/tab_chart.dart';

/// 工单 12 内容缝:内置指弹曲录入正确性。
/// 音位期望值是独立真值(入门 C 调第一把位的标准指位:①3=C5、②3=G4、
/// ③0=C4、③2=D4),逐音抽查旋律走向,渲染「对照谱面数据」的数据面在此锁死。
/// C4 基频(A4=440 基准),主音落点断言共用。
const c4Frequency = 261.6255653005986;

/// 频率 → MIDI 音符号(69 = A4),旋律窗/音域断言共用。
double midiOf(double hz) => 69 + 12 * (math.log(hz / 440) / math.ln2);

/// 第一把位旋律窗 C4..E5(MIDI 60..76,工单 25 录入纪律)。
void expectInMelodyWindow(Iterable<TabNote> notes, {required String context}) {
  for (final n in notes) {
    expect(
      midiOf(n.frequency).round(),
      inInclusiveRange(60, 76),
      reason: '$context 出旋律窗:$n',
    );
  }
}

/// 终句主音收:末音 = C4 ③0(拍位各曲不同,由用例自行断言)。
void expectEndsOnTonic(TabNote note) {
  expect(note.string, 3);
  expect(note.fret, 0);
  expect(note.frequency, closeTo(c4Frequency, 1e-9));
}

/// 逐音合法性断言:弦号/品位域内、拍位不倒退(同拍多音合法,独奏
/// 和弦堆依赖录入序 = 低弦→高弦)且落在 1/16 拍网格、缀字非空白。
/// 迁移谱抽查与目标曲内容缝共用同一形状。
void expectNotesLegal(Iterable<TabNote> notes, {required String context}) {
  var lastBeat = -1.0;
  for (final n in notes) {
    expect(n.string, inInclusiveRange(1, 4), reason: '$n');
    expect(n.fret, greaterThanOrEqualTo(0), reason: '$n');
    expect(
      n.beat,
      greaterThanOrEqualTo(lastBeat),
      reason: '$context 拍位不倒退,见 $n',
    );
    expect(
      n.beat * 4,
      (n.beat * 4).round(),
      reason: '$context 拍位落在 1/16 拍网格,见 $n',
    );
    if (n.lyric != null) expect(n.lyric, isNotEmpty);
    lastBeat = n.beat;
  }
}

void main() {
  test('清单按序产出内置指弹曲,id 与曲名对应', () {
    final charts = loadBuiltinTabCharts();

    expect(charts, hasLength(builtinTabChartCatalog.length));
    for (var i = 0; i < charts.length; i++) {
      expect(charts[i].id, builtinTabChartCatalog[i].id);
    }
    expect(
      [for (final c in charts) c.chart.title],
      [
        '小星星', '欢乐颂',
        // 2026-10-22 起目标曲指弹谱(工单 25,纯旋律版,逐首录入;
        // 「·独奏」版自工单 37 起逐首续录)。
        '沧海一声笑', '爱你不是两三天', '爱你不是两三天·独奏', 'Big Big World',
        // 2026-10-18 迁入 8 首(ukulele-demo 指弹谱转录)。
        '两只老虎', '玛丽有只小羊羔', '伦敦桥', '铃儿响叮当',
        '卡农', '绿袖子', '划小船', '老麦克唐纳',
      ],
    );
  });

  group('迁移谱数据面抽查(转录自 demo,拍位自曲头累计、域内合法)', () {
    // 显式按 id 圈定迁移谱批次:目标曲指弹谱(工单 25 起)逐首录入后
    // 不属于本批,不能靠「排除入门两首」隐式圈定。
    const migratedIds = {
      'liang-zhi-lao-hu-tab',
      'ma-li-you-zhi-xiao-yang-gao',
      'lun-dun-qiao',
      'ling-er-xiang-ding-dang-tab',
      'ka-nong',
      'lv-xiu-zi',
      'hua-xiao-chuan',
      'lao-mai-ke-tang-na',
    };
    final migrated = loadBuiltinTabCharts()
        .where((c) => migratedIds.contains(c.id))
        .toList();

    test('迁移谱恰好 8 首', () {
      expect(migrated, hasLength(8));
    });

    for (final entry in migrated) {
      test('${entry.id}:音域/品位/拍位合法且按拍不倒退', () {
        expect(entry.chart.tempo, greaterThan(0));
        expect(entry.chart.notes, isNotEmpty);
        expectNotesLegal(entry.chart.notes, context: entry.id);
      });
    }
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
    expect(
      song.notes.take(2).map((n) => n.frequency),
      everyElement(closeTo(c4Frequency, 1e-9)),
    );
    expect(
      song.notes[28].frequency,
      closeTo(c4Frequency, 1e-9),
      reason: '再现段开头同修:C4',
    );
    // 「满天都是小星星」句尾:C4 = ③0 @拍14(二拍长音)。
    final bar4 = song.notes.where((n) => n.beat >= 12 && n.beat < 16).toList();
    expect(bar4.last.string, 3);
    expect(bar4.last.fret, 0);
    expect(bar4.last.beat, 14);

    // 末音回落主音 C4 @拍46,曲末整小节收。
    expect(song.notes.last.fret, 0);
    expect(song.notes.last.beat, 46);
    expect(song.notes.last.frequency, closeTo(c4Frequency, 1e-9));

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

  test('沧海一声笑:82 音 25 小节,主题下行句与五声域抽查', () {
    final song = loadBuiltinTabCharts()
        .singleWhere((c) => c.id == 'cang-hai-yi-sheng-xiao')
        .chart;

    expect(song.notes, hasLength(82));
    expect(song.tempo, 80);

    // 开头「沧海一声笑」= 主题下行 65321:A4 G4 E4 D4 C4 = ①0 ②3 ②0 ③2 ③0
    // (黄霑反工尺「五六工尺上」,多源印证)。
    expect(song.notes.take(5).map((n) => (n.string, n.fret)), [
      (1, 0),
      (2, 3),
      (2, 0),
      (3, 2),
      (3, 0),
    ]);
    // 「滔滔两岸潮」原曲沉到 G3,uke 无低音区(录入注记):高置为 C5 起的
    // 下行串 C5 A4 G4 E4 D4 = ①3 ①0 ②3 ②0 ③2。
    expect(song.notes.skip(5).take(5).map((n) => (n.string, n.fret)), [
      (1, 3),
      (1, 0),
      (2, 3),
      (2, 0),
      (3, 2),
    ]);

    // 五声域(宫商角徵羽,无 fa/si):全部音落在 C4..E5 的
    // {C4 D4 E4 G4 A4 C5 D5 E5}。
    const pentatonicMidi = {60, 62, 64, 67, 69, 72, 74, 76};
    for (final n in song.notes) {
      expect(
        midiOf(n.frequency).round(),
        isIn(pentatonicMidi),
        reason: '${song.title} 出五声域:$n',
      );
    }

    // 段落逐句缀字(歌词源 = assets/charts/cang-hai-yi-sheng-xiao.pro,
    // 维护者 2026-10-13 录入;尾奏「啦……」器乐段不录)。
    final lyrics = song.notes.map((n) => n.lyric).toList();
    expect(lyrics.whereType<String>(), hasLength(82));
    expect(lyrics.take(10).join(), '沧海一声笑滔滔两岸潮');
    expect(lyrics.sublist(10, 18).join(), '浮沉随浪只记今朝');
    expect(lyrics.sublist(18, 26).join(), '苍天笑纷纷世上潮');
    expect(lyrics.sublist(26, 34).join(), '谁负谁胜出天知晓');
    expect(lyrics.sublist(34, 40).join(), '江山笑烟雨遥');
    expect(lyrics.sublist(40, 51).join(), '涛浪淘尽红尘俗世几多娇');
    expect(lyrics.sublist(51, 58).join(), '清风笑竟惹寂寥');
    expect(lyrics.sublist(58, 67).join(), '豪情还剩了一襟晚照');
    expect(lyrics.sublist(67, 74).join(), '苍生笑不再寂寥');
    expect(lyrics.sublist(74).join(), '豪情仍在痴痴笑笑');

    // 逐音合法性(弦号/品位域内、严格递增、1/16 网格)。
    expectNotesLegal(song.notes, context: song.title);

    // 全曲唯一超 5 品处 = 高潮句「(出天)知晓」:知@37、晓@38 两个 ①7
    // (录入注记:原谱作高音 5 = G5,uke 无把手;装机验手感,不行回桌议调)。
    final fretOver5 = song.notes.where((n) => n.fret > 5).toList();
    expect(fretOver5, hasLength(2));
    expect(fretOver5.map((n) => n.lyric), ['知', '晓']);
    final xiao = song.notes.singleWhere((n) => n.lyric == '晓');
    expect(xiao.beat, 38);

    // 终句主音收:末「笑」= C4 ③0 @96,曲末保有整拍(100 拍 = 25 小节整)。
    expect(song.notes.last.string, 3);
    expect(song.notes.last.fret, 0);
    expect(song.notes.last.beat, 96);
    expect(song.notes.last.frequency, closeTo(c4Frequency, 1e-9));
  });

  test('爱你不是两三天:主歌一+副歌整段 168 音 22 小节,权威源转录抽查', () {
    final song = loadBuiltinTabCharts()
        .singleWhere((c) => c.id == 'ai-ni-bu-shi-liang-san-tian')
        .chart;

    expect(song.notes, hasLength(168));
    expect(song.tempo, 78);

    // 起句「你的信只留下」:附点八分+16 分同音连线(G4 G4 [G4] C5)。
    expect(song.notes.take(4).map((n) => (n.string, n.fret, n.beat)), [
      (2, 3, 0),
      (2, 3, 0.75),
      (2, 3, 1),
      (1, 3, 1.5),
    ]);

    // 音域 D4..A5(主歌 E4..E5,副歌高置段 印张双点 D5..A5,工单 37 台账)。
    for (final n in song.notes) {
      expect(
        midiOf(n.frequency).round(),
        inInclusiveRange(62, 81),
        reason: '${song.title} 出音域:$n',
      );
    }

    // 逐音缀字全文(拖腔音留空;印张连线尾音带字处照录,如 b10「信」)。
    expect(
      song.notes.map((n) => n.lyric ?? '').join(),
      '你的信只留下最后一封淡淡笔迹你熟悉的温柔请别介意我会将信纸好好收着'
      '当我需要你关怀的时候走过夏日街头还是想牵你的手好想听到一句温暖的问候'
      '虽然我们说好了还是朋友但为什么却没有再联络'
      '爱你不是两三天每天却想你很多遍还不习惯孤独街道拥挤人潮没'
      '你拥抱爱你不是两三天一眨眼心跳能沉淀你是否想念',
    );

    // 段落锚点抽查:副歌起「两」= G4 ②3 @64;顶点「天」= G5 ①10 @66。
    final liang = song.notes.singleWhere((n) => n.lyric == '两' && n.beat == 64);
    expect((liang.string, liang.fret, liang.beat), (2, 3, 64));
    final tianTop = song.notes.singleWhere(
      (n) => n.lyric == '天' && n.beat == 66,
    );
    expect((tianTop.string, tianTop.fret), (1, 10));
    // 高置段连续判断:三/每 = E5 ①7。
    final san = song.notes.singleWhere((n) => n.lyric == '三' && n.beat == 64.5);
    expect((san.string, san.fret, san.beat), (1, 7, 64.5));

    expectNotesLegal(song.notes, context: song.title);

    // 全曲末音「念」= A5 ①12 @87.5(长音接原曲间奏)。
    expect(song.notes.last.string, 1);
    expect(song.notes.last.fret, 12);
    expect(song.notes.last.beat, 87.5);
  });

  test('爱你不是两三天·独奏:前奏+主歌+副歌 496 音,权威源 TAB 行转录抽查', () {
    final song = loadBuiltinTabCharts()
        .singleWhere((c) => c.id == 'ai-ni-bu-shi-liang-san-tian-solo')
        .chart;

    expect(song.notes, hasLength(496));
    expect(song.tempo, 78);

    // 小节2 卷弦起 = E 和弦 4442 块(低弦→高弦),接 ③④②③ 拨弦序列。
    expect(song.notes.take(7).map((n) => (n.string, n.fret, n.beat)), [
      (4, 4, 4.0),
      (3, 4, 4.0),
      (2, 4, 4.0),
      (1, 2, 4.0),
      (3, 4, 4.5),
      (2, 4, 5.0),
      (3, 4, 5.5),
    ]);

    // 小节4 和弦堆的旋律音 ①2=B4 与三连音直化位(工单 37 台账)。
    final stack = song.notes.where((n) => n.beat == 12.0).toList();
    expect(stack.map((n) => (n.string, n.fret)), [
      (4, 2),
      (3, 1),
      (2, 0),
      (1, 2),
    ]);
    expect(
      song.notes
          .where((n) => n.beat >= 13.0 && n.beat < 14.0)
          .map((n) => (n.string, n.fret, n.beat)),
      [(2, 0, 13.0), (1, 0, 13.25), (1, 2, 13.5)],
    );

    // 前奏末音 = ①8=F5 @18(印张圆圈数字+延音号,二拍延音)。
    final fermata = song.notes.singleWhere((n) => n.beat == 18.0);
    expect((fermata.string, fermata.fret), (1, 8));

    // 主歌 b6 E 堆 @20(④②①,③ 位竖杆=虚按不发音)+ ③4 补音 @20.5。
    expect(
      song.notes.where((n) => n.beat == 20.0).map((n) => (n.string, n.fret)),
      [(4, 4), (2, 4), (1, 2)],
    );
    expect(
      song.notes.where((n) => n.beat == 20.5).map((n) => (n.string, n.fret)),
      [(3, 4)],
    );
    // 延展小节(b9 E 整小节)重拍不重击低音:beat 34 只 ②①。
    expect(
      song.notes.where((n) => n.beat == 34.0).map((n) => (n.string, n.fret)),
      [(2, 4), (1, 2)],
    );
    // 副歌A b19 G#7(1323)堆 @72;高置段 b22 首扫 @84 = E 全四弦,
    // 拍 86 = ×柱连音环不占拍(无攻击)。
    expect(
      song.notes.where((n) => n.beat == 72.0).map((n) => (n.string, n.fret)),
      [(4, 1), (2, 2), (1, 3)],
    );
    expect(
      song.notes.where((n) => n.beat == 84.0).map((n) => (n.string, n.fret)),
      [(4, 4), (3, 4), (2, 4), (1, 2)],
    );
    expect(song.notes.where((n) => n.beat == 86.0), isEmpty);
    // b25 D7 闷音柱 {①3③2}(②④×不发音);曲末扫 @107.75 = G#7 全四弦。
    expect(
      song.notes.where((n) => n.beat == 98.0).map((n) => (n.string, n.fret)),
      [(3, 2), (1, 3)],
    );
    expect(
      song.notes.where((n) => n.beat == 107.75).map((n) => (n.string, n.fret)),
      [(4, 1), (3, 3), (2, 2), (1, 3)],
    );

    // 曲末 112 拍(末扫 107.75 上取整到整小节线)。
    expect(tabTotalBeats(song), 112);

    // 器乐谱无缀字;音域 C#4..F5(61..77,印张 E 调指形原样)。
    expect(song.notes.where((n) => n.lyric != null), isEmpty);
    for (final n in song.notes) {
      expect(
        midiOf(n.frequency).round(),
        inInclusiveRange(61, 77),
        reason: '${song.title} 出音域:$n',
      );
    }

    expectNotesLegal(song.notes, context: song.title);
  });

  test('Big Big World:副歌+主歌一 79 音 17 小节,权威源转录抽查', () {
    final song = loadBuiltinTabCharts()
        .singleWhere((c) => c.id == 'big-big-world')
        .chart;

    expect(song.notes, hasLength(79));
    expect(song.tempo, 88);

    // 弱起「I'm a」= C5 D5(①3 ①5),句首「big big girl」= E5×3(①7)。
    expect(song.notes.take(5).map((n) => (n.string, n.fret, n.beat)), [
      (1, 3, 0),
      (1, 5, 0.5),
      (1, 7, 1),
      (1, 7, 2),
      (1, 7, 3),
    ]);

    // 音域 A4..F5(MIDI 69..77,印张双点减一);全曲单音在 ① 弦。
    for (final n in song.notes) {
      expect(n.string, 1, reason: '${song.title} 出 ① 弦:$n');
      expect(
        midiOf(n.frequency).round(),
        inInclusiveRange(69, 77),
        reason: '${song.title} 出音域:$n',
      );
    }

    // 逐音缀字全文(拖腔音留空;印张连字符照拆 ye/llow、fee/ling,
    // 弧线内整词 falling/outside/very,in/side 无弧线按音节拆)。
    expect(
      song.notes.map((n) => n.lyric ?? '').join(),
      "I'mabigbiggirlInabigbigworldIt'snotabigbigthingifyouleaveme"
      "ButIdodofeelthatIdodowillmissyoumuch"
      'Missyoumuch'
      'Icanseethefirstleaffalling'
      "It'sallyellowandnice"
      "It'ssoverycold"
      "outsideLikethewayI'mfeelinginside",
    );

    // b9「much」16 分拖腔 + 同音连线:E5(16) D5(16) C5(8)~C5(4)。
    expect(
      song.notes
          .where((n) => n.beat >= 25 && n.beat < 27)
          .map((n) => (n.fret, n.beat, n.lyric)),
      [(7, 25, 'much'), (5, 25.25, null), (3, 25.5, null), (3, 26, null)],
    );

    // b17「outside」附点八分起 16 分三连拖腔:C5. D5 E5 D5 E5。
    expect(
      song.notes
          .where((n) => n.beat >= 58.5 && n.beat < 61)
          .map((n) => (n.fret, n.beat)),
      [(3, 58.5), (5, 59.25), (7, 59.5), (5, 59.75), (7, 60)],
    );

    // b18「way」拖腔下行 D5 C5 A4:全曲唯一 ①0(印张单点 6)。
    expect(
      song.notes
          .where((n) => n.beat >= 63 && n.beat < 64)
          .map((n) => n.fret),
      [5, 3, 0],
    );

    expectNotesLegal(song.notes, context: song.title);

    // 末音 =「inside」拖腔 E5 ①7 @67;曲末保有整拍(68 拍 = 17 小节整,
    // b19 尾「I'm a」弱起属原曲反复段,不录)。
    expect(song.notes.last.string, 1);
    expect(song.notes.last.fret, 7);
    expect(song.notes.last.beat, 67);
  });
}
