// 组合谱面真值导出(工单41):把 scoreSheetCatalog 首曲的三源数据导成 JSON,
// 供 tools/pdf_census.py 做普查-真值 diff。开发侧一次性工具,不进 app。
//
// 用法: dart run tools/dump_score_sheet_json.dart > /tmp/gs-aini-gt.json
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';

void main() {
  final charts = {for (final e in builtinTabChartCatalog) e.id: e.chart};
  final def = scoreSheetCatalog.first;
  final tab = charts[def.tabChartId]!;
  final melody = charts[def.melodyChartId]!;
  print(jsonEncode({
    'id': def.id,
    'tempo': tab.tempo,
    'notes': [
      for (final n in tab.notes)
        {'beat': n.beat, 'string': n.string, 'fret': n.fret},
    ],
    'melody': [
      for (final n in melody.notes)
        {'beat': n.beat + def.melodyAlignBeats, 'string': n.string,
          'fret': n.fret},
    ],
    'chords': [
      for (final c in def.chords) {'beat': c.beat, 'label': c.label},
    ],
    'strums': [
      for (final e in def.strums)
        {'beat': e.beat, 'kind': e.kind.name},
    ],
    'rests': [
      for (final e in def.rests) {'beat': e.beat, 'beats': e.beats},
    ],
    'tremolos': [
      for (final e in def.tremolos) {'beat': e.beat},
    ],
  }));
}
