import 'package:flutter/material.dart';

import '../rhythm/metronome_page.dart';
import '../rhythm/rhythm_trainer_page.dart';

/// 跟练页签(工单 15 起瘦身):练琴工具入口——节拍器与节奏型训练
/// (练稳定右手不依赖跟练引擎,工单 06/09 迁移保留)。曲目浏览与跟练
/// 入口在曲库页:列表唯一家,点弹唱谱/指弹谱直达对应跟练会话页。
class PlayPage extends StatelessWidget {
  const PlayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MetronomePage(),
                  ),
                ),
                icon: const Icon(Icons.av_timer),
                label: const Text('节拍器'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RhythmTrainerPage(),
                  ),
                ),
                icon: const Icon(Icons.swap_vert),
                label: const Text('节奏型训练'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
