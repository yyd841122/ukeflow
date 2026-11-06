// 识谱源校验+物化 CLI(票01,ADR-0011):矢量谱页解码器产出的 ScoreIR JSON
// 过 App 端权威校验器、物化器与谱面视图布局推导(总闸)。开发侧工具,不进 app。
//
// 用法: dart run tools/validate_score_ir.dart <scoreir.json>
// exit 0 = 校验+物化+布局推导全过;exit 1 = 阻塞错误(逐条人话打印)。
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:ukeflow/core/import/score_ir.dart';
import 'package:ukeflow/core/import/score_ir_materializer.dart';
import 'package:ukeflow/core/import/score_ir_validator.dart';
import 'package:ukeflow/core/practice/score_sheet_layout.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tools/validate_score_ir.dart <scoreir.json>');
    exit(2);
  }
  final raw = File(args.first).readAsStringSync();
  final ScoreIr ir;
  try {
    ir = ScoreIr.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } on ScoreIrFormatException catch (e) {
    stderr.writeln('✗ 源结构坏损: $e');
    exit(1);
  }
  final errors = validateScoreIr(ir);
  if (errors.isNotEmpty) {
    stderr.writeln('✗ 校验阻塞 ${errors.length} 项:');
    for (final e in errors) {
      stderr.writeln('  - $e');
    }
    exit(1);
  }
  final m = materializeScoreIr(ir);
  // 谱面视图布局推导(灰板防线):简谱推导遇变化音会抛(拒绝静默渲染),
  // 这里前置跑一遍,让这类数据在校验链就死,不进手机。
  try {
    final layout = ScoreSheetLayout(
      def: m.def,
      tabChart: m.accompaniment,
      melodyChart: m.melody,
    );
    print('✓ 谱面布局推导过:${layout.barCount} 小节入画');
  } on ArgumentError catch (e) {
    stderr.writeln('✗ 谱面布局推导阻塞: ${e.message}');
    exit(1);
  }
  print('✓ ${ir.id}「${ir.title}」校验全过,物化成功:'
      '伴奏层 ${m.accompaniment.notes.length} 音 / '
      '旋律层 ${m.melody.notes.length} 音 / '
      '和弦锚 ${m.def.chords.length} / 扫弦 ${m.def.strums.length} / '
      '小节 ${ir.measures.length},♩${ir.tempoMap.first.bpm}');
}
