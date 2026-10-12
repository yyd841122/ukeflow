import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/providers.dart';
import '../../data/chord_library.dart';
import 'chord_diagram.dart';
import 'chord_tips.dart';

/// 和弦详情：大指法图 + 试听（按当前指法错峰拨响应响的弦，工单 05）+
/// 按法切换 + 按法要点 + 常见错误。
class ChordDetailPage extends ConsumerStatefulWidget {
  const ChordDetailPage({super.key, required this.chord});

  final Chord chord;

  @override
  ConsumerState<ChordDetailPage> createState() => _ChordDetailPageState();
}

class _ChordDetailPageState extends ConsumerState<ChordDetailPage> {
  late int _index = widget.chord.fingerings.indexOf(widget.chord.primaryFingering);

  /// 试听当前指法(GLOSSARY「和弦示范音」):闷音弦跳过、空弦拨响,
  /// 错峰与音源加载细节都在 PluckPlayer.strum。失败以 SnackBar 呈现。
  Future<void> _audition() async {
    try {
      await ref.read(pluckPlayerProvider).strum(
        freqs: widget.chord.fingerings[_index].stringFrequencies,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('试听失败:$error')));
      }
    }
  }
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
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _audition,
              icon: const Icon(Icons.music_note),
              label: const Text('试听'),
            ),
          ),
          if (chord.fingerings.length > 1) ...[
            const SizedBox(height: 12),
            // 一行宽度均分(按法全库上限 4 个):同工单 04 四弦钮的做法。
            // 水平内边距收小:M3 默认值会把四等分内宽挤到「按法 4」折行;
            // 选中态去掉 ✓(琥珀填充已足够醒目),✓ 会把「按法 1」挤到折行被裁。
            ChipTheme(
              data: ChipTheme.of(context).copyWith(showCheckmark: false),
              child: Row(
                children: [
                  for (var i = 0; i < chord.fingerings.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          label: Text('按法 ${i + 1}'),
                          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          selected: i == _index,
                          onSelected: (_) => setState(() => _index = i),
                        ),
                      ),
                    ),
                ],
              ),
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
