// 组合谱面和弦锚导出(工单56):评测集构建的和弦上下文输入。
// × 展开规则需要每拍的和弦指形,单源取自 App 的 scoreSheetCatalog
// (与 dump_tab_truth.dart 同型的 dev-only 工具,不进 App)。
//
// 用法: dart run tools/dump_eval_chords.dart > /tmp/gs-aini-chords.json
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:ukeflow/core/chart/score_sheet_defs.dart';

void main() {
  final def = scoreSheetCatalog.first;
  print(jsonEncode({
    'id': def.id,
    'title': def.title,
    'key': def.keySignature,
    'chords': [
      for (final c in def.chords)
        {'beat': c.beat, 'label': c.label, 'frets': c.fingering.frets},
    ],
  }));
}
