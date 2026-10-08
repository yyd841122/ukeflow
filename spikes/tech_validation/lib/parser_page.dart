import 'package:chord_pro/chord_pro.dart';
import 'package:flutter/material.dart';

import 'sample_charts.dart';

/// Spike C 的设备端肉眼验收：解析结果结构化展示。
/// 自动化断言在 test/parser_spike_test.dart。
class ParserPage extends StatefulWidget {
  const ParserPage({super.key});

  @override
  State<ParserPage> createState() => _ParserPageState();
}

class _ParserPageState extends State<ParserPage> {
  String _name = '';
  ParseResult? _result;

  void _parse(String name, String source) {
    setState(() {
      _name = name;
      _result = ChordPro.parse(source);
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => _parse('干净英文谱', cleanChart),
                child: const Text('英文谱'),
              ),
              FilledButton.tonal(
                onPressed: () => _parse('中文贴字谱', chineseChart),
                child: const Text('中文谱'),
              ),
              FilledButton.tonal(
                onPressed: () => _parse('压力谱', stressChart),
                child: const Text('压力谱'),
              ),
            ],
          ),
        ),
        Expanded(
          child: result == null
              ? const Center(child: Text('选择一份样例谱进行解析'))
              : _ResultView(name: _name, result: result),
        ),
      ],
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.name, required this.result});

  final String name;
  final ParseResult result;

  @override
  Widget build(BuildContext context) {
    final song = result.songs.first;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        Text(name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text('段落 ${song.sections.length} · '
            '和弦 token ${_countChords(song)} · '
            '诊断 ${result.diagnostics.length} 条'),
        for (final d in result.diagnostics.take(8))
          Text(d.toString(),
              style: TextStyle(
                  fontSize: 11,
                  color: d.severity == DiagnosticSeverity.error
                      ? Colors.red
                      : Colors.orange)),
        for (final section in song.sections) ...[
          const SizedBox(height: 8),
          Text('── ${section.kind.name}${section.label == null ? '' : ' (${section.label})'}',
              style: const TextStyle(color: Colors.teal)),
          for (final line in section.lines)
            if (line.isVerbatim)
              Text(line.verbatim ?? '',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12))
            else
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final token in line.tokens)
                    if (token is ChordToken)
                      Text(' ${token.raw} ',
                          style: const TextStyle(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold))
                    else if (token is TextToken)
                      Text(token.text)
                    else if (token is AnnotationToken)
                      Text('(${token.text})',
                          style: const TextStyle(color: Colors.orange)),
                ],
              ),
        ],
      ],
    );
  }

  int _countChords(Song song) => [
        for (final s in song.sections)
          for (final l in s.lines)
            for (final t in l.tokens)
              if (t is ChordToken) t
      ].length;
}
