import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/cifra_extract.dart';
import 'package:ukeflow/core/chart/strum_chart_parser.dart';
import 'package:ukeflow/data/chord_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('decodeCifraPayload', () {
    test('合法载荷:标题/艺人/行结构逐段还原', () {
      final payload = decodeCifraPayload({
        'title': 'Gravity',
        'artist': 'Embrace',
        'lines': [
          [
            {'c': 'D#', 's': 'D#                  '},
            '                  ',
            {'c': 'Cm', 's': 'Cm'},
          ],
          ['Hunny its been a long time coming, And I cant stop now. '],
          <Object>[],
        ],
      });

      expect(payload, isNotNull);
      expect(payload!.title, 'Gravity');
      expect(payload.artist, 'Embrace');
      expect(payload.lines, hasLength(3));
      final chordLine = payload.lines[0];
      expect(chordLine, hasLength(3));
      expect(chordLine[0], isA<CifraChordSeg>());
      final chord = chordLine[0] as CifraChordSeg;
      expect(chord.name, 'D#');
      expect(chord.raw, 'D#                  ');
      expect(chordLine[1], isA<CifraTextSeg>());
      expect((chordLine[1] as CifraTextSeg).text, '                  ');
      expect(payload.lines[1].single, isA<CifraTextSeg>());
      expect(payload.lines[2], isEmpty);
    });

    test('畸形载荷:非 Map / 行非 List / 段不认得——整体拒绝返回 null', () {
      expect(decodeCifraPayload(null), isNull);
      expect(decodeCifraPayload('nope'), isNull);
      expect(decodeCifraPayload([1, 2, 3]), isNull);
      expect(decodeCifraPayload({'lines': 'not-a-list'}), isNull);
      expect(
        decodeCifraPayload({
          'lines': [
            [42],
          ],
        }),
        isNull,
      );
      expect(
        decodeCifraPayload({
          'lines': [
            [
              {'c': 3},
            ],
          ],
        }),
        isNull,
      );
    });

    test('字符串容错:JSON 串直接解;Android 桥多包一层引号也剥得掉', () {
      final inner = jsonEncode({
        'title': 'Gravity',
        'lines': <List<Object>>[
          <Object>['x'],
        ],
      });

      final direct = decodeCifraPayload(inner);
      expect(direct, isNotNull);
      expect(direct!.title, 'Gravity');

      final wrapped = jsonEncode(inner);
      final unwrapped = decodeCifraPayload(wrapped);
      expect(unwrapped, isNotNull);
      expect(unwrapped!.title, 'Gravity');
    });

    test('缺元数据字段:null 而非报错', () {
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>['x'],
        ],
      });
      expect(payload, isNotNull);
      expect(payload!.title, isNull);
      expect(payload.artist, isNull);
    });

    test('提取失败码:{error:...} 可读出;正常载荷/垃圾不算失败', () {
      expect(
        cifraExtractError(jsonEncode({'error': 'no-chords'})),
        'no-chords',
      );
      expect(
        cifraExtractError({
          'lines': <List<Object>>[
            <Object>['x'],
          ],
        }),
        isNull,
      );
      expect(cifraExtractError('garbage'), isNull);
      expect(cifraExtractError(null), isNull);
    });
  });

  group('buildChordPro', () {
    test('两行式一对:首和弦吸行首(①)+升号归一+列位行内化(词中回退词首②)', () {
      // 行结构取自真实存档页(embrace/gravity,2026-06):
      // <b>D#</b>…<b>Cm</b>…<b>Gm</b>…<b>G#</b>…<b>D#</b> 上悬,歌词行在下。
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>[
            {'c': 'D#', 's': 'D#'},
            ' ' * 18,
            {'c': 'Cm', 's': 'Cm'},
            ' ' * 10,
            {'c': 'Gm', 's': 'Gm'},
            ' ' * 9,
            {'c': 'G#', 's': 'G#'},
            ' ' * 6,
            {'c': 'D#', 's': 'D#'},
          ],
          ['Hunny its been a long time coming, And I cant stop now. '],
        ],
      })!;

      final text = buildChordPro(payload, allowedChords: {
        'Eb', 'Cm', 'Gm', 'Ab',
      });

      // 列位(0/20/32/43/51)落进歌词:20、32、43、51 都是词中间——回退词首;
      // 首和弦吸到行首;D#→Eb、G#→Ab 同音异名归一(和弦库只有降号拼法)。
      expect(
        text,
        '[Eb]Hunny its been a [Cm]long time [Gm]coming, And I '
        '[Ab]cant stop [Eb]now.\n',
      );
    });

    test('连续两条悬空和弦行(原调+capo 双记谱):只取首条配歌词,其余丢弃', () {
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>[
            {'c': 'Gm', 's': 'Gm'},
            ' ' * 6,
            {'c': 'Cm', 's': 'Cm'},
          ],
          <Object>[
            ' ' * 4,
            {'c': 'A#m', 's': 'A#m'},
          ],
          ['Some people wait'],
        ],
      })!;

      expect(
        buildChordPro(payload, allowedChords: {'Gm', 'Cm', 'Bbm'}),
        '[Gm]Some [Cm]people wait\n',
      );
    });

    test('悬空行等不到歌词(空行隔开):独立和弦行落盘,和弦空格并列', () {
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>[
            {'c': 'Em', 's': 'Em'},
            ' ' * 4,
            {'c': 'C', 's': 'C'},
          ],
          <Object>[],
          <Object>[
            {'c': 'G', 's': 'G'},
          ],
          ['la la'],
        ],
      })!;

      expect(buildChordPro(payload, allowedChords: {'Em', 'C', 'G'}), '[Em] [C]\n[G]la la\n');
    });

    test('段落标记:英/葡词表译成指令对,custom 段留标签,重音剥离', () {
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>['[Intro]'],
          <Object>[
            {'c': 'Em', 's': 'Em'},
          ],
          ['something here'],
          <Object>['[Chorus]'],
          <Object>[
            ' ' * 2,
            {'c': 'G', 's': 'G'},
            ' ' * 4,
            {'c': 'C', 's': 'C'},
          ],
          ['  sing it loud  '],
          <Object>['[Refrão]'],
          ['outro trecho'],
        ],
      })!;

      expect(
        buildChordPro(payload, allowedChords: {'Em', 'G', 'C'}),
        '{start_of_intro: Intro}\n'
        '[Em]something here\n'
        '{end_of_intro}\n'
        '{start_of_chorus: Chorus}\n'
        '[G]sing [C]it loud\n'
        '{end_of_chorus}\n'
        '{start_of_chorus: Refrão}\n'
        'outro trecho\n'
        '{end_of_chorus}\n',
      );
    });

    test('capo 双记谱(真实存档形态):纯文本 capo 行跟在 b 和弦行后,丢弃不配歌词', () {
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>[
            {'c': 'D#', 's': 'D#'},
            ' ' * 18,
            {'c': 'Cm', 's': 'Cm'},
            ' ' * 10,
            {'c': 'Gm', 's': 'Gm'},
            ' ' * 9,
            {'c': 'G#', 's': 'G#'},
            ' ' * 6,
            {'c': 'D#', 's': 'D#'},
          ],
          // 第二行无 b 元素:站点把它渲染成纯文本。
          ['C (with capo fret3) Am          Em         F        C'],
          ['Hunny its been a long time coming, And I cant stop now. '],
        ],
      })!;

      expect(
        buildChordPro(payload, allowedChords: {'Eb', 'Cm', 'Gm', 'Ab'}),
        '[Eb]Hunny its been a [Cm]long time [Gm]coming, And I '
        '[Ab]cant stop [Eb]now.\n',
      );
    });

    test('标记与和弦同行(真站形态):[Intro] 剥为段落行,和弦照常行内化', () {
      // 2026-10-14 真机机检(Let It Be 页):站点把 [Intro]/[Solo] 与和弦
      // 放同一行——纯文本段 "[Intro] " 在前,b 和弦段跟后。
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>[
            '[Intro] ',
            {'c': 'C', 's': 'C'},
            ' ',
            {'c': 'G', 's': 'G'},
          ],
          <Object>[],
          ['When I find myself in times of trouble'],
        ],
      })!;

      final text = buildChordPro(payload, allowedChords: {'C', 'G', 'Am', 'F'});
      // 标记不再混进歌词当和弦记号;Intro 段落指令对;悬空和弦行独立落盘。
      expect(text, contains('{start_of_intro: Intro}'));
      expect(text, contains('{end_of_intro}'));
      expect(text, contains('[C] [G]'));
      expect(text, isNot(contains('[Intro]')));
      expect(text, contains('When I find myself in times of trouble'));
    });

    test('歌词行不以和弦行替身被误杀:普通句子照常配和弦', () {
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>[
            {'c': 'G', 's': 'G'},
          ],
          ['Dont be blue, my dear Em'],
        ],
      })!;

      expect(buildChordPro(payload, allowedChords: {'G', 'Em'}), '[G]Dont be blue, my dear Em\n');
    });

    test('单词/两词歌词行不作二记谱行丢弃:丢词=静默数据损失,fail-closed', () {
      // 葡语歌词常见形态:悬空行后跟整行一词("Amor"、"Eu")。
      // 首字母 A-G 的词在「吸收任意后缀」的和弦样判定下必命中——
      // 短行(词数<2)与严格过半(半数边缘)都不够丢的证据。
      final one = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>[
            {'c': 'Am', 's': 'Am'},
          ],
          ['Amor'],
        ],
      })!;
      expect(buildChordPro(one, allowedChords: {'Am'}), '[Am]Amor\n');

      final two = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>[
            {'c': 'C', 's': 'C'},
          ],
          ['Baby blue'],
        ],
      })!;
      expect(buildChordPro(two, allowedChords: {'C'}), '[C]Baby blue\n');
    });

    test('混排行+元数据:{title}/{artist} 置顶,行内和弦按 DOM 序精确插入', () {
      final payload = decodeCifraPayload({
        'title': 'Gravity',
        'artist': 'Embrace',
        'lines': <List<Object>>[
          <Object>['Intro: ', {'c': 'Em', 's': 'Em'}, ' live'],
        ],
      })!;

      expect(
        buildChordPro(payload, allowedChords: {'Em'}),
        '{title: Gravity}\n{artist: Embrace}\nIntro: [Em] live\n',
      );
    });

    test('同音异名映射带低音:斜线和弦两端各归一;归一不了保留原样', () {
      final slash = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>[{'c': 'D#m/G#', 's': 'D#m/G#'}],
          <Object>[],
          <Object>[{'c': 'X#7', 's': 'X#7'}],
        ],
      })!;

      expect(
        buildChordPro(slash, allowedChords: {'Ebm/Ab', 'X#7'}),
        '[Ebm/Ab]\n[X#7]\n',
      );
    });

    test('巴西记谱映射(真站形态):7M→maj7、(9) 顶替七、X4→sus4、(b5) 拼接', () {
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>[
            {'c': 'F7M', 's': 'F7M'},
            ' ',
            {'c': 'Dm7(9)', 's': 'Dm7(9)'},
            ' ',
            {'c': 'G4', 's': 'G4'},
            ' ',
            {'c': 'B7(b9)', 's': 'B7(b9)'},
            ' ',
            {'c': 'D#7M', 's': 'D#7M'},
          ],
        ],
      })!;

      expect(
        buildChordPro(
          payload,
          allowedChords: {
            'Fmaj7', 'Dm9', 'Gsus4', 'B7b9', 'Ebmaj7',
          },
        ),
        '[Fmaj7] [Dm9] [Gsus4] [B7b9] [Ebmaj7]\n',
      );
    });

    test('站点 Tab 段(六线谱噪声)整段跳过:报告只留和弦与歌词', () {
      // 真站形态(2026-10-16 用户实测 Somewhere Over The Rainbow):
      // 「[Tab - Intro]」custom 段里全是 E|---B|--- 六线谱行,对尤克里里
      // 跟练是纯噪声,还让整份谱一眼像吉他谱——整段丢弃。
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>['[Intro]'],
          <Object>[
            ' ',
            {'c': 'C', 's': 'C'},
          ],
          <Object>['[Tab - Intro]'],
          <Object>['E|-------0-------|'],
          <Object>['B|---1-------1---|'],
          <Object>['[Chorus]'],
          <Object>['la la la'],
        ],
      })!;

      final text = buildChordPro(payload, allowedChords: {'C'});
      expect(text, contains('{start_of_intro: Intro}'));
      expect(text, contains('[C]'));
      expect(text, contains('{start_of_chorus: Chorus}'));
      expect(text, contains('la la la'));
      expect(text, isNot(contains('Tab - Intro')));
      expect(text, isNot(contains('E|---')));
      expect(text, isNot(contains('B|---')));
    });

    test('映射不越白名单:库没有的和弦保留原样交校验报错', () {
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          <Object>[
            {'c': 'F7M', 's': 'F7M'},
            ' ',
            {'c': 'E5', 's': 'E5'},
          ],
        ],
      })!;

      // F7M 没有可落库的映射时保留原样;E5(power chord)库没有,原样保留。
      expect(
        buildChordPro(payload, allowedChords: {'E5'}),
        '[F7M] [E5]\n',
      );
    });

    test('全管线:真实存档 Gravity 行结构 → 生成文本过真实和弦库白名单校验', () async {
      final lib = ChordLibrary.parse(
        await rootBundle.loadString('assets/chords/ukulele.json'),
      );
      // 行结构逐字对照 2026-06 存档页(embrace/gravity):
      // b 和弦行 / 纯文本 capo 行 / 歌词行 / 双 b 行 / [Chorus] 标记。
      final payload = decodeCifraPayload({
        'title': 'Gravity',
        'artist': 'Embrace',
        'lines': <List<Object>>[
          <Object>[
            {'c': 'D#', 's': 'D#'},
            ' ' * 18,
            {'c': 'Cm', 's': 'Cm'},
            ' ' * 10,
            {'c': 'Gm', 's': 'Gm'},
            ' ' * 9,
            {'c': 'G#', 's': 'G#'},
            ' ' * 6,
            {'c': 'D#', 's': 'D#'},
          ],
          ['C (with capo fret3) Am          Em         F        C'],
          ['Hunny its been a long time coming, And I cant stop now. '],
          <Object>[
            ' ' * 8,
            {'c': 'Cm', 's': 'Cm'},
            ' ' * 11,
            {'c': 'Gm', 's': 'Gm'},
            ' ' * 10,
            {'c': 'G#', 's': 'G#'},
            ' ' * 7,
            {'c': 'D#', 's': 'D#'},
          ],
          <Object>[
            ' ' * 8,
            {'c': 'Am', 's': 'Am'},
            ' ' * 11,
            {'c': 'Em', 's': 'Em'},
            ' ' * 10,
            {'c': 'F', 's': 'F'},
            ' ' * 8,
            {'c': 'C', 's': 'C'},
          ],
          ['Such a long time running, And I cant stop now. '],
          <Object>[],
          <Object>['[Chorus]'],
          <Object>[
            ' ' * 9,
            {'c': 'G#', 's': 'G#'},
            ' ' * 33,
            {'c': 'D#', 's': 'D#'},
          ],
          <Object>[
            ' ' * 9,
            {'c': 'F', 's': 'F'},
            ' ' * 34,
            {'c': 'C', 's': 'C'},
          ],
          ['And then i looked up at the sun and I could see '],
        ],
      })!;

      final text = buildChordPro(payload, allowedChords: lib.labels);
      final result = StrumChartParser.parse(text, allowedChords: lib.labels);

      expect(result.ok, isTrue, reason: '校验问题:${result.issues.map((i) => i.message)}');
      expect(result.chart!.title, 'Gravity');
      expect(result.chart!.artist, 'Embrace');
      final chordNames = {
        for (final section in result.chart!.sections)
          for (final line in section.lines)
            for (final chord in line.chords) chord.name,
      };
      expect(chordNames, containsAll(['Eb', 'Cm', 'Gm', 'Ab']));
      expect(
        chordNames.any((n) => n.contains('#')),
        isFalse,
        reason: '升号应已归一为和弦库的降号拼法',
      );
      expect(
        result.chart!.sections.map((s) => s.kind),
        contains(StrumSectionKind.chorus),
      );
      // capo 双记谱行没当歌词混进来。
      expect(text, contains('[Eb]Hunny its been a'));
      expect(text, isNot(contains('capo')));
    });
  });

  group('审计30(#11/#12/#13/#14)', () {
    test('含 ChordPro 特殊字符的文本安全转义,经解析器往返不失真(#11)', () {
      final payload = decodeCifraPayload({
        'title': 'Song {Live}',
        'artist': 'DJ Drop',
        'lines': <List<Object>>[
          [
            {'c': 'C', 's': 'C'},
            ' Love [forever] {comment: x}\n',
          ],
        ],
      })!;
      final chordpro = buildChordPro(payload, allowedChords: {'C'});
      // 直接经同一校验层:转义后不再被当未知和弦/杂指令拦。
      final result = StrumChartParser.parse(chordpro, allowedChords: {'C'});
      expect(result.issues, isEmpty, reason: '实际输出:$chordpro');
      final chart = result.chart!;
      // 花括号在指令值里无法无损编码:剥除降级,内容保留。
      expect(chart.title, 'Song Live');
      expect(chart.artist, 'DJ Drop');
      expect(chart.sections.single.lines.single.lyric,
          contains('Love [forever]'));
      expect(chart.sections.single.lines.single.lyric,
          contains('{comment: x}'));
    });

    test('纯器乐连续和弦行:等不到歌词时全部独立落盘,不丢行(#12)', () {
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          [
            {'c': 'C', 's': 'C'},
            '  ',
            {'c': 'G', 's': 'G'},
          ],
          [
            {'c': 'Am', 's': 'Am'},
            '  ',
            {'c': 'F', 's': 'F'},
          ],
          [''], // 空行:断开配对
        ],
      })!;
      expect(
        buildChordPro(payload, allowedChords: {'C', 'G', 'Am', 'F'}),
        '[C] [G]\n[Am] [F]\n',
      );
    });

    test('歌词到达时连续和弦行仍按双记谱只取首条(既有语义不回退)(#12)', () {
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          [
            {'c': 'Gm', 's': 'Gm'},
            '   ',
            {'c': 'Cm', 's': 'Cm'},
          ],
          [
            {'c': 'A#m', 's': 'A#m'},
          ],
          ['Some people wait'],
        ],
      })!;
      expect(
        buildChordPro(payload, allowedChords: {'Gm', 'Cm', 'Bbm'}),
        '[Gm]Some [Cm]people wait\n',
      );
    });

    test('混排行和弦同样过同音异名归一:D# 命中 Eb 白名单(#13)', () {
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          [
            'Intro: ',
            {'c': 'D#', 's': 'D#'},
            ' live\n',
          ],
        ],
      })!;
      expect(
        buildChordPro(payload, allowedChords: {'Eb'}),
        'Intro: [Eb] live\n',
      );
    });

    test('「Amor Eterno」不再判成和弦样:悬空行后的歌词保留(#14)', () {
      final payload = decodeCifraPayload({
        'lines': <List<Object>>[
          [
            {'c': 'C', 's': 'C'},
            '   ',
            {'c': 'G', 's': 'G'},
          ],
          ['Amor Eterno'],
          ['te dou meu coração'],
        ],
      })!;
      expect(
        buildChordPro(payload, allowedChords: {'C', 'G'}),
        '[C]Amor[G] Eterno\nte dou meu coração\n',
      );
    });
  });

}