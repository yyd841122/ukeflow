import '../../core/model/strum_chart.dart';
import '../../core/model/tab_chart.dart';

/// 谱面元信息行(GLOSSARY「弹唱谱」):「artist · C 调 · 80 BPM」,
/// 有的才显示;曲库卡片与跟练空闲面板共用,一字不差。
/// 空白字段(解析出空串的 {artist: } 等)剔除,不产孤立分隔符。
String? chartMetaLine(StrumChart chart) {
  final artist = chart.artist?.trim() ?? '';
  final key = chart.key?.trim() ?? '';
  final parts = [
    if (artist.isNotEmpty) artist,
    if (key.isNotEmpty) '$key 调',
    if (chart.tempo != null) '${chart.tempo} BPM',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// 指弹谱元信息行:「指弹 · artist · 90 BPM」(曲库卡片与指弹谱页共用);
/// artist 缺省时以「指弹 · 90 BPM」起步,不产孤立分隔符。
String tabChartMetaLine(TabChart chart) {
  final artist = chart.artist?.trim() ?? '';
  return [
    '指弹',
    if (artist.isNotEmpty) artist,
    '${chart.tempo} BPM',
  ].join(' · ');
}
