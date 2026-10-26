/// 指弹谱(GLOSSARY「指弹谱」):逐音记录「哪根弦、哪个品位、何时弹响」。
///
/// 与弹唱谱([StrumChart])是**两个独立的一等公民模型**(ADR-0003):
/// 不同的数据形态(逐音事件 vs 和弦-歌词对齐)、不同的显示形式(四线谱 vs
/// 歌词滚动)、不同的播放调度(逐音拨弦 vs 按节奏型扫弦)。任何「统一成
/// 万能谱格式」的倾向都被该决策排除——本文件不 import 弹唱谱的任何类型。
///
/// v1 指弹谱仅限内置手工录入(在线搜索/导入解析被 ADR-0003 明确排除),
/// 谱数据以 Dart 常量直接入库(见 core/chart/builtin_tab_charts.dart),
/// 入库前过 [validateTabChart]——坏内容当场报错,不带病进入曲库。
library;

import 'dart:math' as math;

import 'uke_string.dart';

/// 一个音:第 [string] 弦、第 [fret] 品、第 [beat] 拍。
class TabNote {
  const TabNote({
    required this.string,
    required this.fret,
    required this.beat,
    this.lyric,
  });

  /// 弦号(GLOSSARY「弦号」):1 弦 = A(最细)…4 弦 = G(最粗),
  /// 四线谱渲染顶线为 1 弦,与外部教学材料一致。
  final int string;

  /// 品位:0 = 空弦,1..n = 第 n 品。
  final int fret;

  /// 发声时刻(自曲头,四分拍,0 起)。八分半拍 = 0.5——录入域内
  /// (0.25 的倍数)double 精确,无累计误差;编译期逐事件取整成毫秒。
  final double beat;

  /// 该音承载的歌词缀字(如「一」「闪」),null = 无词(器乐音)。
  /// 内置入门曲的新手友好显示注记:**逐音缀一个字**,不是弹唱谱的
  /// 「歌词-和弦」对齐文本(ADR-0003 两谱模型分界不动,本字段不向
  /// 弹唱谱靠拢);旋律音缀词、伴奏音留空即可表达「唱到哪」。
  final String? lyric;

  /// 该音基频(Hz)= 空弦基频 × 2^(品位/12),KS 拨弦音源直接可用。
  double get frequency =>
      UkeString.byNumber(string).frequency * math.pow(2, fret / 12);

  @override
  String toString() => '①$string ${fret == 0 ? '空弦' : '$fret 品'} @拍$beat';
}

/// 一首指弹谱。
class TabChart {
  const TabChart({
    required this.title,
    this.artist,
    required this.tempo,
    required this.notes,
  });

  /// 曲名。
  final String title;

  /// 出处(如「传统童谣」「贝多芬」),无则 null。
  final String? artist;

  /// 每分钟拍数(四分),时间轴编译的缺省速度。
  final int tempo;

  /// 逐音事件,按谱面录入顺序(消费方经 [sortedTabNotes] 取时序视图,
  /// 模型不约束)。
  final List<TabNote> notes;

  /// 展示名替换(导入独奏谱的命名合并策略,工单 43):展示名一律以
  /// 入库名为准——名字相同则原样返回(StrumChart.withTitle 同款纪律)。
  TabChart withTitle(String title) => title == this.title
      ? this
      : TabChart(title: title, artist: artist, tempo: tempo, notes: notes);
}

/// 指弹谱逐音的**时序视图**:按拍位升序,同拍保持录入序。单一来源,
/// 时间轴编译(core/practice/tab_timeline.dart)与四线谱布局
/// (features/play/tab_chart_layout.dart)共用。
///
/// 排序键是 (beat, 录入序) 复合键——Dart 的 List.sort 不保证稳定
/// (SDK 对 >32 元素走非稳定快排),「同拍保持录入序」的契约必须显式
/// 进键,不能搭 sort 实现的便车:同时拨响的音,谱面先后就是演奏指示
/// (builtin_tab_charts 录入须知:同拍多音按低弦→高弦)。
List<TabNote> sortedTabNotes(List<TabNote> notes) {
  final indexed = [for (var (i, note) in notes.indexed) (i: i, note: note)];
  indexed.sort((a, b) {
    final byBeat = a.note.beat.compareTo(b.note.beat);
    return byBeat != 0 ? byBeat : a.i.compareTo(b.i);
  });
  return [for (final entry in indexed) entry.note];
}

/// 指弹谱数据坏损:内置内容加载期当场报错(含谱名与坏音上下文),
/// 不带病进入 UI。与和弦库 [ChordDataError] 同一哲学——坏数据是缺陷
/// 不是瞬时故障,继承 Error(而非 Exception)不参与自动重试。
class TabDataError extends Error {
  TabDataError(this.message);

  final String message;

  @override
  String toString() => 'TabDataError: $message';
}

/// 内置指弹谱入库校验:弦号 1..4、品位 ≥ 0、拍位非负有限、tempo 为正、
/// 谱非空。任何一项不满足抛 [TabDataError],消息指明曲名与坏音。
/// 校验过的谱原样返回(便于 `charts = [for (...) validateTabChart(...)]`)。
TabChart validateTabChart(TabChart chart, {String context = ''}) {
  final where = context.isEmpty ? chart.title : '${chart.title}($context)';
  if (chart.notes.isEmpty) {
    throw TabDataError('指弹谱「$where」没有任何音');
  }
  if (chart.tempo <= 0) {
    throw TabDataError('指弹谱「$where」tempo 非正:${chart.tempo}');
  }
  for (final note in chart.notes) {
    if (note.string < 1 || note.string > UkeString.values.length) {
      throw TabDataError('指弹谱「$where」弦号越界(1..4):$note');
    }
    if (note.fret < 0) {
      throw TabDataError('指弹谱「$where」品位为负:$note');
    }
    if (note.beat.isNaN || note.beat.isInfinite || note.beat < 0) {
      throw TabDataError('指弹谱「$where」拍位非负有限才合法:$note');
    }
    if (note.lyric != null && note.lyric!.trim().isEmpty) {
      throw TabDataError('指弹谱「$where」歌词缀字为空白:$note');
    }
  }
  return chart;
}
