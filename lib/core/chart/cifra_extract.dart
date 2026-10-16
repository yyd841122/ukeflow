/// Cifra Club 搜索源导入(工单 17)的核心缝:WebView 内 JS 提取的行结构
/// → ChordPro 文本谱。一切提取只在 WebView 里发生(ADR-0002/调研结论:
/// 站点 Akamai 反爬,禁止服务端直连),本文件只管「取到之后」的纯转换。
library;

import 'dart:convert';

/// JS 提取产物里的一段:歌词/排版纯文本,或一个和弦记号。
sealed class CifraSeg {
  const CifraSeg();
}

/// 纯文本段(歌词行内容、和弦行里和弦之间的空隙与记号)。
class CifraTextSeg extends CifraSeg {
  const CifraTextSeg(this.text);

  final String text;
}

/// 和弦段:[name] 为和弦名(data-chord-name 优先),[raw] 为该元素在页面
/// 上的原始文本(含对齐空格),[column] 为行内列位(前面各段原始长度累计,
/// 解码时算好)。
class CifraChordSeg extends CifraSeg {
  const CifraChordSeg({
    required this.name,
    required this.raw,
    required this.column,
  });

  final String name;
  final String raw;
  final int column;
}

/// 一首曲谱页的提取结果:元数据 + 逐行片段
/// (pre 里每个视觉行一条,顺序即页面顺序)。
class CifraPayload {
  const CifraPayload({
    required this.title,
    required this.artist,
    required this.lines,
  });

  final String? title;
  final String? artist;
  final List<List<CifraSeg>> lines;
}

/// 桥返回值解码公共前导:字符串先解 JSON,Android 桥对字符串返回值再包
/// 一层 JSON 引号就再剥一层;非 Map 形状返回 null(调用方各自处置)。
Map? _decodeBridgeValue(Object? input) {
  Object? value = input;
  if (value is String) {
    try {
      value = jsonDecode(value);
    } catch (_) {
      return null;
    }
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return null;
      }
    }
  }
  return value is Map ? value : null;
}

/// JS 返回值 → [CifraPayload]。容错纪律:页面结构变化/脚本被拦时
/// 返回 null(上层给可读失败态),绝不抛异常。
/// [input] 接受已解码的 Map,或 JSON 字符串(Android 桥可能给返回值
/// 再包一层 JSON 引号,剥两层都试)。
CifraPayload? decodeCifraPayload(Object? input) {
  final value = _decodeBridgeValue(input);
  if (value == null) return null;
  final rawLines = value['lines'];
  if (rawLines is! List) return null;
  final lines = <List<CifraSeg>>[];
  for (final rawLine in rawLines) {
    if (rawLine is! List) return null;
    final segs = <CifraSeg>[];
    var rawSoFar = 0;
    for (final rawSeg in rawLine) {
      switch (rawSeg) {
        case String text:
          segs.add(CifraTextSeg(text));
          rawSoFar += text.length;
        case {'c': String name, 's': String raw}:
          segs.add(CifraChordSeg(name: name, raw: raw, column: rawSoFar));
          rawSoFar += raw.length;
        default:
          return null; // 认不得的段:整体拒绝,宁可报「提取失败」不猜。
      }
    }
    lines.add(List.unmodifiable(segs));
  }
  return CifraPayload(
    title: value['title'] is String ? value['title'] as String : null,
    artist: value['artist'] is String ? value['artist'] as String : null,
    lines: List.unmodifiable(lines),
  );
}

/// 提取失败码:JS 侧返回 `{error: <code>}`(页面结构变化/拦截/没和弦)
/// 时给出代码字符串,供上层映射可读文案;不是失败形状则 null。
String? cifraExtractError(Object? input) {
  final value = _decodeBridgeValue(input);
  if (value == null) return null;
  final error = value['error'];
  return error is String ? error : null;
}

