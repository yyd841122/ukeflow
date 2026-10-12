/// 四根空弦(标准 C 调定音,GLOSSARY「弦号」)。
///
/// 枚举序 = 弹奏位次序 4 弦→1 弦(下标与和弦指法 `frets` 下标一致);
/// 基频为等律十二平均律值(A4=440),调音器与试音共用。
library;

enum UkeString {
  g(4, 'G', 391.99543598174927),
  c(3, 'C', 261.6255653005986),
  e(2, 'E', 329.62755691246664),
  a(1, 'A', 440.0);

  const UkeString(this.number, this.label, this.frequency);

  /// 弦号:1 弦 = A(最细)、2 = E、3 = C、4 = G(最粗)。
  final int number;

  /// 音名。
  final String label;

  /// 空弦基频 Hz。
  final double frequency;
}
