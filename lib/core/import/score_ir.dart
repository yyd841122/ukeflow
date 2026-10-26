/// 识谱源(GLOSSARY「识谱源」Score IR,schemaVersion 1,ADR-0009):导入谱
/// 的唯一真源。照权威印张识别、经校对台人工逐位确认后由工作台导出的
/// 机器可读谱面描述——加载时经校验器+物化器(core/import/score_ir_
/// validator.dart / score_ir_materializer.dart)物化为既有组合结构
/// (ScoreSheetDef + TabChart×2,喂 buildScorePlaybackChart)方可显示与
/// 跟练。**它本身不是显示格式,也不是统一谱格式**(ADR-0009:运行时
/// 模型仍是 ADR-0003 双模型 + ADR-0008 组合视图)。
///
/// 与运行时模型的分界:拍位/休止/滑音/扫弦/和弦锚与 ScoreSheetDef 逐类
/// 对应(物化 1:1 直落);声部逐音带 `durationBeats`(运行时 TabNote 无
/// 时值,由拍位推导)与 `midi`(冗余校验字段)——识别端把纸上节奏符号算
/// 成拍位,时值是校验「每声部每小节拍长闭合」的原料。逐事件可带证据
/// (页码/框选/裁图/置信度);**不支持记号显式落 unsupportedSymbols,
/// 禁止静默丢**(校验器阻塞)。`ScoreStrumKind`/`ChordFingering` 直接复用
/// 运行时类型:扫弦种类与指形是域事实(照印张),物化零映射。
///
/// JSON 是工作台↔App 的交换契约:键一律 lowerCamelCase,可空字段缺省
/// 即 null。schemaVersion 不符当场拒析([ScoreIrFormatException])——坏源
/// 不静默(工单 43 的 Ready/Broken 兜底吃这里的异常面)。
library;

import '../chart/score_sheet_defs.dart';
import '../model/chord.dart';

/// 源格式版本(工单 42 定稿;结构变更须 bump 并写迁移)。
const int scoreIrSchemaVersion = 1;

/// 识谱源结构坏损:JSON 解析期当场拒析(缺键/类型错/schemaVersion 不符)。
/// 走 Exception 而非 Error,与内置内容的 [TabDataError] 故意分域:内置
/// 谱是 Dart 常量,坏 = 代码缺陷(Error,不参与捕获);识谱源是外部输入
/// (工作台导出/用户手改),坏 = 数据故障,工单 43 的 Ready/Broken 兜底
/// 必须捕获它显示「已损坏」。
class ScoreIrFormatException implements Exception {
  ScoreIrFormatException(this.message);

  final String message;

  @override
  String toString() => 'ScoreIrFormatException: $message';
}

/// 一份识谱源:曲名元信息 + 拍格骨架(meter/tempoMap/keyMap/measures)+
/// 双声部 + 主轴事件表 + 证据与复核状态。
class ScoreIr {
  const ScoreIr({
    required this.schemaVersion,
    required this.id,
    required this.title,
    this.artist,
    required this.meter,
    required this.tempoMap,
    required this.keyMap,
    required this.measures,
    required this.melodyAlignBeats,
    required this.tabChartId,
    required this.melodyChartId,
    required this.melody,
    required this.accompaniment,
    this.rests = const [],
    this.slides = const [],
    this.tremolos = const [],
    this.strums = const [],
    this.chordAnchors = const [],
    this.unsupportedSymbols = const [],
    this.review,
  });