/// JS 提取产物 → ChordPro 文本谱(可直接喂 StrumChartParser 同一校验层)。
///
/// 转换规则(工单 16 机检 Python 原型实证、票 26 立票载明的语义):
/// ① 悬空和弦行的首和弦吸到歌词行首——原谱缩进只是排版习惯;
/// ② 行中和弦落在单词中间时回退词首。
/// 同音异名归一:和弦库根音只有降号拼法,谱面 D#/G# 类升号写法白名单
/// 不收时映射到降号同音(Eb/Ab),否则保留原写法交校验报错。
/// 段落标记行([Chorus]/[Refrão] 等)翻译为 start_of/end_of 指令对,
/// 识别不了的落 custom 段(标签保留)。连续多条悬空和弦行(站点双记谱
/// 行,如「原调+capo」两行)只取第一条配歌词,其余丢弃。
String buildChordPro(
  CifraPayload payload, {
  required Set<String> allowedChords,
}) {
  final out = StringBuffer();
  if (payload.title != null && payload.title!.trim().isNotEmpty) {
    out.writeln('{title: ${_directiveArg(payload.title!.trim())}}');
  }
  if (payload.artist != null && payload.artist!.trim().isNotEmpty) {
    out.writeln('{artist: ${_directiveArg(payload.artist!.trim())}}');
  }

  String? openSection;
  void closeSection() {
    if (openSection != null) {
      out.writeln('{end_of_$openSection}');
      openSection = null;
    }
  }

  /// 悬空和弦行攒列:连续和弦行先攒着,等歌词行来配对——首条配对、
  /// 其余按站点双记谱(原调+capo)丢弃;等不到歌词(空行/段落标记/谱尾)
  /// 时**全部**独立落盘——纯器乐进行(C-G/Am-F 相邻两行)不丢行
  /// (审计 2026-10-16 #12)。
  final hanging = <_ChordLine>[];

  /// 站点「[Tab - X]」段 = 吉他六线谱(真机实证),对尤克里里跟练是
  /// 纯噪声——进入这类段后所有行丢弃,直到下一个非 Tab 标记。
  var skippingTabSection = false;

  void flushHangingStandalone() {
    for (final line in hanging) {
      final names = [
        for (final seg in line.chords) _normalizeChord(seg.name, allowedChords),
      ];
      out.writeln('[${names.join('] [')}]');
    }
    hanging.clear();
  }

  for (final line in _classifyLines(payload.lines)) {
    switch (line) {
      case _BlankLine():
        if (skippingTabSection) break;
        flushHangingStandalone(); // 空行断开配对:悬空行就地独立落盘。
      case _MarkerLine(:final slug, :final label):
        flushHangingStandalone();
        closeSection();
        if (slug.startsWith('tab')) {
          skippingTabSection = true; // 六线谱段整段丢弃,不开指令对。
          break;
        }
        skippingTabSection = false;
        openSection = slug;
        out.writeln('{start_of_$slug: ${_directiveArg(label)}}');
      case _ChordLine():
        if (skippingTabSection) break;
        hanging.add(line);
      case _LyricLine():
        if (skippingTabSection) break;
        // 站点双记谱的 capo 行渲染为纯文本(无 b 元素):紧跟悬空和弦行、
        // 内容大半是和弦样的行是二记谱行,丢弃——真歌词不在这;悬空列
        // 原样保留,等下一个真歌词行配对。
        if (hanging.isNotEmpty && line.chordalish) {
          break;
        }
        final host = hanging.isEmpty ? null : hanging.first;
        hanging.clear(); // 首条配歌词,其余(双记谱)按既有语义丢弃。
        final marks = host == null
            ? <(int, String)>[]
            : line.pairedMarks(host, allowedChords: allowedChords);
        out.writeln(_interleave(line.lyricText, marks));
      case _MixedLine():
        if (skippingTabSection) break;
        flushHangingStandalone();
        out.writeln(_interleave(line.lyricText, line.exactMarks(allowedChords)));
    }
  }
  flushHangingStandalone();
  closeSection();
  return out.toString();
}

