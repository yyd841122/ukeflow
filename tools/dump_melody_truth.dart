// 简谱旋律层真值导出(工单49):builtin 金标准的 melody 层逐音导成 JSON,
// 供 tools/score_workbench 识别草稿做逐位 diff。开发侧一次性工具,不进 app。
//
// 用法: dart run tools/dump_melody_truth.dart > /tmp/gs-aini-melody-gt.json
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:ukeflow/core/chart/builtin_tab_charts.dart';
import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/model/uke_string.dart';

void main() {
  final charts = {for (final e in builtinTabChartCatalog) e.id: e.chart};
  final def = scoreSheetCatalog.first;
  final melody = charts[def.melodyChartId]!;
  print(jsonEncode({
    'id': def.id,
    'melodyAlignBeats': def.melodyAlignBeats,
    'tempo': melody.tempo,
    'notes': [
      for (final n in melody.notes)
        {
          'beat': n.beat,
          'string': n.string,
          'fret': n.fret,
          'midi': UkeString.byNumber(n.string).midi + n.fret,
          if (n.lyric != null) 'lyric': n.lyric,
        },
    ],
  }));
}