  factory ScoreIr.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != scoreIrSchemaVersion) {
      throw ScoreIrFormatException(
        'schemaVersion 不符:期望 $scoreIrSchemaVersion,实际 '
        '${json['schemaVersion']}(旧版源请先在工作台重导出)',
      );
    }
    return ScoreIr(
      schemaVersion: scoreIrSchemaVersion,
      id: _s(json, 'id'),
      title: _s(json, 'title'),
      artist: _sOrNull(json, 'artist'),
      meter: ScoreIrMeter.fromJson(_m(json, 'meter')),
      tempoMap: [
        for (final e in _l(json, 'tempoMap')) ScoreIrTempoChange.fromJson(_cast(e)),
      ],
      keyMap: [
        for (final e in _l(json, 'keyMap')) ScoreIrKeyChange.fromJson(_cast(e)),
      ],
      measures: [
        for (final e in _l(json, 'measures')) ScoreIrMeasure.fromJson(_cast(e)),
      ],
      melodyAlignBeats: _d(json, 'melodyAlignBeats'),
      tabChartId: _s(json, 'tabChartId'),
      melodyChartId: _s(json, 'melodyChartId'),
      melody: ScoreIrVoice.fromJson(
        _cast(_cast(json['voices'])['melody'], 'voices.melody'),
      ),
      accompaniment: ScoreIrVoice.fromJson(
        _cast(_cast(json['voices'])['accompaniment'], 'voices.accompaniment'),
      ),
      rests: [
        if (json['rests'] != null)
          for (final e in (json['rests']! as List)) ScoreIrRestEvent.fromJson(_cast(e)),
      ],
      slides: [
        if (json['slides'] != null)
          for (final e in (json['slides']! as List)) ScoreIrSlideEvent.fromJson(_cast(e)),
      ],
      tremolos: [
        if (json['tremolos'] != null)
          for (final e in (json['tremolos']! as List)) ScoreIrTremoloEvent.fromJson(_cast(e)),
      ],
      strums: [
        if (json['strums'] != null)
          for (final e in (json['strums']! as List)) ScoreIrStrumEvent.fromJson(_cast(e)),
      ],
      chordAnchors: [
        if (json['chordAnchors'] != null)
          for (final e in (json['chordAnchors']! as List))
            ScoreIrChordAnchor.fromJson(_cast(e)),
      ],
      unsupportedSymbols: [
        if (json['unsupportedSymbols'] != null)
          for (final e in (json['unsupportedSymbols']! as List))
            ScoreIrUnsupportedSymbol.fromJson(_cast(e)),
      ],
      review: json['review'] == null
          ? null
          : ScoreIrReview.fromJson(_cast(json['review'])),
    );
  }

  /// 源格式版本,恒 [scoreIrSchemaVersion]。
  final int schemaVersion;

  /// 曲目 id(独奏谱类目卡 key;内置金标准照录 def.id)。
  final String id;

  /// 曲名(歌本体;物化为 def.title 与两层 TabChart 题)。
  final String title;

  /// 演唱者,无则 null。
  final String? artist;

  /// 拍号(v1 全库 4/4;变拍须 bump schema——工单 39 实测印张 2/4 段按连
  /// 拍格录入,统一 4/4 已够)。
  final ScoreIrMeter meter;

  /// 变速表,首条须落在拍 0(物化取首条为 TabChart.tempo)。
  final List<ScoreIrTempoChange> tempoMap;

  /// 调号表,首条须落在拍 0(物化取首条为 def.keySignature)。
  final List<ScoreIrKeyChange> keyMap;

  /// 小节骨架(主轴拍格):number 自 1 连续,startBeat = (number-1) ×
  /// meter.beatsPerMeasure(冗余校验字段,校验器逐条核对)。
  final List<ScoreIrMeasure> measures;

  /// 旋律层 → 主轴的恒定拍格偏移(与 ScoreSheetDef.melodyAlignBeats 同义,
  /// 旋律声部拍位为层内本地拍位)。
  final double melodyAlignBeats;

  /// TAB 伴奏层(主轴)的谱 id(照录内置绑定;导入谱由持久化层自定)。
  final String tabChartId;

  /// 简谱旋律层的谱 id。
  final String melodyChartId;

  /// 简谱旋律声部(层内本地拍位)。
  final ScoreIrVoice melody;

  /// TAB 伴奏声部(主轴拍位)。
  final ScoreIrVoice accompaniment;

  /// 主轴显示休止(照印张休止记号,物化为 ScoreSheetDef.rests;与声部
  /// 休止分列——前者是「印张画了休止符」,后者是拍长闭合的簿记)。
  final List<ScoreIrRestEvent> rests;

  /// 滑音(物化为 ScoreSheetDef.slides;起止拍须有声部音,校验器核对)。
  final List<ScoreIrSlideEvent> slides;

  /// 震音记号(物化为 ScoreSheetDef.tremolos)。
  final List<ScoreIrTremoloEvent> tremolos;

  /// 扫弦/卷弦事件(物化为 ScoreSheetDef.strums)。
  final List<ScoreIrStrumEvent> strums;

  /// 和弦行拍锚(物化为 ScoreSheetDef.chords)。
  final List<ScoreIrChordAnchor> chordAnchors;

  /// 不支持记号(击弦/勾弦等):显式落表留证据,**校验器逐条阻塞**——
  /// 禁止静默丢(ADR-0009 证据链强制)。空表 = 全部记号受支持。
  final List<ScoreIrUnsupportedSymbol> unsupportedSymbols;

  /// 复核状态(校对台全曲逐小节确认后导出;内置金标准往返为已对照值,
  /// 物化不消费此字段)。null = 未复核。
  final ScoreIrReview? review;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'title': title,
        if (artist != null) 'artist': artist,
        'meter': meter.toJson(),
        'tempoMap': [for (final e in tempoMap) e.toJson()],
        'keyMap': [for (final e in keyMap) e.toJson()],
        'measures': [for (final e in measures) e.toJson()],
        'melodyAlignBeats': melodyAlignBeats,
        'tabChartId': tabChartId,
        'melodyChartId': melodyChartId,
        'voices': {
          'melody': melody.toJson(),
          'accompaniment': accompaniment.toJson(),
        },
        if (rests.isNotEmpty) 'rests': [for (final e in rests) e.toJson()],
        if (slides.isNotEmpty) 'slides': [for (final e in slides) e.toJson()],
        if (tremolos.isNotEmpty)
          'tremolos': [for (final e in tremolos) e.toJson()],
        if (strums.isNotEmpty) 'strums': [for (final e in strums) e.toJson()],
        if (chordAnchors.isNotEmpty)
          'chordAnchors': [for (final e in chordAnchors) e.toJson()],
        if (unsupportedSymbols.isNotEmpty)
          'unsupportedSymbols': [
            for (final e in unsupportedSymbols) e.toJson(),
          ],
        if (review != null) 'review': review!.toJson(),
      };
}