/// 文本进歌词行:ChordPro 行内特殊字符转义——chord_pro 内联词法在
/// TextToken 里解 `\[ \] \{ \} \\`,转义可往返:「Song {Live}」不再碎成
/// 杂指令、「Love [forever]」不再被当未知和弦拦(审计 2026-10-16 #11)。
String _escapeLyricText(String text) => text
    .replaceAll(r'\', r'\\')
    .replaceAll('[', r'\[')
    .replaceAll(']', r'\]')
    .replaceAll('{', r'\{')
    .replaceAll('}', r'\}');

/// 文本进指令参数(标题/艺人/段落标签)。chord_pro 的指令值是「raw
/// 文本到首个 } 为止」(不解引号、不解转义),花括号在值内无法无损
/// 编码——剥除(内容保留:「Song {Live}」→「Song Live」),反斜杠
/// 一并剥(它是行内转义符,留在值里只会以字面出现)。剥除是结构降噪:
/// 不剥则值被首个 } 截断、尾巴漏成杂歌词(审计 2026-10-16 #11)。
String _directiveArg(String text) => text.replaceAll(RegExp(r'[{}\\]'), '');

/// 行内化:把 (列位, 和弦名) 记号按列位织进歌词(同列位保持和弦先后,
/// 紧邻书写;dart List.sort 非稳定,以数组序为次键)。歌词侧文本经
/// [_escapeLyricText] 转义。
String _interleave(String lyric, List<(int, String)> marks) {
  final order = List.generate(marks.length, (i) => i);
  order.sort((a, b) {
    final cmp = marks[a].$1.compareTo(marks[b].$1);
    return cmp != 0 ? cmp : a.compareTo(b);
  });
  final buf = StringBuffer();
  var last = 0;
  for (final i in order) {
    final (pos, name) = marks[i];
    final p = pos.clamp(0, lyric.length);
    buf.write(_escapeLyricText(lyric.substring(last, p)));
    buf.write('[$name]');
    last = p;
  }
  buf.write(_escapeLyricText(lyric.substring(last)));
  return buf.toString();
}

/// 同音异名归一(只动根音/低音的升降号拼写,quality 一字不动)。
String _normalizeChord(String name, Set<String> allowedChords) {
  final cleaned = name.trim().replaceAll('♯', '#').replaceAll('♭', 'b');
  if (allowedChords.contains(cleaned)) return cleaned;
  // 候选按序:原样 / 升转降 / 巴西记谱 / 升转降+巴西记谱。
  // 每个候选都必须命中白名单才采用——映射永不引入库里没有的和弦。
  final parts = cleaned.split('/');
  final candidates = [
    parts.join('/'),
    parts.map(_mapPartToFlat).join('/'),
    parts.map(_brazilianQuality).join('/'),
    parts.map((p) => _brazilianQuality(_mapPartToFlat(p))).join('/'),
  ];
  for (final candidate in candidates) {
    if (allowedChords.contains(candidate)) return candidate;
  }
  return cleaned;
}

final RegExp _chordPartRe = RegExp(r'^([A-G])([#b]?)(.*)$');

/// 巴西记谱 → 和弦库标准后缀(真站形态:7M=maj7、(9) 顶替七=m9/9/maj9、
/// X4=sus4、(b5) 类升降扩展直接拼接)。只动 quality,根音不动;
/// 结果是否可用由白名单把关(见 _normalizeChord)。
String _brazilianQuality(String part) {
  final m = _chordPartRe.firstMatch(part);
  if (m == null) return part;
  final rootAcc = '${m.group(1)}${m.group(2) ?? ''}';
  var quality = (m.group(3) ?? '').replaceAll('7M', 'maj7');
  final paren = RegExp(r'\((b|##|#)?(\d+)\)$').firstMatch(quality);
  if (paren != null) {
    final accidental = paren.group(1) ?? '';
    final number = paren.group(2)!;
    final base = quality.substring(0, paren.start);
    if (accidental.isEmpty && (number == '9' || number == '11' || number == '13')) {
      // 7(9)/m7(9)/maj7(9):扩展数字顶替七和弦的「7」→ 9/m9/maj9。
      final stem = base == 'maj7'
          ? 'maj'
          : base.endsWith('7')
          ? base.substring(0, base.length - 1)
          : base;
      quality = '$stem$number';
    } else if (accidental.isEmpty && number == '4') {
      quality = base.endsWith('7') ? '${base}sus4' : 'sus4'; // 7(4)/X(4)
    } else {
      quality = '$base$accidental$number'; // m7(b5)→m7b5、7(b9)→7b9 类。
    }
  } else if (quality == '4') {
    quality = 'sus4'; // 巴西 G4 = Gsus4。
  }
  return '$rootAcc$quality';
}

/// C#→Db D#→Eb F#→Gb G#→Ab A#→Bb;E#/B#→F/C。升号不在白名单才走到这,
/// 降号拼法/无记号原样返回。
String _mapPartToFlat(String part) {
  final m = _chordPartRe.firstMatch(part);
  if (m == null || m.group(2) != '#') return part;
  const letterToFlat = {
    'C': 'Db',
    'D': 'Eb',
    'F': 'Gb',
    'G': 'Ab',
    'A': 'Bb',
    'E': 'F',
    'B': 'C',
  };
  return '${letterToFlat[m.group(1)!]}${m.group(3)}';
}

// ---------------------------------------------------------------------------
// 行分类:预内容里的一行分五类
// (空行/段落标记行/悬空和弦行/纯歌词行/混排行),分类只看本行。
// ---------------------------------------------------------------------------

/// 行首标记前缀:真站(2026-10-14 真机机检,Let It Be 页)把
/// 「[Intro] C G」「[Solo] …」的标记与和弦放同一行——不剥的话标记文本
/// 混进歌词,校验层把 [Intro] 当和弦记号拦下。
final RegExp _leadingMarkerRe = RegExp(r'^\s*\[([^\[\]]+)\]\s*');

/// 行分类入口:行首带标记前缀的行拆成「标记行 + 剩余行」两条
/// (剩余行的和弦列位前移),其余原样单行分类。
List<_CifraLine> _classifyLines(List<List<CifraSeg>> lines) {
  final out = <_CifraLine>[];
  for (final segs in lines) {
    final text = [
      for (final seg in segs)
        if (seg is CifraTextSeg) seg.text,
    ].join();
    final leading = _leadingMarkerRe.firstMatch(text);
    if (leading == null) {
      out.add(_CifraLine.of(segs));
      continue;
    }
    final label = leading.group(1)!.trim();
    out.add(_MarkerLine(slug: _markerSlug(label), label: _cleanLabel(label)));
    out.add(_CifraLine.of(_stripLeadingText(segs, leading.end)));
  }
  return out;
}

/// 把行内文本剥掉前 [charCount] 个字符(和弦段列位同步前移)。
List<CifraSeg> _stripLeadingText(List<CifraSeg> segs, int charCount) {
  final stripped = <CifraSeg>[];
  var removed = 0;
  for (final seg in segs) {
    switch (seg) {
      case CifraTextSeg(:final text):
        if (removed >= charCount) {
          stripped.add(seg);
        } else if (removed + text.length <= charCount) {
          removed += text.length; // 整段落在前缀里,不产出。
        } else {
          final rest = text.substring(charCount - removed);
          removed = charCount;
          if (rest.isNotEmpty) stripped.add(CifraTextSeg(rest));
        }
      case CifraChordSeg():
        // 前缀全是行首文本,和弦段必然整体在后:列位一律前移。
        final column = seg.column - charCount;
        stripped.add(
          CifraChordSeg(
            name: seg.name,
            raw: seg.raw,
            column: column < 0 ? 0 : column,
          ),
        );
    }
  }
  return stripped;
}

sealed class _CifraLine {
  static _CifraLine of(List<CifraSeg> segs) {
    final chords = <CifraChordSeg>[
      for (final seg in segs)
        if (seg is CifraChordSeg) seg,
    ];
    final text = [
      for (final seg in segs)
        if (seg is CifraTextSeg) seg.text,
    ].join();
    if (chords.isEmpty) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return _BlankLine();
      final marker = _markerRe.firstMatch(trimmed);
      if (marker != null) {
        final label = marker.group(1)!.trim();
        return _MarkerLine(slug: _markerSlug(label), label: _cleanLabel(label));
      }
      return _LyricLine(text);
    }
    if (_lyricish(text).isEmpty) return _ChordLine(chords);
    return _MixedLine(chords, text);
  }
}

