// 跨语言总闸(工单51 retro):校对台(tools/score_workbench)导出的识谱源
// JSON 必须被 App 端真解析——fromJson + 校验为空 + 物化出双声部谱。此前
// 「Python 导出 ↔ Dart 解析」契约只有肉眼核对,导出端键名/形状漂移要等
// 用户导入时才炸。fixture 由 tests/test_proof.py::build_gate_ir 经校对台
// 全流程(preflight 全绿)导出;pytest 漂移闸
// (test_export_fixture_matches_dart_gate)钉住两端不漂——本测试红 =
// 工作台导出与 Dart 契约裂了,不是 Dart 代码坏了。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/import/score_ir.dart';
import 'package:ukeflow/core/import/score_ir_materializer.dart';
import 'package:ukeflow/core/import/score_ir_validator.dart';

void main() {
  final ir = ScoreIr.fromJson(
    jsonDecode(File('test/fixtures/score_ir/workbench_export_sample.json')
        .readAsStringSync()) as Map<String, dynamic>,
  );

  test('工作台导出样张:fromJson 后校验为空(两端契约对齐)', () {
    expect(validateScoreIr(ir), isEmpty);
    expect(ir.id, 'workbench-sample');
    expect(ir.tempoMap.single.bpm, 78);
  });

  test('工作台导出样张:物化出双声部谱+组合定义(事件表 1:1 落)', () {
    final m = materializeScoreIr(ir);
    expect(m.melody.notes, isNotEmpty);
    expect(m.accompaniment.notes, isNotEmpty);
    expect(m.def.title, ir.title);
    expect(m.def.chords, isNotEmpty);       // chordAnchors 1:1
    expect(m.def.strums, isNotEmpty);       // strums 1:1
    expect(m.def.rests, isNotEmpty);        // 显示休止 1:1
    expect(m.def.slides, isNotEmpty);       // slides 1:1
    expect(m.def.tremolos, isNotEmpty);     // tremolos 1:1
  });
}
