import 'package:chord_pro/chord_pro.dart';

import '../model/strum_chart.dart';

export '../model/strum_chart.dart';

/// 谱面校验问题的稳定类别。消息文案可改，switch 请认 code。
enum ChartIssueCode {
  /// `{start_of_x}` 开了没关（解析器静默自动闭合——校验层拦下，ADR-0006）。
  unterminatedSection,

  /// 新段落开始时上一个段落还没闭合（段落不能嵌套）。
  nestedSection,

  /// `{end_of_x}` 没有对应的开始指令。
  strayEnd,

  /// `{end_of_x}` 与当前打开的段落类型不匹配。
  mismatchedEnd,

  /// 带选择器的段落未闭合（冷门语法，一并拦截）。
  unterminatedSuppressedSection,

  /// 回唤语法没有可回唤的目标（{chorus} 前没有副歌段；[^] 前没有和弦）。
  danglingRecall,

  /// 谱面用了本 App 不支持的指令（{transpose} 移调、非 4/4 拍号）——
  /// 显式拒绝而非静默按原调/4/4 播放(审计 2026-10-16 #17)。
  unsupportedDirective,

  /// 和弦名不在白名单（和弦库数据）里。
  unknownChord,

  /// 方括号内容连解析器都认不出是和弦。
  unparseableChord,

  /// 一份谱出现多首歌（`{new_song}`）——一份谱只应有一首歌。
  multipleSongs,

  /// 解析器报出的其他 error 级诊断（几乎不出现，出现即拦）。
  parserError,
}

/// 一个校验问题：可读（含谱面原文上下文）、可定位（第几行第几列，1 起）。
class ChartIssue {
  const ChartIssue({
    required this.code,
    required this.line,
    required this.column,
    required this.message,
  });

  final ChartIssueCode code;
  final int line;
  final int column;
  final String message;

  @override
  String toString() => message;
}

/// 解析+校验结果：[issues] 非空则 [chart] 为 null（宽进严出，ADR-0006——
/// 坏谱一个模型对象都不产出）。
class ChartParseResult {
  const ChartParseResult({required this.chart, required this.issues});

  /// 仅当 [issues] 为空时非 null。
  final StrumChart? chart;
  final List<ChartIssue> issues;

  bool get ok => issues.isEmpty;
}

/// 弹唱谱解析+校验的唯一入口。
///
/// 解析交给 chord_pro（极宽容，几乎不报错），谱面合法性由本层把关：
/// 段落闭合检查（把解析器静默吞掉的段落结构问题拦为 error）+
/// 和弦名白名单（对照和弦库数据，保证谱内和弦都能查到指法与示范音）。
class StrumChartParser {
  StrumChartParser._();

  static ChartParseResult parse(
    String source, {
    required Set<String> allowedChords,
  }) {
    final result = ChordPro.parse(source);
    final issues = <ChartIssue>[];
    final sourceLines = source.split('\n');

    for (final d in result.diagnostics) {
      final issue = _issueFromDiagnostic(d, sourceLines);
      if (issue != null) issues.add(issue);
    }

    if (result.songs.length > 1) {
      issues.add(
        ChartIssue(
          code: ChartIssueCode.multipleSongs,
          line: 1,
          column: 1,
          message: '一份谱只应有一首歌，但谱里出现了 '
              '${result.songs.length} 首（{new_song}）',
        ),
      );
    }

    final song = result.songs.first;
    issues.addAll(_unsupportedDirectiveIssues(song, sourceLines));
    issues.addAll(_chordIssues(song, allowedChords));

    if (issues.isNotEmpty) {
      return ChartParseResult(chart: null, issues: List.unmodifiable(issues));
    }
    return ChartParseResult(
      chart: _toChart(result.songs.first),
      issues: const [],
    );
  }

