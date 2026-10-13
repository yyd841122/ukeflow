import '../../core/audio/beat_scheduling.dart' show beatsPerBar;
import '../../core/model/tab_chart.dart';
import '../../core/practice/tab_timeline.dart' show tabTotalBeats;

/// 四线谱(指弹谱的显示形式,GLOSSARY「指弹谱」Avoid 条)几何的纯函数,
/// 与和弦图同一分工:绘制与数据一致的保证点——弦序(1 弦最上)、音的
/// 横向位置(时值→横坐标)、小节线都从这里出,CustomPainter 只做笔画。
class TabChartLayout {
  TabChartLayout(TabChart chart, {required this.pxPerBeat})
    : totalBeats = tabTotalBeats(chart),
      notes = sortedTabNotes(chart.notes);

  /// 全曲拍数(末音保有整拍、上取整到整小节线,与时间轴编译同一来源
  /// [tabTotalBeats])与对应小节数。
  final int totalBeats;

  /// 谱面逐音,按拍位升序(同拍保持录入序,与时间轴编译同序)。
  final List<TabNote> notes;

  /// 一档拍位的像素宽(缩放系数;页面给 44,半拍音位 22px 不挤)。
  final double pxPerBeat;

  /// 弦线间距与音点半径:相邻半拍音点(22px)留出间隙不粘连。
  static const lineGap = 30.0;
  static const noteRadius = 9.0;

  /// 纵向:弦号标注区(上)+ 4 弦 3 档 + 底部余白(有歌词缀字的谱在
  /// 余白处再让出一条歌词行,唱词落在最低弦线下,不与谱面重叠)。
  static const _topPad = 22.0;
  static const _bottomPad = 14.0;
  static const _lyricBand = 22.0;
  static const _heightBase = _topPad + 3 * lineGap + _bottomPad;
  static const fontSize = 14.0;

  /// 画布高:无词谱即 [_heightBase],有词谱加一条歌词带。
  double get height => hasLyrics ? _heightBase + _lyricBand : _heightBase;

  /// 歌词行的纵向中心(最低弦线之下);仅 [hasLyrics] 时有意义。
  double get lyricY => TabChartLayout.stringY(4) + _bottomPad + _lyricBand / 2;

  /// 谱内是否有歌词缀字(歌词带是否让位由此单一判定)。
  bool get hasLyrics => notes.any((n) => n.lyric != null);

  /// 横向:音区左留白(容纳音点圆)…右留白。
  static const firstPad = 16.0;
  static const rightPad = 16.0;

  /// 第 [string] 根弦(弦号 1..4)的 y:1 弦(A)最上,与外部教学材料
  /// 一致(GLOSSARY「弦号」)。纵向几何是常量(不随谱/缩放变),静态
  /// 供谱面画笔与弦号列共用同一入口。
  static double stringY(int string) => _topPad + (string - 1) * lineGap;

  /// 拍位 [beat] 的横坐标(时值→横坐标,线性比例)。
  double noteX(double beat) => firstPad + beat * pxPerBeat;

  /// 第 [bar] 小节线(0 起,含末尾收束线共 barCount+1 条)的横坐标,
  /// 与该小节头拍位的音同一 x——读谱时小节线即拍位参照。
  double barX(int bar) => noteX(bar * beatsPerBar.toDouble());

  /// 小节数(= totalBeats / beatsPerBar)。
  int get barCount => totalBeats ~/ beatsPerBar;

  /// 谱面画布宽:覆盖到末尾收束小节线,右留白收口。
  double get chartWidth => barX(barCount) + rightPad;
}
