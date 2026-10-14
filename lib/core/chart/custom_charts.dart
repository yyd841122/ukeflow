import 'strum_chart_parser.dart';

/// 自建谱(GLOSSARY「自建谱」)源文本 → 弹唱谱。
/// 存储里存的是 ChordPro 源文本(唯一真源,随解析器演进重读即得),
/// 读出必过与导入时同一的校验层——这是不信任存储的最后一道闸:
/// 坏谱当场抛错(带曲名可定位),缺陷可见,不带病进曲库页
/// (与内置谱 BuiltInCharts.load 同一哲学)。
StrumChart parseCustomChart({
  required String source,
  required String title,
  required Set<String> allowedChords,
}) {
  final result = StrumChartParser.parse(source, allowedChords: allowedChords);
  if (!result.ok) {
    throw StateError(
      '自建谱「$title」源文本未过校验,存储可能已损坏:\n'
      '${result.issues.map((i) => i.message).join('\n')}',
    );
  }
  return result.chart!;
}
