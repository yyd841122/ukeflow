import 'package:flutter/material.dart';

import '../../data/chord_library.dart';
import 'chord_diagram.dart';
import 'chord_tips.dart';

/// 和弦详情：大指法图 + 按法切换 + 按法要点 + 常见错误。
/// 示范音试听由工单 05 在此页追加。
class ChordDetailPage extends StatefulWidget {
  const ChordDetailPage({super.key, required this.chord});

  final Chord chord;

  @override
  State<ChordDetailPage> createState() => _ChordDetailPageState();
}

class _ChordDetailPageState extends State<ChordDetailPage> {
  late int _index = widget.chord.fingerings.indexOf(widget.chord.primaryFingering);

  @override
  Widget build(BuildContext context) {
    final chord = widget.chord;
    final primaryIndex = chord.fingerings.indexOf(chord.primaryFingering);
    final showingPrimary = _index == primaryIndex;
    // 要点文案按主指法撰写；看其它按法时改显示按当前指法形状生成的提示，
    // 保证文字与图永远一致。
    final (essence, mistakes) = showingPrimary
        ? chordTips(chord)
        : (genericChordTips(chord.fingerings[_index]), null);
    return Scaffold(
      appBar: AppBar(title: Text(chord.label)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: ChordDiagram(fingering: chord.fingerings[_index], width: 230, showStringLabels: true)),
          if (chord.fingerings.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < chord.fingerings.length; i++)
                  ChoiceChip(
                    label: Text('按法 ${i + 1}'),
                    selected: i == _index,
                    onSelected: (_) => setState(() => _index = i),
                  ),
              ],
            ),
            if (!showingPrimary)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '详细要点按主指法（按法 ${primaryIndex + 1}）撰写，当前按法要点按图生成',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          _TipCard(title: '按法要点', body: essence),
          if (mistakes != null) ...[
            const SizedBox(height: 12),
            _TipCard(title: '常见错误', body: mistakes),
          ],
          const SizedBox(height: 12),
          Text(
            '○ 空弦　× 闷音　点内数字 = 手指编号',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
