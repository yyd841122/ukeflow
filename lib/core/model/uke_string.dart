/// 四根空弦(标准 C 调定音,GLOSSARY「弦号」)。
///
/// 枚举序 = 弹奏位次序 4 弦→1 弦(下标与和弦指法 `frets` 下标一致);
/// [frequency] 为 A4=440 基准的等律十二平均律值(全库常量基准),
/// 可调 A4 基准(工单 20 设置)经 [frequencyAt] 换算,调音器目标/试音消费。
library;

import 'dart:math' as math;

enum UkeString {
  g(4, 'G', 67, 391.99543598174927),
  c(3, 'C', 60, 261.6255653005986),
  e(2, 'E', 64, 329.62755691246664),
  a(1, 'A', 69, 440.0);

  const UkeString(this.number, this.label, this.midi, this.frequency);

  /// 弦号:1 弦 = A(最细)、2 = E、3 = C、4 = G(最粗)。
  final int number;

  /// 音名。
  final String label;

  /// MIDI 编号(高音 G:G4=67、C4=60、E4=64、A4=69;换算的唯一域事实)。
  final int midi;

  /// 空弦基频 Hz(A4=440 基准常量;其他基准走 [frequencyAt])。
  final double frequency;

  /// 以给定 A4 基准换算的空弦基频 Hz:等律 a4·2^((midi-69)/12)。
  /// A4=440 时与 [frequency] 常量重合(测试锚定)。
  double frequencyAt(double a4) => a4 * math.pow(2, (midi - 69) / 12);

  /// 弦号 → 弦(GLOSSARY「弦号」:1 = A…4 = G)。指弹谱逐音事件与
  /// 四线谱渲染按弦号取弦共用此查取;越界抛 StateError(坏数据当场炸)。
  static UkeString byNumber(int number) =>
      values.firstWhere((s) => s.number == number);
}
