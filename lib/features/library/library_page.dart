import 'package:flutter/material.dart';

import '../play/flowing_score_page.dart';
import '../rhythm/metronome_page.dart';
import '../rhythm/rhythm_trainer_page.dart';
import 'image_pick_flow.dart';
import 'library_chart_list_page.dart';
import 'score_source_import_flow.dart';

/// 曲库首屏:练琴工具与类型目录,歌曲和导入入口在各类型列表内。
class LibraryPage extends StatelessWidget {
  const LibraryPage({
    super.key,
    this.imagePickFlow,
    this.scoreSourceImportFlow,
  });

  /// 选图流程随图片谱入口传入列表,保留测试注入缝。
  final ImagePickFlow? imagePickFlow;

  /// 识谱源导入流程随独奏谱入口传入列表,同上注入缝。
  final ScoreSourceImportFlow? scoreSourceImportFlow;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        // 工具行不依赖曲库数据:加载/错误态也在,练琴不被列表问题挡路。
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
        const SizedBox(height: 24),
        // 一手数据流水谱 MVP 入口(《天空之城》声画同步试验,工单外
        // 临时卡;跑通后并入正式曲库结构)。
        Card(
          child: ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: const Text('天空之城 · 流水谱'),
            subtitle: const Text('一手数据试验 · 固定红线跟滚 + 示范声'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const FlowingScorePage(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        for (final category in LibraryCategory.values)
          Card(
            child: ListTile(
              leading: Icon(category.icon),
              title: Text(category.title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LibraryChartListPage(
                    category: category,
                    imagePickFlow: imagePickFlow,
                    scoreSourceImportFlow: scoreSourceImportFlow,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
