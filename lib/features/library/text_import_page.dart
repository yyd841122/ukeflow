import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chart/chart_import.dart';
import '../../core/chart/strum_chart_parser.dart';
import '../../data/chord_library.dart';
import '../../data/providers.dart';
import '../play/practice_page.dart';

/// 文本导入页（工单 16，GLOSSARY「文本导入」）：粘贴「和弦+歌词」纯文本 →
/// 自建校验（ADR-0006，宽进严出）→ 命名入库 → 立即可跟练。
///
/// 三个阶段一线走：粘贴（校验失败给出可读可定位的错误，原文一字不动、
/// 改完原地重试）→ 报告（和弦清单+段落结构过目、命名入库；曲库已有同名
/// 弹明确处置，不静默重复）→ 成功（校验报告再呈，一键直达跟练会话页）。
/// 新谱落库即随曲库流自动入列（工单 15 数据源）。
class TextImportPage extends ConsumerStatefulWidget {
  const TextImportPage({super.key});

  @override
  ConsumerState<TextImportPage> createState() => _TextImportPageState();
}

enum _Phase { paste, report, saved }

/// 同名重复导入（曲库已有同名）时对话框的三种处置。
enum _DuplicateAction { overwrite, keepBoth }

class _TextImportPageState extends ConsumerState<TextImportPage> {
  final _source = TextEditingController();
  final _title = TextEditingController();

  var _phase = _Phase.paste;

  /// 粘贴阶段的校验错误（null = 还没验过/已过）；每条已可读可定位。
  List<String>? _errors;

  /// 报告/成功阶段共用的校验报告与谱（过了校验才非 null）。
  ChartImportReport? _report;
  StrumChart? _chart;

  String? _titleError;

  /// 入库写入期间禁用存入钮（双击防抖，打卡钮同款）。
  var _saving = false;

  @override
  void dispose() {
    _source.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    setState(() {
      _errors = null;
    });
    if (_source.text.trim().isEmpty) {
      setState(() => _errors = ['先粘贴谱文本']);
      return;
    }
    final Set<String> allowedChords;
    try {
      final library = await ref.read(chordLibraryProvider.future);
      allowedChords = library.labels;
    } catch (error) {
      if (!mounted) return;
      setState(() => _errors = ['和弦库加载失败,暂时无法校验:$error']);
      return;
    }
    final result = StrumChartParser.parse(
      _source.text,
      allowedChords: allowedChords,
    );
    if (!mounted) return;
    setState(() {
      if (result.ok) {
        _chart = result.chart!;
        _report = ChartImportReport.of(result.chart!);
        // 曲名按源文本 {title} 预填;谱内无名字时留空逼用户命名。
        _title.text =
            result.chart!.title == StrumChart.untitled ? '' : result.chart!.title;
        _titleError = null;
        _phase = _Phase.report;
      } else {
        _errors = [for (final issue in result.issues) issue.message];
      }
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '先给这首谱起个名字');
      return;
    }
    setState(() {
      _titleError = null;
      _saving = true;
    });
    try {
      final dao = ref.read(customChartsDaoProvider);
      final existing = await dao.getByTitle(title);
      if (!mounted) return;
      if (existing != null) {
        final action = await _resolveDuplicate(title);
        if (!mounted || action == null) return;
        if (action == _DuplicateAction.overwrite) {
          await dao.overwrite(
            id: existing.id,
            title: title,
            source: _source.text,
          );
        } else {
          await dao.add(title: title, source: _source.text);
        }
      } else {
        await dao.add(title: title, source: _source.text);
      }
      if (!mounted) return;
      setState(() => _phase = _Phase.saved);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 曲库已有同名:弹对话框要明确处置,绝不静默重复。
  Future<_DuplicateAction?> _resolveDuplicate(String title) {
    return showDialog<_DuplicateAction>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('曲库已有同名《$title》'),
            content: const Text('覆盖原谱,还是两个都保留?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed:
                    () => Navigator.of(
                      context,
                    ).pop(_DuplicateAction.keepBoth),
                child: const Text('两个都保留'),
              ),
              FilledButton(
                onPressed:
                    () => Navigator.of(
                      context,
                    ).pop(_DuplicateAction.overwrite),
                child: const Text('覆盖原谱'),
              ),
            ],
          ),
    );
  }

  void _startPractice() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PracticePage(chart: _chart!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文本导入')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: switch (_phase) {
          _Phase.paste => _buildPaste(context),
          _Phase.report => _buildReport(context),
          _Phase.saved => _buildSaved(context),
        },
      ),
    );
  }

  Widget _buildPaste(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('import-source'),
          controller: _source,
          maxLines: 12,
          minLines: 8,
          decoration: const InputDecoration(
            hintText: '粘贴"和弦+歌词"文本,如:\n'
                '{title: 歌名}\n'
                '[C]门前大桥下游过一群鸭\n'
                '[G7]快来快来数一数',
          ),
        ),
        if (_errors != null) ...[
          const SizedBox(height: 12),
          for (final error in _errors!)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: scheme.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            '原文未动,改好再点校验',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('import-validate'),
          onPressed: _validate,
          icon: const Icon(Icons.fact_check),
          label: const Text('校验'),
        ),
      ],
    );
  }

  Widget _buildReport(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('import-title'),
          controller: _title,
          decoration: InputDecoration(
            labelText: '曲谱名',
            errorText: _titleError,
          ),
        ),
        const SizedBox(height: 16),
        _ReportPanel(report: _report!),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('import-save'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.library_add),
          label: const Text('存入曲库'),
        ),
      ],
    );
  }

  Widget _buildSaved(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.check_circle,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text('导入成功', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '已存入曲库,弹回即见',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        _ReportPanel(report: _report!),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const Key('import-practice'),
          onPressed: _startPractice,
          icon: const Icon(Icons.play_arrow),
          label: const Text('去跟练'),
        ),
      ],
    );
  }
}

/// 校验报告面板:「导入完成后展示校验报告」——和弦清单+段落结构,
/// 入库前的确认与入库后的成功页共用。
class _ReportPanel extends StatelessWidget {
  const _ReportPanel({required this.report});

  final ChartImportReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('和弦清单', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final chord in report.chords) Chip(label: Text(chord)),
          ],
        ),
        const SizedBox(height: 16),
        Text('段落结构', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final section in report.sections)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${section.title} · ${section.lineCount} 行'),
          ),
      ],
    );
  }
}