/// 拍号:每小节 [beatsPerMeasure] 拍,以 [beatUnit] 分音符为一拍(v1 全库 4/4)。
class ScoreIrMeter {
  const ScoreIrMeter({required this.beatsPerMeasure, required this.beatUnit});

  factory ScoreIrMeter.fromJson(Map<String, dynamic> json) => ScoreIrMeter(
        beatsPerMeasure: _i(json, 'beatsPerMeasure'),
        beatUnit: _i(json, 'beatUnit'),
      );

  final int beatsPerMeasure;
  final int beatUnit;

  Map<String, dynamic> toJson() =>
      {'beatsPerMeasure': beatsPerMeasure, 'beatUnit': beatUnit};
}

/// 变速点:第 [beat] 拍起每分钟 [bpm] 拍(四分拍)。
class ScoreIrTempoChange {
  const ScoreIrTempoChange({required this.beat, required this.bpm});

  factory ScoreIrTempoChange.fromJson(Map<String, dynamic> json) =>
      ScoreIrTempoChange(beat: _d(json, 'beat'), bpm: _i(json, 'bpm'));

  final double beat;
  final int bpm;

  Map<String, dynamic> toJson() => {'beat': beat, 'bpm': bpm};
}

/// 调号点:第 [beat] 拍起为 [key](照印张记法,如「1=E」)。
class ScoreIrKeyChange {
  const ScoreIrKeyChange({required this.beat, required this.key});

  factory ScoreIrKeyChange.fromJson(Map<String, dynamic> json) =>
      ScoreIrKeyChange(beat: _d(json, 'beat'), key: _s(json, 'key'));

  final double beat;
  final String key;

  Map<String, dynamic> toJson() => {'beat': beat, 'key': key};
}

/// 小节骨架:第 [number] 小节起于主轴第 [startBeat] 拍。
class ScoreIrMeasure {
  const ScoreIrMeasure({required this.number, required this.startBeat});

  factory ScoreIrMeasure.fromJson(Map<String, dynamic> json) =>
      ScoreIrMeasure(number: _i(json, 'number'), startBeat: _d(json, 'startBeat'));

  final int number;
  final double startBeat;

  Map<String, dynamic> toJson() => {'number': number, 'startBeat': startBeat};
}

/// 一个声部:逐音事件 + 声部休止。声部休止是拍长闭合的簿记(印张休止
/// 符号或音间气口),物化不消费(运行时时值由拍位推导,气口即空档);
/// 导入源的休止证据落在这里。
class ScoreIrVoice {
  const ScoreIrVoice({required this.notes, this.rests = const []});

