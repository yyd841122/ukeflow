// TAB 伴奏层真值导出(工单50):builtin 金标准的 solo TAB 层逐音 + 技巧/休止
// 事件导成 JSON,供 tools/score_workbench 识别草稿做逐位 diff。开发侧一次性
// 工具,不进 app(与 dump_melody_truth.dart 同型)。
//
// 用法: dart run tools/dump_tab_truth.dart > /tmp/gs-aini-tab-gt.json
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';

void main() {
  final charts = {for (final e in builtinTabChartCatalog) e.id: e.chart};
  final def = scoreSheetCatalog.first;
  final tab = charts[def.tabChartId]!;
  print(jsonEncode({
    'id': def.id,
    'tempo': tab.tempo,
    'notes': [
      for (final n in tab.notes)
        {'beat': n.beat, 'string': n.string, 'fret': n.fret},
    ],
    'strums': [
      for (final e in def.strums) {'beat': e.beat, 'kind': e.kind.name},
    ],
    'rests': [
      for (final e in def.rests) {'beat': e.beat, 'beats': e.beats},
    ],
    'tremolos': [
      for (final e in def.tremolos) {'beat': e.beat},
    ],
    'slides': [
      for (final e in def.slides)
        {'fromBeat': e.fromBeat, 'toBeat': e.toBeat},
    ],
  }));
}
