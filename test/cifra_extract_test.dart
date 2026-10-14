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
}
