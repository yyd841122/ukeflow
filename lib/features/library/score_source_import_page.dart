import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../play/score_sheet_view.dart';
import 'score_source_import_flow.dart';

/// 识谱源导入预览页(工单 44):试物化三源出谱面视图横带(ScoreStripView
/// 静态读谱态,横向可拖)+ 命名 + 确认入库。命名纪律同自建谱:展示名
/// 一律以入库名为准,读出物化时统一覆盖源内曲名(组合定义与两层谱题
/// 同源覆盖,曲库卡片与谱面页不出现两个名字)。
class ImportScoreSourcePage extends ConsumerStatefulWidget {
  const ImportScoreSourcePage({super.key, required this.ready});

  /// 流程验检通过的待确认识谱源(合法源,物化三件套在手)。
  final ScoreSourceReady ready;

  @override
  ConsumerState<ImportScoreSourcePage> createState() =>
      _ImportScoreSourcePageState();
}

class _ImportScoreSourcePageState extends ConsumerState<ImportScoreSourcePage> {
  late final _title = TextEditingController(
    text: widget.ready.suggestedTitle ?? widget.ready.ir.title,
  );
  String? _titleError;

  /// 入库写入期间禁用存入钮(双击防抖,文本导入同款)。
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '先给这首谱起个名字');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(importedSoloChartsDaoProvider)
          .add(
            title: title,
            sourceJson: widget.ready.sourceJson,
            schemaVersion: widget.ready.ir.schemaVersion,
            reviewedAt: widget.ready.ir.review?.reviewedAt,
          );
    } on Object catch (error) {
      debugPrint('UkeFlow: 识谱源入库失败 $error');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没存进曲库——请再试一次')));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('「$title」已存入曲库')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.ready.materialization;
    return Scaffold(
      appBar: AppBar(title: const Text('预览导入谱')),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                '识谱源 · ${m.def.subtitleLine(m.accompaniment)}',
                key: const Key('import-score-meta'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            // 预览横带:与谱面视图页同一渲染(静态读谱态),用户手动拖。
            Expanded(
              child: ScoreStripView(
                def: m.def,
                tabChart: m.accompaniment,
                melodyChart: m.melody,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('import-score-title'),
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: '曲谱名',
                      hintText: '入库名即展示名,可改',
                    ).copyWith(errorText: _titleError),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('import-score-save'),
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.library_add),
                    label: const Text('存入曲库'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
