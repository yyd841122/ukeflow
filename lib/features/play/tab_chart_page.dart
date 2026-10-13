import 'package:flutter/material.dart';

import '../../core/model/tab_chart.dart';
import 'chart_meta.dart';
import 'tab_chart_view.dart';

/// 指弹谱页(工单 12「能看」):曲名+元信息+四线谱静态读谱视图。
/// 逐音跟练(高亮/示范声/变速/数拍)归工单 13,届时本页升级为会话页。
class TabChartPage extends StatelessWidget {
  const TabChartPage({super.key, required this.chart});

  final TabChart chart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(chart.title)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                tabChartMetaLine(chart),
                key: const Key('tab-meta'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TabChartView(chart: chart),
            ),
          ],
        ),
      ),
    );
  }
}
