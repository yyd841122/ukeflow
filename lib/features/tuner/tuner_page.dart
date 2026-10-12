import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/providers.dart';
import '../../core/model/uke_string.dart';
import '../../core/ui/placeholder_page.dart';

/// 调音器页:拾音调音由工单 19 迁入(占位);
/// 空弦试音先行——点弦名拨响标准音,可对照听音调弦。
class TunerPage extends ConsumerStatefulWidget {
  const TunerPage({super.key});

  @override
  ConsumerState<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends ConsumerState<TunerPage> {
  Future<void> _pluck(UkeString string) async {
    try {
      await ref.read(pluckPlayerProvider).pluck(freq: string.frequency);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('试音失败:$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 页签页不自带 AppBar(页题在占位体与底栏各一份,导航壳统一管理)。
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const PlaceholderPage(title: '调音器', icon: Icons.tune),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('空弦试音', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '点弦名拨响标准音,对照实体琴调弦',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    for (final string in UkeString.values)
                      FilledButton.tonal(
                        onPressed: () => _pluck(string),
                        child: Text('${string.number}弦 ${string.label}'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
