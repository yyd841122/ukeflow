import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/scoring/report.dart';
import '../../../core/scoring/strum_scorer.dart';
import '../../../data/settings_providers.dart';
import 'practice_scoring_controller.dart';

/// 跟练评分报告页(GLOSSARY「跟练评分」):全曲报告,看完即弃不落库。
///
/// 版式(数据全来自 [practiceScoringProvider] 的报告,页内无计算状态):
/// - 头部:准确率大字 + 五判定计数;
/// - 延迟校准(GLOSSARY):倾向提示(meanSignedError 指方向)+ ±200ms
///   10ms 一档滑块(拖动实时重算)+ 保存(跨会话生效);
/// - 最差三处;小节聚合条;行聚合;扫弦点轨道(按判定着色,点格重听)。
class ScoringReportPage extends ConsumerWidget {
  const ScoringReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(practiceScoringProvider);
    final report = state.report;
    return PopScope(
      // 看完即弃:离开报告即弃数据(控制器回 idle,报告对象随状态清空)。
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ref.read(practiceScoringProvider.notifier).closeReport();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('跟练评分报告')),
        body: report == null
            ? const Center(child: Text('没有可显示的报告'))
            : _ReportBody(report: report),
      ),
    );
  }
}

class _ReportBody extends ConsumerStatefulWidget {
  const _ReportBody({required this.report});

  final ScoringReport report;

  @override
  ConsumerState<_ReportBody> createState() => _ReportBodyState();
}

class _ReportBodyState extends ConsumerState<_ReportBody> {
  /// 点格选中的轨道序号(详情行与重听目标)。
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final state = ref.watch(practiceScoringProvider);
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _Header(report: report),
        const SizedBox(height: 16),
        _LatencyCard(report: report, latencySec: state.reportLatencySec ?? 0),
        const SizedBox(height: 16),
        _SectionTitle('最差三处', scheme),
        _WorstList(report: report),
        const SizedBox(height: 16),
        _SectionTitle('小节准确率', scheme),
        _BarStrip(report: report),
        const SizedBox(height: 16),
        _SectionTitle('分行准确率', scheme),
        _LineList(report: report),
        const SizedBox(height: 16),
        _SectionTitle('扫弦点轨道(点格重听)', scheme),
        const SizedBox(height: 8),
        _StrumTrack(
          report: report,
          selected: _selected,
          onTap: (index) {
            setState(() => _selected = index);
            ref.read(practiceScoringProvider.notifier).replay(index);
          },
        ),
        if (_selected case final index? when index < report.spots.length)
          _SpotDetail(report.spots[index]),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.scheme);

  final String text;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
  );
}

/// 判定 → 颜色(报告全套着色的单一来源)。
Color judgmentColor(BuildContext context, StrumJudgment judgment) {
  final scheme = Theme.of(context).colorScheme;
  return switch (judgment) {
    StrumJudgment.onTime => scheme.primary,
    StrumJudgment.early || StrumJudgment.late => scheme.tertiary,
    StrumJudgment.wrong => scheme.secondary,
    StrumJudgment.missed => scheme.error,
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.report});

  final ScoringReport report;

  @override
  Widget build(BuildContext context) {
    final result = report.result;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          result.total == 0 ? '—' : '${(result.accuracy * 100).round()}%',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
        Text(
          '准确率 · 共 ${result.total} 下'
          '(准 ${result.onTime} · 早 ${result.early} · 晚 ${result.late} · '
          '漏 ${result.missed} · 错 ${result.wrong})',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _LatencyCard extends ConsumerWidget {
  const _LatencyCard({required this.report, required this.latencySec});

  final ScoringReport report;

  /// 当前延迟(秒):控制器的报告重算值,滑块的值源。
  final double latencySec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(practiceScoringProvider.notifier);
    final ms = report.result.meanSignedErrorSec * 1000;
    final String hint;
    if (report.result.total == 0) {
      hint = '没记到该扫的点。';
    } else if (ms < -30) {
      hint = '整体偏早 ${ms.abs().round()}ms → 把延迟调小一点(或你有点抢拍)。';
    } else if (ms > 30) {
      hint = '整体偏晚 ${ms.round()}ms → 把延迟调大一点(或你有点拖拍)。';
    } else {
      hint = '早晚挺均衡。';
    }
    final currentMs = (latencySec * 1000).round();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hint, style: Theme.of(context).textTheme.bodySmall),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    key: const Key('latency-slider'),
                    min: minScoringLatencyMs.toDouble(),
                    max: maxScoringLatencyMs.toDouble(),
                    divisions:
                        (maxScoringLatencyMs - minScoringLatencyMs) ~/ 10,
                    value: currentMs.toDouble().clamp(
                      minScoringLatencyMs.toDouble(),
                      maxScoringLatencyMs.toDouble(),
                    ),
                    label: '${currentMs}ms',
                    onChanged: (v) => controller.setReportLatencySec(v / 1000),
                  ),
                ),
                Text('${currentMs}ms'),
                TextButton(
                  key: const Key('latency-save'),
                  onPressed: controller.saveReportLatency,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorstList extends StatelessWidget {
  const _WorstList({required this.report});

  final ScoringReport report;

  @override
  Widget build(BuildContext context) {
    final worst = worstSpots(report, count: 3);
    if (worst.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('全准,没有可举的短板。'),
      );
    }
    return Column(
      children: [
        for (final spot in worst)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.flag,
              color: judgmentColor(context, spot.judgment),
            ),
            title: Text(_spotLabel(spot)),
            trailing: Text(_judgmentLabel(spot)),
          ),
      ],
    );
  }
}

