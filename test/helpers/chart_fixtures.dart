import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/strum_chart_parser.dart';

/// 练习内核测试（工单 08）共用：谱文本 → 弹唱谱，
/// 走与产品相同的解析+校验入口。
const testAllowedChords = {'C', 'G', 'Am', 'F', 'Em', 'Dm'};

StrumChart parseChart(String source) {
  final result =
      StrumChartParser.parse(source, allowedChords: testAllowedChords);
  expect(result.ok, isTrue, reason: '测试谱必须过校验：${result.issues}');
  return result.chart!;
}