  factory ScoreIrVoice.fromJson(Map<String, dynamic> json) => ScoreIrVoice(
        notes: [
          for (final e in _l(json, 'notes')) ScoreIrNote.fromJson(_cast(e)),
        ],
        rests: [
          if (json['rests'] != null)
            for (final e in (json['rests']! as List)) ScoreIrRest.fromJson(_cast(e)),
        ],
      );

  /// 逐音事件,按演奏序(拍位升序,同拍按录入序)。
  final List<ScoreIrNote> notes;

  /// 声部休止,按拍位升序。
  final List<ScoreIrRest> rests;

  Map<String, dynamic> toJson() => {
        'notes': [for (final e in notes) e.toJson()],
        if (rests.isNotEmpty) 'rests': [for (final e in rests) e.toJson()],
      };
}

/// 声部一个音:第 [string] 弦第 [fret] 品、第 [beat] 拍起响 [durationBeats]
/// 拍。[midi] 为冗余校验字段(= 空弦 midi + fret);[lyric] 逐音缀字
/// (内置金标准的旋律层缀词,识别端一期不产歌词,恒 null)。
class ScoreIrNote {
  const ScoreIrNote({
    required this.beat,
    required this.durationBeats,
    required this.string,
    required this.fret,
    required this.midi,
    this.lyric,
    this.evidence,
  });

  factory ScoreIrNote.fromJson(Map<String, dynamic> json) => ScoreIrNote(
        beat: _d(json, 'beat'),
        durationBeats: _d(json, 'durationBeats'),
        string: _i(json, 'string'),
        fret: _i(json, 'fret'),
        midi: _i(json, 'midi'),
        lyric: _sOrNull(json, 'lyric'),
        evidence: json['evidence'] == null
            ? null
            : ScoreIrEvidence.fromJson(_cast(json['evidence'])),
      );

  final double beat;
  final double durationBeats;
  final int string;
  final int fret;
  final int midi;
  final String? lyric;
  final ScoreIrEvidence? evidence;

  Map<String, dynamic> toJson() => {
        'beat': beat,
        'durationBeats': durationBeats,
        'string': string,
        'fret': fret,
        'midi': midi,
        if (lyric != null) 'lyric': lyric,
        if (evidence != null) 'evidence': evidence!.toJson(),
      };
}

/// 声部一个休止:第 [beat] 拍起休 [beats] 拍。
class ScoreIrRest {
  const ScoreIrRest({required this.beat, required this.beats, this.evidence});

  factory ScoreIrRest.fromJson(Map<String, dynamic> json) => ScoreIrRest(
        beat: _d(json, 'beat'),
        beats: _d(json, 'beats'),
        evidence: json['evidence'] == null
            ? null
            : ScoreIrEvidence.fromJson(_cast(json['evidence'])),
      );

  final double beat;
  final double beats;
  final ScoreIrEvidence? evidence;

  Map<String, dynamic> toJson() => {
        'beat': beat,
        'beats': beats,
        if (evidence != null) 'evidence': evidence!.toJson(),
      };
}

/// 主轴显示休止(照印张,物化为 ScoreRestEvent)。
class ScoreIrRestEvent {
  const ScoreIrRestEvent({required this.beat, required this.beats, this.evidence});

  factory ScoreIrRestEvent.fromJson(Map<String, dynamic> json) =>
      ScoreIrRestEvent(
        beat: _d(json, 'beat'),
        beats: _d(json, 'beats'),
        evidence: json['evidence'] == null
            ? null
            : ScoreIrEvidence.fromJson(_cast(json['evidence'])),
      );

  final double beat;
  final double beats;
  final ScoreIrEvidence? evidence;

  Map<String, dynamic> toJson() => {
        'beat': beat,
        'beats': beats,
        if (evidence != null) 'evidence': evidence!.toJson(),
      };
}

/// 滑音(物化为 ScoreSlideEvent):从 [fromBeat] 的音滑到 [toBeat] 的音。
class ScoreIrSlideEvent {
  const ScoreIrSlideEvent({
    required this.fromBeat,
    required this.toBeat,
    this.evidence,
  });

  factory ScoreIrSlideEvent.fromJson(Map<String, dynamic> json) =>
      ScoreIrSlideEvent(
        fromBeat: _d(json, 'fromBeat'),
        toBeat: _d(json, 'toBeat'),
        evidence: json['evidence'] == null
            ? null
            : ScoreIrEvidence.fromJson(_cast(json['evidence'])),
      );

  final double fromBeat;
  final double toBeat;
  final ScoreIrEvidence? evidence;

