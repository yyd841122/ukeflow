import 'package:flutter/material.dart';

import '../../../core/score/score_gate.dart';

/// 换歌体检报告(票08「体检报告可见」):三态结论横幅 + 谱面概览 +
/// 支持记号清点 + 未支持记号逐项明细(类别分组,带小节号)+ 结论注记。
/// 只呈现 [ScoreHealthReport];判别规则在转换守门(同源,不在此处)。
class ScoreHealthReportView extends StatelessWidget {
  const ScoreHealthReportView({
    super.key,
    required this.report,
    required this.songLabel,
    this.onEnterPractice,
  });

  final ScoreHealthReport report;

  /// 标题行曲名(报告元数据读不到时的兜底标签)。
  final String songLabel;

  /// 仅可练且调用方要手动进入时给出(常规动线是闸门页自动进,不出现)。
  final VoidCallback? onEnterPractice;

  static const Color _glyph = Color(0xFF374D3A);
  static const Color _muted = Color(0xFF617258);
  static const Color _red = Color(0xFFC8616D);
  static const Color _amber = Color(0xFF9C6F1E);

  String _midiName(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return '${names[midi % 12]}${midi ~/ 12 - 1}';
  }

  String get _reason {
    final counts = report.categoryCounts;
    switch (report.verdict) {
      case ScoreHealthVerdict.ready:
        return '守门放行:没发现暂不支持的记号,可以进跟练。';
      case ScoreHealthVerdict.needsRules:
        final n = report.violations.length;
        final dims = counts.keys.map((c) => c.label).join('、');
        return '资料完整可信,但有 $n 处暂不支持的记号($dims)。'
            '谱子本身没问题,补上转换规则后即可练。';
      case ScoreHealthVerdict.insufficient:
        final structural = report.violations.where((v) => v.structural).length;
        return '资料本身无法可靠读取($structural 处结构问题),清点在问题处中止;'
            '该谱不能导入,请检查来源。';
    }
  }

  Color get _verdictColor => switch (report.verdict) {
        ScoreHealthVerdict.ready => _glyph,
        ScoreHealthVerdict.needsRules => _amber,
        ScoreHealthVerdict.insufficient => _red,
      };

  IconData get _verdictIcon => switch (report.verdict) {
        ScoreHealthVerdict.ready => Icons.check_circle,
        ScoreHealthVerdict.needsRules => Icons.rule,
        ScoreHealthVerdict.insufficient => Icons.report,
      };

  /// 明细行:守门消息自带「第 N 小节」前缀时去重,只留视图统一的位置
  /// 格式;结构级(无小节号)原样。
  String _violationLine(ScoreViolation v) {
    final message = v.message.replaceFirst(RegExp(r'^第 \d+ 小节'), '').trim();
    return v.measure == null ? '· $message' : '· 第 ${v.measure} 小节:$message';
  }

  @override
  Widget build(BuildContext context) {
    final tuning = report.tuning1to4;
    final overview = <(String, String)>[
      (
        '拍号',
        report.timeSignatures.isEmpty ? '—' : report.timeSignatures.join('、'),
      ),
      (
        '调弦',
        tuning == null ? '—' : tuning.map(_midiName).join(' '),
      ),
      ('变调夹', report.capo == null ? '—' : (report.capo! > 0 ? '第 ${report.capo} 品' : '无')),
      (
        '规模',
        report.measureCount == null
            ? '—'
            : '${report.measureCount} 小节'
                '${report.eventCount == null ? '' : ' · ${report.eventCount} 事件'}'
                '${report.noteCount == null ? '' : ' · ${report.noteCount} 音'}',
      ),
      (
        '曲长',
        report.durationSeconds == null
            ? '—'
            : '${(report.durationSeconds! ~/ 60)} 分 ${(report.durationSeconds! % 60).toStringAsFixed(0)} 秒',
      ),
    ];
    final violations = report.violations;
    final byCategory = <GateCategory, List<ScoreViolation>>{};
    for (final v in violations) {
      (byCategory[v.category] ??= []).add(v);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 三态结论横幅
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _verdictColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _verdictColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_verdictIcon, color: _verdictColor, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.verdict.label,
                      style: TextStyle(
                        color: _verdictColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_reason, style: const TextStyle(color: _muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 谱面概览
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '《$songLabel》谱面概览',
                    style: const TextStyle(
                        color: _glyph, fontWeight: FontWeight.w700),
                  ),
                ),
                for (final (label, value) in overview)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 64,
                          child: Text(label, style: const TextStyle(color: _muted)),
                        ),
                        Expanded(
                          child: Text(value, style: const TextStyle(color: _glyph)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        // 支持记号清点
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('记号清点(支持的都认得)',
                      style: TextStyle(color: _glyph, fontWeight: FontWeight.w700)),
                ),
                if (report.featureNotes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 3),
                    child: Text('无扫弦/泛音/延音等记号', style: TextStyle(color: _muted)),
                  )
                else
                  for (final note in report.featureNotes)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text('· $note', style: const TextStyle(color: _glyph)),
                    ),
              ],
            ),
          ),
        ),
        // 未支持记号明细
        if (violations.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '未支持记号(${violations.length} 处)',
                      style: TextStyle(
                          color: _verdictColor, fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final entry in byCategory.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2),
                      child: Text(
                        '${entry.key.label} · ${entry.value.length} 处',
                        style: const TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ),
                    for (final v in entry.value)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          _violationLine(v),
                          style: const TextStyle(color: _glyph),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        // 结论注记
        if (!report.ok)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              report.verdict == ScoreHealthVerdict.needsRules
                  ? '按换歌纪律,该谱未导入;缺的规则补上后重新体检即可。'
                  : '按换歌纪律,该谱未导入;请先修复资料来源。',
              style: const TextStyle(color: _muted),
              textAlign: TextAlign.center,
            ),
          ),
        if (onEnterPractice != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: FilledButton(
              onPressed: onEnterPractice,
              child: const Text('进入跟练'),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
