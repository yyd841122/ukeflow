import 'dart:math' as math;

/// 调音器的音高数学(工单 19,spike A 迁入):频率 ↔ 音名/音分。
/// A4 基准缺省 440(全库换算常量);设置可调值(工单 20)经各入口的
/// `a4` 参数接入——目标弦取域走 UkeString.frequencyAt,检测换算走
/// [nearestNote]/[TunerFilter.push] 的 a4 参。

/// A4 基准频率 Hz(缺省常量;设置可调值的缺省锚,见 settings_providers)。
const double referenceA4 = 440.0;

/// 「已调准」判准:相对目标弦偏差 ±5 音分内(spec 用户故事 3)。
const double tunedThresholdCents = 5.0;

/// 十二平均律音名(升号拼法,与外部教学材料一致)。
const List<String> noteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// 频率 → 最近音(MIDI 编号、音名如 'A4'、相对该音的偏差音分)。
/// 等律十二平均律,midi = 69 + 12·log2(f/A4)。
({int midi, String name, double cents}) nearestNote(
  double freq, {
  double a4 = referenceA4,
}) {
  final midi = 69.0 + 12 * math.log(freq / a4) / math.ln2;
  final nearest = midi.round();
  return (
    midi: nearest,
    name: '${noteNames[nearest % 12]}${nearest ~/ 12 - 1}',
    cents: (midi - nearest) * 100,
  );
}

/// 两频率间的音分差(正 = [freq] 高于 [refFreq])。
double centsBetween(double freq, double refFreq) =>
    1200 * math.log(freq / refFreq) / math.ln2;
