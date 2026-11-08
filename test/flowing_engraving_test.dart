import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/score/flowing_engraving.dart';
import 'package:ukeflow/core/score/reference_score.dart';

/// 排版规则回归闸:基准 = codex 对原 HTML 逐项核验值(曲谱排版优化核验
/// 报告)——115 组符杠、88 处琶音/扫弦、9 个独立符尾。任何失守先修代码,
/// 不许改基准。
void main() {
  final raw = File('assets/scores/sky-city-guistudy.json').readAsStringSync();
  late ReferenceScore score;
  late EngravingPlan plan;

  setUpAll(() {
    score = buildReferenceScore(jsonDecode(raw), pageTempoBpm: 80);
    plan = buildEngravingPlan(score);
  });

  test('符杠 115 组、琶音/扫弦 88 处(codex 原谱对照真值)', () {
    expect(plan.beams.length, 115);
    expect(plan.brushes.length, 88);
    expect(plan.brushes.where((b) => b.isArpeggio).length, 88,
        reason: '本曲扫弦直箭为 0,88 处全部是琶音波浪');
  });

  test('独立符尾 9 个(入杠之外仍带符尾的音)', () {
    final flagOnly = score.events
        .where((e) => e.notes.isNotEmpty)
        .where((e) => (plan.rhythmOf(e.id)?.flags ?? 0) > 0)
        .where((e) => !plan.beams.any((p) => p.$1 == e.id || p.$2 == e.id))
        .length;
    expect(flagOnly, 9);
  });

  test('和弦:58 处标记、11 种按法,首段 Dm 网格数据完整', () {
    final chordEvents = score.events.where((e) => e.chord != null).toList();
    expect(chordEvents.length, 58);
    expect(chordEvents.map((e) => e.chord!.name).toSet().length, 11);
    expect(chordEvents.first.chord!.strings.length, 4);
    expect(chordEvents.first.chord!.firstFret, greaterThanOrEqualTo(1));
  });

  test('休止 3 个,符形码点按四分/八分区分', () {
    final rests = score.events.where((e) => e.isRest).toList();
    expect(rests.length, 3);
    final codes = rests.map((e) => plan.rhythmOf(e.id)!.restCodePoint).toSet();
    expect(codes.length, greaterThanOrEqualTo(1));
  });

  test('延音和弦继承原位的琶音标记(画面记号,不加声音)', () {
    // codex 报告:88 处中 85 处 brushType=4,3 处为延音和弦续显。
    final inherited = plan.brushes
        .map((b) => score.events.firstWhere((e) => e.id == b.eventId))
        .where((e) => e.brushType == 0)
        .length;
    expect(inherited, 3);
  });
}