String _spotLabel(StrumSpot spot) {
  final chord = spot.chord ?? '—';
  final error = spot.judgment == StrumJudgment.missed
      ? ''
      : ' ${spot.errorSec >= 0 ? '+' : ''}${(spot.errorSec * 1000).round()}ms';
  return '第 ${spot.barIndex + 1} 小节 ${_beatInBar(spot)} 拍 · $chord$error';
}

String _beatInBar(StrumSpot spot) => '${spot.slotInBar ~/ 2 + 1}';

String _judgmentLabel(StrumSpot spot) => switch (spot.judgment) {
  StrumJudgment.onTime => '准',
  StrumJudgment.early => '早',
  StrumJudgment.late => '晚',
  StrumJudgment.wrong => '错',
  StrumJudgment.missed => '漏',
};

class _BarStrip extends StatelessWidget {
  const _BarStrip({required this.report});

  final ScoringReport report;

  @override
  Widget build(BuildContext context) {
    final byBar = accuracyByBar(report);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final bar in byBar)
          Chip(
            avatar: Icon(
              Icons.circle,
              size: 14,
              color: (bar.matched / bar.total) >= 0.9
                  ? Theme.of(context).colorScheme.primary
                  : (bar.matched / bar.total) >= 0.5
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.error,
            ),
            label: Text(
              '${bar.bar + 1}:${bar.matched}/${bar.total}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
      ],
    );
  }
}

class _LineList extends StatelessWidget {
  const _LineList({required this.report});

  final ScoringReport report;

  @override
  Widget build(BuildContext context) {
    final byLine = accuracyByLine(report);
    return Column(
      children: [
        for (final line in byLine)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    '段${line.sectionIndex + 1} 行${line.lineIndex + 1}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: line.total == 0 ? 0 : line.matched / line.total,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${line.matched}/${line.total}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StrumTrack extends StatelessWidget {
  const _StrumTrack({
    required this.report,
    required this.selected,
    required this.onTap,
  });

  final ScoringReport report;
  final int? selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final spot in report.spots)
          InkWell(
            key: Key('strum-cell-${spot.spotIndex}'),
            onTap: () => onTap(spot.spotIndex),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 34,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: judgmentColor(
                  context,
                  spot.judgment,
                ).withValues(alpha: selected == spot.spotIndex ? 0.55 : 0.22),
                border: Border.all(
                  color: judgmentColor(context, spot.judgment),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _judgmentLabel(spot),
                style: TextStyle(
                  fontSize: 12,
                  color: judgmentColor(context, spot.judgment),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SpotDetail extends StatelessWidget {
  const _SpotDetail(this.spot);

  final StrumSpot spot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        '${_spotLabel(spot)} · 判定:${_judgmentLabel(spot)}(已重听该声)',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
