import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/score/reference_score.dart';
import '../../../core/score/score_gate.dart';
import '../flowing_score_page.dart';
import 'health_report_view.dart';

/// 换歌体检的曲谱源装载缝(测试注入,免 rootBundle)。
final flowingGateJsonLoaderProvider =
    Provider<Future<Object> Function(String assetKey)>(
  (ref) =>
      (assetKey) async => jsonDecode(await rootBundle.loadString(assetKey)),
);

/// 换歌体检流程页(票08,ADR-0012「逐首体检」):进跟练前先体检——
/// 可练(零违例)自动进流水谱;缺规则待补/资料不够出报告,**不导入**
/// (跟练页根本不进)。体检与转换守门同源(同一趟 walk,见
/// reference_score.dart),报告只呈现结论。
///
/// 元数据接入点:[pageTempoBpm](页 BPM,07 工单的曲页元数据)从参数
/// 传入;运输链路(下载/解码)落位后同样在这里先行体检。
class FlowingScoreGatePage extends ConsumerStatefulWidget {
  const FlowingScoreGatePage({
    super.key,
    this.assetKey = 'assets/scores/sky-city-guistudy.json',
    this.pageTempoBpm = 80,
    this.autoEnter = true,
    this.selftest = false,
  });

  final String assetKey;
  final double pageTempoBpm;

  /// 可练时自动进入跟练(常规换歌动线);false = 停在报告(自检/测试)。
  final bool autoEnter;

  /// 体检自检入口(仅 debug 构建露出的坏谱样例):标题区分,永不自动进。
  final bool selftest;

  @override
  ConsumerState<FlowingScoreGatePage> createState() =>
      _FlowingScoreGatePageState();
}

class _FlowingScoreGatePageState extends ConsumerState<FlowingScoreGatePage> {
  ScoreHealthReport? _report;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final loader = ref.read(flowingGateJsonLoaderProvider);
    ScoreHealthReport report;
    try {
      final source = await loader(widget.assetKey);
      report = checkScoreHealth(source, pageTempoBpm: widget.pageTempoBpm);
    } catch (error) {
      // 装载/解码失败(资产缺失、JSON 坏)按资料不够呈现——运输链路的
      // 故障同样先过体检,不静默进跟练。
      report = ScoreHealthReport(
        verdict: ScoreHealthVerdict.insufficient,
        violations: [
          ScoreViolation(
            ruleId: 'source-unreadable',
            category: GateCategory.structure,
            message: '资料读取失败:$error',
            structural: true,
          ),
        ],
      );
    }
    if (!mounted) return;
    setState(() => _report = report);
    if (report.ok && widget.autoEnter && !widget.selftest) {
      _enterPractice();
    }
  }

  void _enterPractice() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const FlowingScorePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selftest ? '体检自检 · 坏谱样例' : '换歌体检'),
      ),
      body: report == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('体检中…', style: TextStyle(color: Color(0xFF617258))),
                ],
              ),
            )
          : ScoreHealthReportView(
              report: report,
              songLabel: widget.selftest ? '坏谱样例' : (report.title.isEmpty ? '待导入曲谱' : report.title),
              onEnterPractice:
                  report.ok && (!widget.autoEnter || widget.selftest)
                      ? _enterPractice
                      : null,
            ),
    );
  }
}
