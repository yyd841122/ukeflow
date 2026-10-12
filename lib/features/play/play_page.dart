import 'package:flutter/material.dart';

import '../../core/ui/placeholder_page.dart';
import '../rhythm/metronome_page.dart';
import '../rhythm/rhythm_trainer_page.dart';

/// 跟练页:正式跟练引擎由后续工单实现(占位);
/// 节拍器与节奏型训练先行入驻——练稳定右手不依赖跟练引擎
/// (工单 09 重做本页时迁移)。
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
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RhythmTrainerPage(),
              ),
            ),
            icon: const Icon(Icons.swap_vert),
            label: const Text('节奏型训练'),
          ),
        ],
      ),
    );
  }
}
