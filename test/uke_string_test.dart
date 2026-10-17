import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/uke_string.dart';

/// UkeString:四根空弦标准 C 调定音(GLOSSARY 弦号)。
/// 期望值独立来源:等律公式 440·2^((midi-69)/12),不抄实现里的字面量。
void main() {
  test('四弦按 G C E A 排列(下标与和弦指法 frets 下标一致)', () {
    expect(UkeString.values.map((s) => s.label), ['G', 'C', 'E', 'A']);
    expect(UkeString.values.map((s) => s.number), [4, 3, 2, 1]);
  });

  test('空弦基频 = 等律理论值(±0.01Hz)', () {
    // midi:G4=67、C4=60、E4=64、A4=69。
    const midis = [67, 60, 64, 69];
    for (var i = 0; i < UkeString.values.length; i++) {
      final s = UkeString.values[i];
      final expectHz = 440.0 * math.pow(2.0, (midis[i] - 69) / 12);
      expect(s.frequency, closeTo(expectHz, 0.01), reason: '${s.label} 弦');
    }
  });

  test('frequencyAt:按给定 A4 基准换算空弦基频(工单 20 设置可调)', () {
    // 期望值独立来源:等律公式 a4·2^((midi-69)/12)。
    // 440 处与既有 frequency 常量一致是回归锚(换算不许漂移常量)。
    const midis = [67, 60, 64, 69];
    for (var i = 0; i < UkeString.values.length; i++) {
      final s = UkeString.values[i];
      expect(
        s.frequencyAt(440.0),
        closeTo(s.frequency, 0.0001),
        reason: '${s.label} 弦 A4=440 应与既有常量重合',
      );
      final expectHz = 432.0 * math.pow(2.0, (midis[i] - 69) / 12);
      expect(
        s.frequencyAt(432.0),
        closeTo(expectHz, 0.01),
        reason: '${s.label} 弦 A4=432',
      );
    }
    // 已知点抽查:432 系 G 弦 ≈ 384.87Hz(工单 20 验收示例域)。
    expect(UkeString.g.frequencyAt(432.0), closeTo(384.87, 0.01));
  });
}
