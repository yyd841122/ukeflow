import 'package:flutter/material.dart';

import '../../core/ui/placeholder_page.dart';
import '../rhythm/metronome_page.dart';

/// 跟练页:正式跟练引擎由后续工单实现(占位);
/// 节拍器先行入驻——练稳定右手不依赖跟练引擎。
class PlayPage extends StatelessWidget {
  const PlayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PlaceholderPage(
            title: '跟练',
            icon: Icons.play_circle_outline,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MetronomePage(),
              ),
            ),
            icon: const Icon(Icons.av_timer),
            label: const Text('节拍器'),
          ),
        ],
      ),
    );
  }
}
