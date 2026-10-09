import 'package:chord_pro/chord_pro.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/charts/sample_charts.dart';

/// Spike C 三语义回归（自 spikes/tech_validation/test/parser_spike_test.dart
/// 迁入，断言不改）——守的是 chord_pro 包的语义，升级包时第一时间报警：
/// 1. Chord.root 只含根音字母，quality 分离存储；
/// 2. {transpose} 指令不改动 token 流，移调必须显式调 song.transposed(n)；
/// 3. 解析器极宽容（未知指令/未闭合段落静默、几乎不产生 error 诊断）——
///    所以谱面校验是 UkeFlow 自建层的责任（ADR-0006）。
List<ChordToken> _chordsOf(Song song) => [
      for (final section in song.sections)
        for (final line in section.lines)
          for (final token in line.tokens)
            if (token is ChordToken) token,
    ];

String _textOf(Song song) {
  final buf = StringBuffer();
  for (final section in song.sections) {
    for (final line in section.lines) {
      for (final token in line.tokens) {
        if (token is TextToken) buf.write(token.text);
      }
    }
  }
  return buf.toString();
}

void main() {
  group('chord_pro 解析器语义回归（Spike C 迁入）', () {
    test('干净英文谱：元数据/段落/和弦齐全，无 error 诊断', () {
      final result = ChordPro.parse(cleanChart);

      expect(result.songs, hasLength(1));
      final song = result.songs.first;
      expect(song.metadata.titles.first, contains('Big Big World'));
      expect(song.metadata.artists.first, contains('Emilia'));
      expect(
        song.sections.map((s) => s.kind),
        containsAll([SectionKind.verse, SectionKind.chorus]),
      );
      expect(
        _chordsOf(song).map((c) => c.raw).toSet(),
        containsAll(['C', 'Am', 'Em', 'F', 'Dm', 'G']),
      );
      expect(
        result.diagnostics
            .where((d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
      );
    });

    test('中文贴字谱：歌词逐字保留，和弦与汉字紧贴可解析', () {
      final result = ChordPro.parse(chineseChart);
      final song = result.songs.first;

      final text = _textOf(song);
      expect(text, contains('爱你不是两三天'));
      expect(text, contains('每天却想你很多遍'));

      final firstLineChords = song.sections
          .firstWhere((s) => s.kind == SectionKind.verse)
          .lines
          .first
          .tokens
          .whereType<ChordToken>()
          .map((c) => c.raw)
          .toList();
      expect(firstLineChords, ['Am']);
    });

    test('语义一：root 只含根音字母，quality 分离存储', () {
      final result = ChordPro.parse(cleanChart);
      final am = _chordsOf(result.songs.first).firstWhere((c) => c.raw == 'Am');

      expect(am.chord!.root, 'A');
      expect(am.chord!.quality, 'm');
      expect(am.chord!.raw, 'Am');
    });

    test('语义二：{transpose} 指令不改动 token 流，移调必须显式 transposed()', () {
      // 谱内写了 {transpose: 2}（见 stressChart），token 流里的和弦原样不动
      final result = ChordPro.parse(stressChart);
      final roots =
          _chordsOf(result.songs.first).map((c) => c.chord?.root).toSet();
      expect(roots, contains('C'));

      // 显式移调才生效：cleanChart +2 → C Am Em F Dm G 变为 D B F# G E A
      final transposed =
          ChordPro.parse(cleanChart).songs.first.transposed(2);
      expect(
        _chordsOf(transposed).map((c) => c.chord?.root).toSet(),
        containsAll(['D', 'B', 'F#', 'G', 'E', 'A']),
      );
      expect(_chordsOf(transposed).map((c) => c.raw), isNot(contains('C')));
    });

    test('语义三：压力谱不抛异常，tab 原样保留，未闭合段落静默零 error', () {
      final result = ChordPro.parse(stressChart + stressChartSuffix);
      final song = result.songs.first;

      final tabSections =
          song.sections.where((s) => s.kind == SectionKind.tab).toList();
      expect(tabSections, hasLength(1));
      final tabText = [
        for (final line in tabSections.first.lines)
          if (line.isVerbatim) line.verbatim ?? '',
      ].join('\n');
      expect(tabText, contains('e|--0--2--3--|'));

      // Spike 结论：未闭合的 {soc} 不抛异常、静默自动闭合、零 error 诊断。
      // 该解析器极其宽容，谱面语法校验需 UkeFlow 自建
      expect(
        result.diagnostics
            .where((d) => d.severity == DiagnosticSeverity.error),
        isEmpty,
      );
    });
  });
}
