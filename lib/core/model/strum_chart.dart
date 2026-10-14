/// 弹唱谱（GLOSSARY「弹唱谱」）：解析+校验后的曲谱模型。
///
/// 纯模型，不依赖 chord_pro——解析器语义（ADR-0006 三语义）全部封在
/// `core/chart/strum_chart_parser.dart` 里，后续工单（时间轴编译/跟练 UI）
/// 只认本文件。构造入口只有解析器：未过校验的谱文本变不成 [StrumChart]。
library;

/// 弹唱谱段落类型。
///
/// tab/grid 等逐字环境（无和弦-歌词对齐数据）与弹唱谱无关，解析时整段
/// 丢弃；其余环境归入 [other]（内容行照常保留）。
enum StrumSectionKind { verse, chorus, bridge, loose, other }

/// 弹唱谱的一个段落。
class StrumSection {
  const StrumSection({required this.kind, this.label, required this.lines});

  final StrumSectionKind kind;

  /// 段落标签（如 `{start_of_verse: Verse 1}` 的 "Verse 1"），无则 null。
  final String? label;

  /// 内容行，按谱面顺序。空行（无歌词无和弦）已在解析时丢弃。
  final List<StrumLine> lines;
}

/// 一行歌词与行内和弦标记。
class StrumLine {
  const StrumLine({required this.lyric, required this.chords});

  /// 歌词文本，逐字保留（中文紧贴和弦记号不丢字）。
  final String lyric;

  /// 行内和弦标记，按谱面出现顺序。
  final List<ChordMark> chords;
}

/// 行内一个 `[和弦]` 标记。
class ChordMark {
  const ChordMark({required this.name, required this.offset});

  /// 和弦名（谱面原样去除首尾空白）。因已过白名单校验，
  /// 该名即和弦库数据的显示名（Chord.label），可直接查指法与示范音。
  final String name;

  /// 在本行歌词文本 [StrumLine.lyric] 中的下标（0 起，UTF-16 码元；
  /// 中文歌词均在基本平面，码元即字符）。
  final int offset;
}

/// 一首弹唱谱。
///
/// 节奏型不内嵌于谱：谱是「和弦+歌词」的对齐文本，同一首谱可换节奏型练
/// （spec 用户故事 23）；弹唱谱+节奏型+BPM→动作事件时间轴的编译参数
/// 在时间轴编译器（工单 08）里。
class StrumChart {
  const StrumChart({
    required this.title,
    this.artist,
    this.key,
    this.tempo,
    required this.sections,
  });

  /// 谱内无 {title} 时的缺省名(解析层赋值)。
  /// 判断「谱内有无显式曲名」须比对本常量,不得各处自写字面串。
  static const untitled = '未命名';

  /// 歌名（`{title}`），缺省时为 [untitled]。
  final String title;
  final String? artist;

  /// 调性（`{key}`，如 "C"）。
  final String? key;

  /// 每分钟拍数（`{tempo}`），时间轴编译的默认速度。
  final int? tempo;

  final List<StrumSection> sections;

  /// 展示名替换(自建谱命名合并策略,票 16 落地):展示名一律以入库名
  /// 为准——曲库卡片与跟练会话页标题同源。名字相同则原样返回。
  StrumChart withTitle(String title) => title == this.title
      ? this
      : StrumChart(
          title: title,
          artist: artist,
          key: key,
          tempo: tempo,
          sections: sections,
        );
}