  /// 把解析器诊断复判为校验问题：段落结构问题（解析器只给 warning 甚至
  /// 静默）一律升为 error；其余 error 级诊断照拦；良性 warning 放行。
  static ChartIssue? _issueFromDiagnostic(
    Diagnostic d,
    List<String> sourceLines,
  ) {
    switch (d.code) {
      case DiagnosticCode.unterminatedSection:
        return _issue(
          d,
          ChartIssueCode.unterminatedSection,
          _locate(d, sourceLines, (text) => text == null
              ? '有段落没有闭合'
              : '段落 $text 没有闭合'),
        );
      case DiagnosticCode.nestedSection:
        return _issue(
          d,
          ChartIssueCode.nestedSection,
          _locate(d, sourceLines, (text) => text == null
              ? '上一个段落还未闭合就开了新段落（段落不能嵌套）'
              : '$text 出现在上一个段落还未闭合时（段落不能嵌套）'),
        );
      case DiagnosticCode.strayEnd:
        return _issue(
          d,
          ChartIssueCode.strayEnd,
          _locate(d, sourceLines, (text) => text == null
              ? '结束指令没有对应的开始指令'
              : '$text 没有对应的开始指令'),
        );
      case DiagnosticCode.mismatchedEnd:
        return _issue(
          d,
          ChartIssueCode.mismatchedEnd,
          _locate(d, sourceLines, (text) => text == null
              ? '结束指令与当前打开的段落不匹配'
              : '$text 与当前打开的段落不匹配'),
        );
      case DiagnosticCode.unterminatedSuppressedSection:
        return _issue(
          d,
          ChartIssueCode.unterminatedSuppressedSection,
          _locate(d, sourceLines, (_) => '带选择器的段落没有闭合'),
        );
      default:
        return d.severity == DiagnosticSeverity.error
            ? _issue(
                d,
                ChartIssueCode.parserError,
                _locate(d, sourceLines, (_) => d.message),
              )
            : null;
    }
  }

  static ChartIssue _issue(Diagnostic d, ChartIssueCode code, String message) =>
      ChartIssue(
        code: code,
        line: d.span.line,
        column: d.span.column,
        message: message,
      );

  /// 错误消息定位段：行列前缀 + 谱面指令原文（取不到原文时退化为纯定位）。
  static String _locate(
    Diagnostic d,
    List<String> sourceLines,
    String Function(String? directiveText) describe,
  ) {
    return '${_at(d.span)}：${describe(_directiveTextAt(sourceLines, d.span))}';
  }

  static String _at(SourceSpan span) =>
      '第 ${span.line} 行第 ${span.column} 列';

  /// 不支持指令检查:{transpose} 与非 4/4 拍号此前被静默丢弃(谱照过、
  /// 播放按原调/4/4 走,音全错)——显式拒绝,给可读消息,定位到指令
  /// 原文所在行列(审计 2026-10-16 #17)。
  static List<ChartIssue> _unsupportedDirectiveIssues(
    Song song,
    List<String> sourceLines,
  ) {
    final issues = <ChartIssue>[];
    for (final d in song.directives) {
      final value = (d.value ?? '').trim();
      switch (d.name) {
        case 'transpose':
          final semitones = int.tryParse(value);
          if (semitones != null && semitones != 0) {
            issues.add(
              ChartIssue(
                code: ChartIssueCode.unsupportedDirective,
                line: d.span.line,
                column: d.span.column,
                message: '${_at(d.span)}:{transpose: $semitones} 要求移调，'
                    '本 App 不支持移调;请把谱面转回原调后再导入',
              ),
            );
          }
        case 'time':
          if (value != '4/4') {
            issues.add(
              ChartIssue(
                code: ChartIssueCode.unsupportedDirective,
                line: d.span.line,
                column: d.span.column,
                message: '${_at(d.span)}:拍号 {$value} 不是 4/4，'
                    '本 App 仅支持 4/4 节拍网格',
              ),
            );
          }
      }
    }
    return issues;
  }

  /// 和弦白名单 + 回唤目标检查(遍历**活跃段**——选择器抑制段是别乐器
  /// 的内容,参与校验会把不支持和弦误拒成导入失败,审计 2026-10-16 #15)。
  /// 回唤:{chorus} 前须有原版副歌段、[^] 前须有和弦,否则转换会静默
  /// 丢内容(审计 2026-10-16 #16)。
  static List<ChartIssue> _chordIssues(
    Song song,
    Set<String> allowedChords,
  ) {
    final issues = <ChartIssue>[];
    Section? lastChorus;
    String? lastChordName;
    for (final section in song.activeSections) {
      if (section.isChorusRecall) {
        if (lastChorus == null) {
          issues.add(
            ChartIssue(
              code: ChartIssueCode.danglingRecall,
              line: section.span.line,
              column: section.span.column,
              message: '${_at(section.span)}:{chorus} 回唤之前没有副歌段可回唤',
            ),
          );
        }
        continue;
      }
      if (section.kind == SectionKind.chorus) lastChorus = section;
      for (final line in section.lines) {
        for (final token in line.tokens) {
          if (token is ChordRecallToken) {
            if (lastChordName == null) {
              issues.add(
                ChartIssue(
                  code: ChartIssueCode.danglingRecall,
                  line: token.span.line,
                  column: token.span.column,
                  message: '${_at(token.span)}:[^] 回唤之前没有和弦可回唤',
                ),
              );
            }
            continue;
          }
          if (token is! ChordToken) continue;
          final name = token.raw.trim();
          if (token.chord == null) {
            issues.add(
              ChartIssue(
                code: ChartIssueCode.unparseableChord,
                line: token.span.line,
                column: token.span.column,
                message: '${_at(token.span)}：'
                    '[${token.raw}] 不是能识别的和弦名',
              ),
            );
          } else if (!allowedChords.contains(name)) {
            issues.add(
              ChartIssue(
                code: ChartIssueCode.unknownChord,
                line: token.span.line,
                column: token.span.column,
                message: '${_at(token.span)}：'
                    '和弦 [$name] 不在和弦库中',
              ),
            );
          } else {
            lastChordName = name;
          }
        }
      }
    }
    return issues;
  }