  Map<String, dynamic> toJson() => {
        'fromBeat': fromBeat,
        'toBeat': toBeat,
        if (evidence != null) 'evidence': evidence!.toJson(),
      };
}

/// 震音记号(物化为 ScoreTremoloEvent):[beat] 拍的 × 柱套椭圆框。
class ScoreIrTremoloEvent {
  const ScoreIrTremoloEvent({required this.beat, this.evidence});

  factory ScoreIrTremoloEvent.fromJson(Map<String, dynamic> json) =>
      ScoreIrTremoloEvent(
        beat: _d(json, 'beat'),
        evidence: json['evidence'] == null
            ? null
            : ScoreIrEvidence.fromJson(_cast(json['evidence'])),
      );

  final double beat;
  final ScoreIrEvidence? evidence;

  Map<String, dynamic> toJson() => {
        'beat': beat,
        if (evidence != null) 'evidence': evidence!.toJson(),
      };
}

/// 扫弦事件(物化为 ScoreStrumEvent):[beat] 拍同拍和弦音组按 [kind] 扫响。
class ScoreIrStrumEvent {
  const ScoreIrStrumEvent({required this.beat, required this.kind, this.evidence});

  factory ScoreIrStrumEvent.fromJson(Map<String, dynamic> json) =>
      ScoreIrStrumEvent(
        beat: _d(json, 'beat'),
        kind: _strumKind(_s(json, 'kind')),
        evidence: json['evidence'] == null
            ? null
            : ScoreIrEvidence.fromJson(_cast(json['evidence'])),
      );

  final double beat;

  /// 复用运行时扫弦种类(GLOSSARY「双轨混播」声部记号,照印张)。
  final ScoreStrumKind kind;
  final ScoreIrEvidence? evidence;

  Map<String, dynamic> toJson() => {
        'beat': beat,
        'kind': kind.name,
        if (evidence != null) 'evidence': evidence!.toJson(),
      };
}

/// 和弦行拍锚(物化为 ScoreChordAnchor):第 [beat] 拍起换 [label] 和弦,
/// 指形照印张(不走 chords-db 查表)。
class ScoreIrChordAnchor {
  const ScoreIrChordAnchor({
    required this.beat,
    required this.label,
    required this.fingering,
    this.evidence,
  });

  factory ScoreIrChordAnchor.fromJson(Map<String, dynamic> json) =>
      ScoreIrChordAnchor(
        beat: _d(json, 'beat'),
        label: _s(json, 'label'),
        fingering: _fingering(_cast(json['fingering'])),
        evidence: json['evidence'] == null
            ? null
            : ScoreIrEvidence.fromJson(_cast(json['evidence'])),
      );

  final double beat;
  final String label;

  /// 复用运行时指形模型(frets/fingers ④③②① 序,× = -1)。
  final ChordFingering fingering;
  final ScoreIrEvidence? evidence;

  Map<String, dynamic> toJson() => {
        'beat': beat,
        'label': label,
        'fingering': {
          'frets': fingering.frets,
          'fingers': fingering.fingers,
          'baseFret': fingering.baseFret,
          'barres': fingering.barres,
          if (fingering.midi != null) 'midi': fingering.midi,
        },
        if (evidence != null) 'evidence': evidence!.toJson(),
      };
}

/// 不支持记号:识别端遇到读谱法之外的记号(击弦/勾弦/泛音等)显式落表,
/// 校验器逐条阻塞——错误消息带 kind/beat/证据,回校对台消解后才准入库。
class ScoreIrUnsupportedSymbol {
  const ScoreIrUnsupportedSymbol({
    required this.kind,
    this.beat,
    this.evidence,
    this.note,
  });

  factory ScoreIrUnsupportedSymbol.fromJson(Map<String, dynamic> json) =>
      ScoreIrUnsupportedSymbol(
        kind: _s(json, 'kind'),
        beat: json['beat'] == null ? null : _d(json, 'beat'),
        evidence: json['evidence'] == null
            ? null
            : ScoreIrEvidence.fromJson(_cast(json['evidence'])),
        note: _sOrNull(json, 'note'),
      );

  /// 记号名(工作台约定串,如 'hammer-on'/'pull-off'/'harmonic')。
  final String kind;

  /// 主轴拍位(可定位处才填;整页性记号可 null)。
  final double? beat;
  final ScoreIrEvidence? evidence;

