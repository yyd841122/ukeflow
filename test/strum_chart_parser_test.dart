import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/strum_chart_parser.dart';

import 'fixtures/charts/sample_charts.dart';

/// 工单 07 seam：谱文本 →（解析+校验）→ 弹唱谱。
/// 期望值来自 spike C 迁入样例的已知字面量，与实现无共谋。
void main() {
  group('StrumChartParser.parse 好谱', () {
    test('中文紧贴谱：歌词逐字保留，和弦标记带歌词内偏移', () {
      final result = StrumChartParser.parse(
        chineseChart,
        allowedChords: const {'C', 'Am', 'Em', 'F', 'G'},
      );

      expect(result.ok, isTrue);
      final chart = result.chart!;
      expect(chart.title, '爱你不是两三天');
      expect(chart.artist, '梁静茹');
      expect(chart.key, 'C');

      // {c: ...} 注释不成段、前后空行不产生空段：只剩主歌+副歌
      expect(chart.sections, hasLength(2));
      final verse = chart.sections[0];
      expect(verse.kind, StrumSectionKind.verse);
      expect(verse.lines, hasLength(4));

      // [Am]爱你不是两三天：和弦在行首
      expect(verse.lines[0].lyric, '爱你不是两三天');
      expect(verse.lines[0].chords, hasLength(1));
      expect(verse.lines[0].chords[0].name, 'Am');
      expect(verse.lines[0].chords[0].offset, 0);

      // [F]还不[Em]习惯：行中和弦按歌词字符下标定位
      expect(verse.lines[2].lyric, '还不习惯');
      expect(verse.lines[2].chords.map((c) => c.name).toList(), ['F', 'Em']);
      expect(verse.lines[2].chords.map((c) => c.offset).toList(), [0, 2]);
    });

    test('英文谱：元数据 tempo/key 齐全，段落类型齐全', () {
      final result = StrumChartParser.parse(
        cleanChart,
        allowedChords: const {'C', 'Am', 'Em', 'F', 'Dm', 'G'},
      );

      final chart = result.chart!;
      expect(chart.title, contains('Big Big World'));
      expect(chart.tempo, 88);
      expect(
        chart.sections.map((s) => s.kind),
        containsAll([StrumSectionKind.verse, StrumSectionKind.chorus]),
      );
    });

    test('无段落指令的散行也是合法谱（loose）', () {
      final result = StrumChartParser.parse(
        '[C]门口坐着一个小[Am]孩\n',
        allowedChords: const {'C', 'Am'},
      );

      final chart = result.chart!;
      expect(chart.sections, hasLength(1));
      expect(chart.sections.first.kind, StrumSectionKind.loose);
      expect(chart.sections.first.lines.single.lyric, '门口坐着一个小孩');
    });
  });

  group('StrumChartParser.parse 段落闭合拦截（ADR-0006 自建校验）', () {
    test('段落开了没关：拦下，报行号与指令原文', () {
      final result = StrumChartParser.parse(
        '{title: 坏谱}\n{start_of_verse}\n[C]歌词\n',
        allowedChords: const {'C'},
      );

      expect(result.chart, isNull);
      final issue = result.issues.single;
      expect(issue.code, ChartIssueCode.unterminatedSection);
      expect(issue.line, 2);
      expect(issue.message, contains('第 2 行'));
      expect(issue.message, contains('{start_of_verse}'));
      expect(issue.message, contains('没有闭合'));
    });

    test('多余的结束指令：拦下并报原文', () {
      final result = StrumChartParser.parse(
        '{title: 坏谱}\n\n{end_of_chorus}\n',
        allowedChords: const {'C'},
      );

      expect(result.chart, isNull);
      final issue = result.issues.single;
      expect(issue.code, ChartIssueCode.strayEnd);
      expect(issue.line, 3);
      expect(issue.message, contains('{end_of_chorus}'));
    });

    test('结束指令与打开段落不匹配：拦下并报原文', () {
      final result = StrumChartParser.parse(
        '{start_of_verse}\n[C]歌词\n{end_of_chorus}\n',
        allowedChords: const {'C'},
      );

      expect(result.chart, isNull);
      final issue = result.issues.single;
      expect(issue.code, ChartIssueCode.mismatchedEnd);
      expect(issue.line, 3);
      expect(issue.message, contains('{end_of_chorus}'));
      expect(issue.message, contains('不匹配'));
    });

    test('段落嵌套：拦下（后续错位的结束指令也一并报出）', () {
      final result = StrumChartParser.parse(
        '{start_of_verse}\n{start_of_chorus}\n[C]歌词\n{end_of_chorus}\n{end_of_verse}\n',
        allowedChords: const {'C'},
      );

      expect(result.chart, isNull);
      expect(
        result.issues.map((i) => i.code),
        contains(ChartIssueCode.nestedSection),
      );
      final nested = result.issues.firstWhere(
        (i) => i.code == ChartIssueCode.nestedSection,
      );
      expect(nested.line, 2);
      expect(nested.message, contains('{start_of_chorus}'));
    });
  });

  group('StrumChartParser.parse 和弦名白名单（对照和弦库数据）', () {
    test('白名单外和弦名：拦下，报行列与和弦名', () {
      final result = StrumChartParser.parse(
        '{start_of_verse}\n[H]歌词\n{end_of_verse}\n',
        allowedChords: const {'C', 'Am'},
      );

      expect(result.chart, isNull);
      final issue = result.issues.single;
      expect(issue.code, ChartIssueCode.unknownChord);
      expect(issue.line, 2);
      expect(issue.column, 1);
      expect(issue.message, contains('[H]'));
      expect(issue.message, contains('不在和弦库中'));
    });

    test('连解析器都认不出的和弦记号：单独报「不能识别」', () {
      // 方括号内紧跟空格 → chord_pro 给出 chord=null 的记号（空括号 [] 则
      // 被记号器直接丢弃、不产出任何记号，无需拦截）
      final result = StrumChartParser.parse(
        '[ C]歌词\n',
        allowedChords: const {'C'},
      );

      expect(result.chart, isNull);
      final issue = result.issues.single;
      expect(issue.code, ChartIssueCode.unparseableChord);
      expect(issue.line, 1);
      expect(issue.message, contains('[ C]'));
      expect(issue.message, contains('不是能识别的和弦名'));
    });

    test('多个坏和弦全部报出，不止第一个', () {
      final result = StrumChartParser.parse(
        '[H]一 [Q]二\n',
        allowedChords: const {'C'},
      );

      expect(result.chart, isNull);
      expect(result.issues, hasLength(2));
      expect(
        result.issues.map((i) => i.code).toSet(),
        {ChartIssueCode.unknownChord, ChartIssueCode.unparseableChord},
      );
    });

    test('和弦名首尾空白容忍：[Am ] 视为 Am 放行', () {
      final result = StrumChartParser.parse(
        '[Am ]歌词\n',
        allowedChords: const {'Am'},
      );

      expect(result.ok, isTrue);
      expect(result.chart!.sections.single.lines.single.chords.single.name,
          'Am');
    });
  });

  group('审计30(#15/#16/#17)', () {
    const allowed = {'C', 'G', 'Am'};

    test('选择器抑制段不参与校验也不进谱(#15)', () {
      final result = StrumChartParser.parse(
        '{start_of_verse}\n[C]词\n{end_of_verse}\n'
        '{start_of_verse-guitar}\n[F#]guitar only\n{end_of_verse-guitar}\n',
        allowedChords: allowed,
      );
      expect(result.issues, isEmpty, reason: '抑制段里的 F# 不得误拒导入');
      expect(result.chart!.sections, hasLength(1));
      expect(result.chart!.sections.single.lines.single.chords.single.name,
          'C');
    });

    test('{chorus} 回唤展开为最近副歌拷贝;[^] 回唤展开为最近和弦(#16)', () {
      final result = StrumChartParser.parse(
        '{start_of_chorus}\n[C]副歌\n{end_of_chorus}\n'
        '{start_of_verse}\n[Am]主歌 [^]词\n{end_of_verse}\n'
        '{chorus}\n',
        allowedChords: allowed,
      );
      expect(result.issues, isEmpty);
      final sections = result.chart!.sections;
      expect(sections, hasLength(3));
      expect(sections[0].kind, StrumSectionKind.chorus);
      // 回唤段 = 副歌拷贝:同和弦同词。
      expect(sections[2].kind, StrumSectionKind.chorus);
      expect(sections[2].lines.single.chords.single.name, 'C');
      expect(sections[2].lines.single.lyric, sections[0].lines.single.lyric);
      // [^] = 最近和弦 Am。
      expect(sections[1].lines.single.chords.map((c) => c.name).toList(),
          ['Am', 'Am']);
    });

    test('悬空回唤显式拒:{chorus} 无副歌、[^] 无和弦(#16)', () {
      final noChorus = StrumChartParser.parse(
        '{start_of_verse}\n[C]词\n{end_of_verse}\n{chorus}\n',
        allowedChords: allowed,
      );
      expect(
        noChorus.issues.any((i) => i.code == ChartIssueCode.danglingRecall),
        isTrue,
      );
      final noChord = StrumChartParser.parse(
        '{start_of_verse}\n[^]词\n{end_of_verse}\n',
        allowedChords: allowed,
      );
      expect(
        noChord.issues.any((i) => i.code == ChartIssueCode.danglingRecall),
        isTrue,
      );
    });

    test('{transpose} 与非 4/4 拍号显式拒,不再静默按原调 4/4 播(#17)', () {
      final transposed = StrumChartParser.parse(
        '{transpose: 2}\n[C]词\n',
        allowedChords: allowed,
      );
      expect(
        transposed.issues
            .any((i) => i.code == ChartIssueCode.unsupportedDirective),
        isTrue,
      );
      expect(transposed.chart, isNull);
      final waltz = StrumChartParser.parse(
        '{time: 3/4}\n[C]词\n',
        allowedChords: allowed,
      );
      expect(
        waltz.issues.any((i) => i.code == ChartIssueCode.unsupportedDirective),
        isTrue,
      );
      expect(waltz.chart, isNull);
      // 4/4 与 transpose 0 照常放行。
      final ok = StrumChartParser.parse(
        '{time: 4/4}\n{transpose: 0}\n[C]词\n',
        allowedChords: allowed,
      );
      expect(ok.issues, isEmpty);
      expect(ok.chart, isNotNull);
    });
  });


  test('移调/拍号的变体形态同样拒:非整数值、行内指令(verify 复核 #17)', () {
    const allowed = {'C', 'G', 'Am'};
    final weird = StrumChartParser.parse(
      '{transpose: 2s}\n[C]词\n',
      allowedChords: allowed,
    );
    expect(
      weird.issues.any((i) => i.code == ChartIssueCode.unsupportedDirective),
      isTrue,
      reason: '非整数值的移调指令不得静默忽略',
    );
    final inline = StrumChartParser.parse(
      '{start_of_verse}\n[C]词 {transpose: 2}\n{end_of_verse}\n',
      allowedChords: allowed,
    );
    expect(
      inline.issues.any((i) => i.code == ChartIssueCode.unsupportedDirective),
      isTrue,
      reason: '行内移调指令不得静默忽略',
    );
  });

}