class _BlankLine extends _CifraLine {}

class _MarkerLine extends _CifraLine {
  _MarkerLine({required this.slug, required this.label});

  /// 段落指令名([a-z0-9_],已去重音/非法字符)。
  final String slug;

  /// 展示标签(指令参数,去花括号/换行)。
  final String label;
}

class _ChordLine extends _CifraLine {
  _ChordLine(this.chords);

  final List<CifraChordSeg> chords;
}

/// 纯歌词行(无和弦段的行)。
class _LyricLine extends _CifraLine {
  _LyricLine(this.rawText);

  /// 原始文本(含缩进——配对转换的列位减缩进靠它)。
  final String rawText;

  String get lyricText => rawText.trim();

  int get _indent => rawText.length - rawText.trimLeft().length;

  /// 疑似二记谱行(capo 变体):空白分词后**严格过半**像和弦记号,且至
  /// 少两个词。只紧跟悬空和弦行时才使用(见 buildChordPro)。
  /// 收得这么紧是因为丢行=静默数据损失(fail-closed):单词歌词行
  /// (葡语歌词常见,"Amor"/"Eu")在「吸收任意后缀」的和弦样判定下
  /// 必命中,词数<2 或恰好半数(如两词含一词)都留给歌词。
  bool get chordalish {
    final tokens =
        rawText.trim().split(RegExp(r'\s+'))..removeWhere((t) => t.isEmpty);
    if (tokens.length < 2) return false;
    final chordLike = tokens.where(_chordTokenRe.hasMatch).length;
    return chordLike * 2 > tokens.length;
  }