  /// 取谱面上某 span 覆盖的原文（如 `{start_of_verse}`），供错误消息引用；
  /// 越界/不一致时返回 null（消息退化为不带原文的定位）。
  static String? _directiveTextAt(List<String> sourceLines, SourceSpan span) {
    if (span.line < 1 || span.line > sourceLines.length) return null;
    final text = sourceLines[span.line - 1];
    final start = span.column - 1;
    if (start < 0 || start + span.length > text.length) return null;
    return text.substring(start, start + span.length);
  }

  /// AST → 弹唱谱模型。丢弃与弹唱无关的行（注释/图片/换版式）与
  /// 逐字环境段落（tab 等），空行不产出 [StrumLine]。只遍历**活跃段**
  /// (选择器抑制段是别乐器的变奏,不进播放,审计 2026-10-16 #15);
  /// {chorus} 回唤展开为最近原版副歌的拷贝、[^] 回唤展开为最近和弦
  /// (目标存在性已由校验层保证,审计 2026-10-16 #16)。
  static StrumChart _toChart(Song song) {
    final sections = <StrumSection>[];
    Section? lastChorus;
    String? lastChordName;

    StrumSection? convert(Section section) {
      if (_isVerbatimKind(section.kind)) return null;
      final lines = <StrumLine>[];
      for (final line in section.lines) {
        if (line.kind != LineKind.structured) continue;
        final buf = StringBuffer();
        final chords = <ChordMark>[];
        for (final token in line.tokens) {
          switch (token) {
            case TextToken(:final text):
              buf.write(text);
            case ChordToken(:final raw):
              final name = raw.trim();
              chords.add(ChordMark(name: name, offset: buf.length));
              lastChordName = name;
            case ChordRecallToken():
              // 校验层保证此前必有和弦:回唤展开为最近和弦。
              chords.add(
                ChordMark(name: lastChordName!, offset: buf.length),
              );
            case AnnotationToken() || InlineDirectiveToken():
              break; // 与弹唱谱无关的记号，忽略
          }
        }
        final lyric = buf.toString();
        if (lyric.isEmpty && chords.isEmpty) continue;
        lines.add(StrumLine(lyric: lyric, chords: List.unmodifiable(chords)));
      }
      if (lines.isEmpty) return null;
      return StrumSection(
        kind: _sectionKind(section.kind),
        label: section.label,
        lines: List.unmodifiable(lines),
      );
    }

    for (final section in song.activeSections) {
      if (section.isChorusRecall) {
        final recall = lastChorus == null ? null : convert(lastChorus);
        if (recall != null) sections.add(recall);
        continue;
      }
      final converted = convert(section);
      if (converted != null) sections.add(converted);
      if (section.kind == SectionKind.chorus) lastChorus = section;
    }
    final meta = song.metadata;
    return StrumChart(
      title: meta.titles.isEmpty ? StrumChart.untitled : meta.titles.first,
      artist: meta.artists.isEmpty ? null : meta.artists.first,
      key: meta.keys.isEmpty ? null : meta.keys.first,
      tempo: meta.tempo,
      sections: List.unmodifiable(sections),
    );
  }

  static bool _isVerbatimKind(SectionKind kind) => switch (kind) {
        SectionKind.tab ||
        SectionKind.grid ||
        SectionKind.abc ||
        SectionKind.ly ||
        SectionKind.svg ||
        SectionKind.textblock ||
        SectionKind.grille => true,
        _ => false,
      };

  static StrumSectionKind _sectionKind(SectionKind kind) => switch (kind) {
        SectionKind.verse => StrumSectionKind.verse,
        SectionKind.chorus => StrumSectionKind.chorus,
        SectionKind.bridge => StrumSectionKind.bridge,
        SectionKind.loose => StrumSectionKind.loose,
        _ => StrumSectionKind.other,
      };
}
