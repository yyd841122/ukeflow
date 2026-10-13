import '../model/tab_chart.dart';

/// 内置指弹曲(GLOSSARY「内置曲库」的指弹部分)的一条曲目。
class BuiltInTabChart {
  const BuiltInTabChart({required this.id, required this.chart});

  /// 曲目 id(如 `xiao-xing-xing`),测试 key 与日后引用用。
  final String id;
  final TabChart chart;
}

/// 内置指弹曲清单(ADR-0003:v1 指弹仅限内置手工录入,无文本格式、
/// 无解析导入)——「手工录入」就是在此逐音写数据,新增曲目在此登记。
///
/// 录入须知(内容纪律,与 assets/charts/README.md 同源):
/// - C 调第一把位入门指位:①0=A4 ①3=C5 ②0=E4 ②1=F4 ②3=G4
///   ③0=C4 ③2=D4;音位以对照原曲/权威谱面核对为准。
/// - [TabNote.beat] 以四分拍计,半拍 = 0.5(附点);每小节 4 拍,
///   长音只在起始拍落一个音(时值由四线谱横向位置表达,不记持续)。
/// - 录入序 = 演奏序:同拍多音按低弦→高弦(拨奏自低向高)。
TabNote _n(int string, int fret, double beat) =>
    TabNote(string: string, fret: fret, beat: beat);

/// 《小星星》(传统童谣):全四分音符 + 句尾二拍长音,一句一个手位
/// 微移,纯右手拨弦入门。C 调,12 小节。
final xiaoXingXing = TabChart(
  title: '小星星',
  artist: '传统童谣',
  tempo: 90,
  notes: [
    // 「一闪一闪亮晶晶」C5 C5 G4 G4 |「满天都是」A4 A4 G4— |「小星」
    // F4 F4 E4 E4 |「晶晶」D4 D4 C4—
    ...[_n(1, 3, 0), _n(1, 3, 1), _n(2, 3, 2), _n(2, 3, 3)],
    ...[_n(1, 0, 4), _n(1, 0, 5), _n(2, 3, 6)],
    ...[_n(2, 1, 8), _n(2, 1, 9), _n(2, 0, 10), _n(2, 0, 11)],
    ...[_n(3, 2, 12), _n(3, 2, 13), _n(3, 0, 14)],
    // 「挂在天上放光明」G4 G4 F4 F4 | E4 E4 D4— |「好像许多小眼睛」
    // G4 G4 F4 F4 | E4 E4 D4—
    ...[_n(2, 3, 16), _n(2, 3, 17), _n(2, 1, 18), _n(2, 1, 19)],
    ...[_n(2, 0, 20), _n(2, 0, 21), _n(3, 2, 22)],
    ...[_n(2, 3, 24), _n(2, 3, 25), _n(2, 1, 26), _n(2, 1, 27)],
    ...[_n(2, 0, 28), _n(2, 0, 29), _n(3, 2, 30)],
    // 尾段再现首段。
    ...[_n(1, 3, 32), _n(1, 3, 33), _n(2, 3, 34), _n(2, 3, 35)],
    ...[_n(1, 0, 36), _n(1, 0, 37), _n(2, 3, 38)],
    ...[_n(2, 1, 40), _n(2, 1, 41), _n(2, 0, 42), _n(2, 0, 43)],
    ...[_n(3, 2, 44), _n(3, 2, 45), _n(3, 0, 46)],
  ],
);

/// 《欢乐颂》(贝多芬):附点节奏(1.5 拍+半拍)进阶,全部音位与小星星
/// 同一把位。C 调,8 小节。
final huanLeSong = TabChart(
  title: '欢乐颂',
  artist: '贝多芬',
  tempo: 100,
  notes: [
    // Mi Mi Fa Sol | Sol Fa Mi Re | Do Do Re Mi | Mi. Re Re—
    ...[_n(2, 0, 0), _n(2, 0, 1), _n(2, 1, 2), _n(2, 3, 3)],
    ...[_n(2, 3, 4), _n(2, 1, 5), _n(2, 0, 6), _n(3, 2, 7)],
    ...[_n(3, 0, 8), _n(3, 0, 9), _n(3, 2, 10), _n(2, 0, 11)],
    ...[_n(2, 0, 12), _n(3, 2, 13.5), _n(3, 2, 14)],
    // Mi Mi Fa Sol | Sol Fa Mi Re | Do Do Re Mi | Re. Do Do—
    ...[_n(2, 0, 16), _n(2, 0, 17), _n(2, 1, 18), _n(2, 3, 19)],
    ...[_n(2, 3, 20), _n(2, 1, 21), _n(2, 0, 22), _n(3, 2, 23)],
    ...[_n(3, 0, 24), _n(3, 0, 25), _n(3, 2, 26), _n(2, 0, 27)],
    ...[_n(3, 2, 28), _n(3, 0, 29.5), _n(3, 0, 30)],
  ],
);

/// 内置指弹曲清单:id 与谱一一对应,新增目标曲在此登记。
/// (谱数据经录入帮助函数构造,清单为 final 而非 const——正确性由
/// [loadBuiltinTabCharts] 的加载期校验兜底。)
final builtinTabChartCatalog = <({String id, TabChart chart})>[
  (id: 'xiao-xing-xing', chart: xiaoXingXing),
  (id: 'huan-le-song', chart: huanLeSong),
];

/// 内置指弹曲加载:逐份校验,任何坏谱当场抛 [TabDataError] 并指明是
/// 哪首(与内置弹唱谱「坏内容不带病入库」同一哲学;数据是 Dart 常量,
/// 加载只需过一遍 [validateTabChart])。
List<BuiltInTabChart> loadBuiltinTabCharts() => [
  for (final entry in builtinTabChartCatalog)
    BuiltInTabChart(
      id: entry.id,
      chart: validateTabChart(entry.chart, context: entry.id),
    ),
];