  /// 票 16 原型语义①②:首和弦吸行首;行中词中回退词首。
  List<(int, String)> pairedMarks(
    _ChordLine host, {
    required Set<String> allowedChords,
  }) {
    final lyric = lyricText;
    final marks = <(int, String)>[];
    var first = true;
    for (final seg in host.chords) {
      final name = _normalizeChord(seg.name, allowedChords);
      int pos;
      if (first) {
        pos = 0; // ① 原谱缩进只是排版习惯,首和弦吸行首。
        first = false;
      } else {
        pos = seg.column - _indent;
        if (pos < 0) {
          pos = 0;
        } else if (pos > 0 &&
            pos < lyric.length &&
            lyric[pos - 1] != ' ' &&
            lyric[pos] != ' ') {
          while (pos > 0 && lyric[pos - 1] != ' ') {
            pos--; // ② 词中回退词首。
          }
        }
      }
      marks.add((pos, name));
    }
    return marks;
  }
}

/// 混排行(和弦嵌在文字里,如「Intro: <b>Em</b> …」):DOM 顺序即意图,
/// 插入点取该和弦之前的纯文本累计长度,精确插入、不吸附。
class _MixedLine extends _CifraLine {
  _MixedLine(this.chords, this.rawText);

  final List<CifraChordSeg> chords;
  final String rawText;

