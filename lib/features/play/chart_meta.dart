import '../../core/model/strum_chart.dart';

/// 谱面元信息行(GLOSSARY「弹唱谱」):「artist · C 调 · 80 BPM」,
/// 有的才显示;曲库卡片与跟练空闲面板共用,一字不差。
String? chartMetaLine(StrumChart chart) {
  final parts = [
    if (chart.artist != null) chart.artist!,
    if (chart.key != null) '${chart.key} 调',
    if (chart.tempo != null) '${chart.tempo} BPM',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