  /// 人工备注(如印张原文描述)。
  final String? note;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (beat != null) 'beat': beat,
        if (evidence != null) 'evidence': evidence!.toJson(),
        if (note != null) 'note': note,
      };
}

/// 识别证据(ADR-0009 证据链强制):页码/框选/裁图/置信度,四项皆可空
/// (内置金标准往返恒 null)。[bbox] = (x, y, w, h),原页渲染坐标系。
class ScoreIrEvidence {
  const ScoreIrEvidence({
    this.page,
    this.bbox,
    this.source,
    this.confidence,
  });

  factory ScoreIrEvidence.fromJson(Map<String, dynamic> json) =>
      ScoreIrEvidence(
        page: json['page'] == null ? null : _i(json, 'page'),
        bbox: json['bbox'] == null
            ? null
            : [for (final v in (json['bbox']! as List)) (v as num).toDouble()],
        source: _sOrNull(json, 'source'),
        confidence: json['confidence'] == null
            ? null
            : _d(json, 'confidence'),
      );

  final int? page;
  final List<double>? bbox;
  final String? source;
  final double? confidence;

  Map<String, dynamic> toJson() => {
        if (page != null) 'page': page,
        if (bbox != null) 'bbox': bbox,
        if (source != null) 'source': source,
        if (confidence != null) 'confidence': confidence,
      };

  @override
  bool operator ==(Object other) =>
      other is ScoreIrEvidence &&
      page == other.page &&
      _listEquals(bbox, other.bbox) &&
      source == other.source &&
      confidence == other.confidence;

  @override
  int get hashCode => Object.hash(
        page,
        bbox == null ? null : Object.hashAll(bbox!),
        source,
        confidence,
      );
}

/// 复核状态:[reviewedAt] = 校对台全曲确认时刻(ISO 8601)。空 = 未复核。
class ScoreIrReview {
  const ScoreIrReview({this.reviewedAt});

  factory ScoreIrReview.fromJson(Map<String, dynamic> json) =>
      ScoreIrReview(reviewedAt: _sOrNull(json, 'reviewedAt'));

  final String? reviewedAt;

  Map<String, dynamic> toJson() => {
        if (reviewedAt != null) 'reviewedAt': reviewedAt,
      };
}

ScoreStrumKind _strumKind(String name) {
  for (final kind in ScoreStrumKind.values) {
    if (kind.name == name) return kind;
  }
  throw ScoreIrFormatException('strums.kind 非法:「$name」'
      '(合法值:${ScoreStrumKind.values.map((k) => k.name).join("/")})');
}

ChordFingering _fingering(Map<String, dynamic> json) => ChordFingering(
      frets: [for (final v in _l(json, 'frets')) v as int],
      fingers: [for (final v in _l(json, 'fingers')) v as int],
      baseFret: _i(json, 'baseFret'),
      barres: [for (final v in _l(json, 'barres')) v as int],
      midi: json['midi'] == null
          ? null
          : [for (final v in (json['midi']! as List)) v as int],
    );

// ── JSON 取值帮手:类型不符当场拒析,消息指明键名(嵌套元素的坏项
// 由运行时类型名兜底示警;坏源不静默)。──

Map<String, dynamic> _cast(Object? v, [String path = '']) {
  if (v is Map<String, dynamic>) return v;
  throw ScoreIrFormatException(
      '${path.isEmpty ? '值' : path} 应为对象,实际 ${v?.runtimeType}');
}

Map<String, dynamic> _m(Map<String, dynamic> json, String key) =>
    _cast(json[key], key);

String _s(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is String && v.isNotEmpty) return v;
  throw ScoreIrFormatException('$key 应为非空字符串,实际 $v');
}

String? _sOrNull(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v == null) return null;
  if (v is String && v.isNotEmpty) return v;
  throw ScoreIrFormatException('$key 应为非空字符串或缺省,实际 $v');
}

double _d(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is num) return v.toDouble();
  throw ScoreIrFormatException('$key 应为数值,实际 $v');
}

int _i(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is int) return v;
  if (v is num && v == v.truncateToDouble()) return v.toInt();
  throw ScoreIrFormatException('$key 应为整数,实际 $v');
}

List<Object?> _l(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is List) return v;
  throw ScoreIrFormatException('$key 应为数组,实际 ${v?.runtimeType}');
}

bool _listEquals(List<double>? a, List<double>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