  String get lyricText => rawText.trimRight();

  List<(int, String)> exactMarks(Set<String> allowedChords) {
    final marks = <(int, String)>[];
    var chordRawBefore = 0;
    for (final seg in chords) {
      // 插入点 = 和弦列位里属于「文本」的部分
      // (= 原始列位 − 之前各和弦段自身原始长度)。和弦名同样过归一:
      // 混排行绕过归一会让升号/巴西记谱写法(「Intro: D# live」)被
      // 白名单拦下,与悬空行路径不同待遇(审计 2026-10-16 #13)。
      marks.add((seg.column - chordRawBefore, _normalizeChord(seg.name, allowedChords)));
      chordRawBefore += seg.raw.length;
    }
    return marks;
  }
}

/// 悬空和弦行判定:去掉空隙与排版记号(空格/括号/竖线/重复次数如 2x、×4)
/// 后不剩内容——和弦名本体全在 [CifraChordSeg] 里,不靠文本猜。
final RegExp _chordLineJunkRe = RegExp(r'[\s()（）\[\]|·]');
final RegExp _repetitionRe = RegExp(r'(?:^|[^\da-z])[x×]?\d{1,2}[x×](?:[^\da-z]|$)',
    caseSensitive: false);

String _lyricish(String text) {
  var t = text.replaceAll(_repetitionRe, '');
  t = t.replaceAll(_chordLineJunkRe, '');
  return t.trim();
}

/// 段落标记行:整行一个方括号词。
final RegExp _markerRe = RegExp(r'^\[([^\[\]]+)\]$');

/// 和弦样 token:大写根音开头(A-G,可带升降号),后接 quality 字符集
/// (m/a/j/i/n/d/u/g/M + 数字与和弦记号)。不再吸收任意后缀:词形单词
/// (「Amor」= A+mor 的 o、「Deus」= D+e 的 e)不再判成和弦样——残余
/// 风险由「词数≥2 + 严格过半」门槛兜底(审计 2026-10-16 #14)。
/// (JS 侧的同类判定见 features/library/cifraclub_extract_js.dart 的
/// CHORD_SHAPE——那边判「粗体元素是不是和弦」用结构性 quality 词表,
/// 这边判「纯文本行是不是和弦样」用字符集,各自取各自的最紧形状。)
final RegExp _chordTokenRe = RegExp(r'^[A-G][#b♯♭]?[majindugsM0-9()#b♯♭/+\-]*$');

/// 标签进指令参数:去花括号与换行(会破坏 {directive: label} 语法)。
String _cleanLabel(String label) =>
    label.replaceAll(RegExp(r'[{}\n\r]'), '').trim();

/// 标记词 → 段落指令名:常见葡/英词表映射(去重音、忽略大小写),
/// 识别不了的落 custom(slug 由标签字母数字构成)。
String _markerSlug(String label) {
  var key = label.toLowerCase();
  const accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'é': 'e', 'ê': 'e', 'í': 'i',
    'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ç': 'c',
  };
  key = key.splitMapJoin(
    '',
    onNonMatch: (ch) => accents[ch] ?? ch,
  );
  const verseWords = {
    'verse', 'verso', 'estrofe', 'copla', 'primeira parte', 'segunda parte',
    'parte', 'parte 1', 'parte 2', 'estrofe 1', 'estrofe 2',
  };
  const chorusWords = {'chorus', 'refrao', 'coro', 'estribillo'};
  const bridgeWords = {'bridge', 'ponte'};
  if (verseWords.contains(key)) return 'verse';
  if (chorusWords.contains(key)) return 'chorus';
  if (bridgeWords.contains(key)) return 'bridge';
  final slug = key
      .splitMapJoin(
        '',
        onNonMatch: (ch) => RegExp(r'[a-z0-9]').hasMatch(ch) ? ch : ' ',
      )
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');
  return slug.isEmpty ? 'part' : slug;
}
