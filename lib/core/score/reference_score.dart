/// 一手数据（.ibe 解码模型）→ 练习时间表的转换器。
///
/// 移植自 codex 项目 musicScore 的 `src/score/reference-score.mjs`（已按
/// 《天空之城》真机核验通过），守门断言逐条保留：遇到不认识的记号
/// **明确拒绝**，绝不悄悄丢弃或近似替代（GLOSSARY「无源不录谱」的
/// 数据侧纪律：只接受机器可读的一手源）。
///
/// 输入是原站旧版播放器 DTO（PascalCase 键名，原样保留不归一化）；
/// 输出 [ReferenceScore] 是纯秒制练习时间表：声音、流水画面、变色
/// 共用同一份事件表（ADR-0005 音画同源的数据基础）。
///
/// 参考真值（codex 核验报告）：51 小节、317 个非空节拍事件、557 音、
/// 曲长 152.8536585 秒、首声 2.25 秒、调弦 1→4 = A4 E4 C4 G4。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// 转换守门失败：[message] 为可直接展示给用户的中文原因。
class ScoreImportException implements Exception {
  const ScoreImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 一个小节的时间与拍号（数据侧，无排版信息）。
class RefMeasure {
  const RefMeasure({
    required this.index,
    required this.startSeconds,
    required this.durationSeconds,
    required this.tempo,
    required this.numerator,
    required this.denominator,
    required this.section,
  });

  final int index;
  final double startSeconds;
  final double durationSeconds;

  /// 本小节起始速度（BPM，四分音符）。
  final int tempo;
  final int numerator;
  final int denominator;

  /// 段落名（Part A / Part B / Ending…），无则 null。
  final String? section;
}

/// 一个音（事件内单根弦）。
class RefNote {
  const RefNote({
    required this.id,
    required this.stringNo,
    required this.fret,
    required this.midi,
    required this.isTieDestination,
    required this.tieOriginNoteId,
    required this.isNaturalHarmonic,
    required this.hasSlideOut,
    required this.sourceString,
  });

  final int id;

  /// 界面弦号 1..4（1 = 高 A 弦）。DTO 的 string=4 对应界面第 1 弦。
  final int stringNo;

  /// 品位，0 = 空弦。
  final int fret;

  /// MIDI 音高 = 调弦 + 品 + 变调夹。本曲泛音全部为 12 品自然泛音，
  /// 其音高恰等于该品位正常音，无需特判（codex 引擎互证）。
  final int midi;
  final bool isTieDestination;

  /// 延音起点音 id；非延音尾音为 null。
  final int? tieOriginNoteId;
  final bool isNaturalHarmonic;

  /// 滑出到后续音（DTO slideOutType=2），画滑音线用。
  final bool hasSlideOut;

  /// DTO 原始 string 值（1..4，4 = 界面第 1 弦），查错用。
  final int sourceString;
}

/// 和弦(按法图数据,GLOSSARY「和弦」的一手数据形态)。
class RefChord {
  const RefChord({
    required this.name,
    required this.firstFret,
    required this.strings,
    required this.showName,
    required this.showDiagram,
  });

  final String name;

  /// 按法图左端品位数(firstFret=1 即第一品)。
  final int firstFret;

  /// DTO 弦序(下标 0 = DTO string 1 = 界面第 1 弦)的品位值,0 = 空弦,
  /// -1 = 不弹。
  final List<int> strings;
  final bool showName;
  final bool showDiagram;
}

/// 一个节拍事件：同一时刻要弹/停的一组音（或休止）。
class RefEvent {
  const RefEvent({
    required this.id,
    required this.measureIndex,
    required this.voiceIndex,
    required this.startSeconds,
    required this.durationSeconds,
    required this.notes,
    required this.chord,
    required this.brushType,
    required this.durationValue,
    required this.dots,
    required this.startTick,
  });

  final int id;
  final int measureIndex;
  final int voiceIndex;
  final double startSeconds;

  /// 发声（或休止占位）持续秒数。
  final double durationSeconds;
  final List<RefNote> notes;

  /// 和弦按法图(无和弦标记为 null)。
  final RefChord? chord;

  /// 和弦名 convenience(画谱标题行用)。
  String? get chordName => chord?.name;

  /// DTO brushType：0 无；1/2 扫弦（下/上）；3/4 琶音（上/下）。
  final int brushType;

  /// DTO 时值分母（4=四分、8=八分…），画谱/休止符形用。
  final int durationValue;
  final int dots;

  /// DTO 播放起点 tick(=displayStart,守门已断言一致);符杠按拍分组用。
  final int startTick;

  bool get isRest => notes.isEmpty;
}

/// 转换产物：整首曲子的练习时间表。
class ReferenceScore {
  const ReferenceScore({
    required this.title,
    required this.artist,
    required this.sourceTempo,
    required this.startingTempo,
    required this.tuning1to4,
    required this.measures,
    required this.events,
    required this.durationSeconds,
  });

  final String title;
  final String artist;

  /// DTO 内标称速度（本曲 96，与页面不符，仅存档不用）。
  final int sourceTempo;

  /// 曲页权威起始速度（本曲 80，页面明确设置，覆盖 DTO 值）。
  final int startingTempo;
  final List<int> tuning1to4;
  final List<RefMeasure> measures;
  final List<RefEvent> events;
  final double durationSeconds;
}

/// 读取打包内的一手数据并转换。[assetKey] 默认为《天空之城》已核验
/// 样本（来源 guistudy 曲页 1yDFAg9Z3mV，SHA-256 729a076d…8145fc）。
Future<ReferenceScore> loadReferenceScore({
  AssetBundle? bundle,
  String assetKey = 'assets/scores/sky-city-guistudy.json',
  double pageTempoBpm = 80,
}) async {
  final raw = await (bundle ?? rootBundle).loadString(assetKey);
  return buildReferenceScore(jsonDecode(raw), pageTempoBpm: pageTempoBpm);
}

/// 把播放器 DTO 转成练习时间表。结构限制与 codex 版一致：单轨、单谱表、
/// 单活动声部、无反复/跳转/弱起/连音/渐变速度；不满足即抛
/// [ScoreImportException]，绝不静默降级。
ReferenceScore buildReferenceScore(
  Object source, {
  required double pageTempoBpm,
}) {
  if (source is! Map) {
    throw const ScoreImportException('曲谱数据格式无效');
  }
  final tracks = _list(source, 'tracks', '曲谱数据格式无效');
  final track = tracks.isNotEmpty ? tracks.first : null;
  final staves = track is Map ? _list(track, 'staves', '曲谱数据格式无效') : const [];
  if (tracks.length != 1 || staves.length != 1 || track is! Map || staves.first is! Map) {
    throw const ScoreImportException('请选择一个曲轨；暂不支持多谱表');
  }
  final staff = staves.first as Map;

  final tempo = pageTempoBpm;
  if (!(tempo > 0) || tempo.isInfinite) {
    throw const ScoreImportException('起始速度无效');
  }
  final tuning = _list(
    _map(staff, 'stringTuning', '调弦或变调夹数据不受支持'),
    'tunings',
    '调弦或变调夹数据不受支持',
  );
  final capo = staff.containsKey('capo') ? staff['capo'] : null;
  if (tuning.length != 4 ||
      capo is! int ||
      capo < 0 ||
      tuning.any((t) => t is! int)) {
    throw const ScoreImportException('调弦或变调夹数据不受支持');
  }

  final masterBars = _list(source, 'masterBars', '缺少小节数据');
  final bars = _list(staff, 'bars', '小节数据缺失');
  final chords = staff.containsKey('chords') && staff['chords'] is Map
      ? staff['chords'] as Map
      : const {};

  final measures = <RefMeasure>[];
  final events = <RefEvent>[];
  var currentTempo = tempo.round();
  var startSeconds = 0.0;
  for (var index = 0; index < masterBars.length; index++) {
    final master = masterBars[index];
    if (master is! Map) throw const ScoreImportException('曲谱数据格式无效');
    final tempoAutomation = master['tempoAutomation'];
    final hasUnsupportedTempo = tempoAutomation is Map &&
        ((tempoAutomation['isLinear'] == true) ||
            _asNum(tempoAutomation['ratioPosition']) != 0);
    final directions = master['directions'];
    final fermata = master['fermata'];
    if (_truthy(master['repeatCount']) ||
        master['isRepeatStart'] == true ||
        _truthy(master['alternateEndings']) ||
        master['isAnacrusis'] == true ||
        hasUnsupportedTempo ||
        _truthy(master['tripletFeel']) ||
        (directions is List && directions.isNotEmpty) ||
        (fermata is Map && fermata.isNotEmpty)) {
      throw ScoreImportException('第 ${index + 1} 小节含暂不支持的反复、弱起或变速记号');
    }
    if (index > 0 && tempoAutomation is Map) {
      currentTempo = _asInt(tempoAutomation['value'], '速度变化数据无效');
    }
    if (currentTempo <= 0) throw const ScoreImportException('速度变化数据无效');
    final numerator = _asInt(master['timeSignatureNumerator'], '不支持的拍号');
    final denominator = _asInt(master['timeSignatureDenominator'], '不支持的拍号');
    if (numerator < 1 || numerator > 32 || ![2, 4, 8, 16].contains(denominator)) {
      throw const ScoreImportException('不支持的拍号');
    }
    final quarterBeats = numerator * 4 / denominator;
    final durationSeconds = quarterBeats * 60 / currentTempo;
    final section = master['section'];
    measures.add(RefMeasure(
      index: index,
      startSeconds: startSeconds,
      durationSeconds: durationSeconds,
      tempo: currentTempo,
      numerator: numerator,
      denominator: denominator,
      section: section is Map && section['text'] is String && (section['text'] as String).isNotEmpty
          ? section['text'] as String
          : null,
    ));

    if (index >= bars.length) throw const ScoreImportException('小节数据缺失');
    final bar = bars[index];
    if (bar is! Map) throw const ScoreImportException('小节数据缺失');
    final voices = _list(bar, 'voices', '小节数据缺失');
    final activeVoices = voices
        .whereType<Map>()
        .where((v) => _list(v, 'beats', '小节数据缺失').any((b) =>
            b is Map && b['isEmpty'] != true))
        .length;
    if (activeVoices > 1) {
      throw const ScoreImportException('暂不支持多个同时演奏的声部');
    }
    for (var voiceIndex = 0; voiceIndex < voices.length; voiceIndex++) {
      final voice = voices[voiceIndex];
      if (voice is! Map) continue;
      for (final beat in _list(voice, 'beats', '小节数据缺失')) {
        if (beat is! Map) continue;
        if (beat['isEmpty'] == true) continue;
        events.add(_buildEvent(
          beat,
          measureIndex: index,
          voiceIndex: voiceIndex,
          measureStart: startSeconds,
          tempo: currentTempo,
          quarterBeats: quarterBeats,
          tuning: tuning.cast<int>(),
          capo: capo,
          chords: chords,
        ));
      }
    }
    startSeconds += durationSeconds;
  }
  if (bars.length != measures.length) {
    throw const ScoreImportException('小节数量不一致');
  }
  events.sort((a, b) {
    final byTime = a.startSeconds.compareTo(b.startSeconds);
    return byTime != 0 ? byTime : a.voiceIndex.compareTo(b.voiceIndex);
  });
  return ReferenceScore(
    title: source['title'] is String ? source['title'] as String : '',
    artist: source['artist'] is String ? source['artist'] as String : '',
    sourceTempo: _asInt(source['tempo'], '曲谱数据格式无效'),
    startingTempo: tempo.round(),
    tuning1to4: tuning.cast<int>(),
    measures: measures,
    events: events,
    durationSeconds: startSeconds,
  );
}

RefEvent _buildEvent(
  Map beat, {
  required int measureIndex,
  required int voiceIndex,
  required double measureStart,
  required int tempo,
  required double quarterBeats,
  required List<int> tuning,
  required int capo,
  required Map chords,
}) {
  final automations = beat['automations'];
  if ((automations is List && automations.any((a) => a is Map && a['type'] == 0)) ||
      _asNum(beat['graceType']) != 0) {
    throw const ScoreImportException('暂不支持小节中途变速或装饰音');
  }
  final duration = _asInt(beat['duration'], '暂不支持此时值或连音组');
  final dots = _asInt(beat['dots'], '暂不支持此时值或连音组');
  final tupletNum = _asNum(beat['tupletNumerator']).toInt();
  final tupletDen = _asNum(beat['tupletDenominator']).toInt();
  if (![1, 2, 4, 8, 16, 32, 64].contains(duration) ||
      dots < 0 ||
      dots > 3 ||
      (tupletNum > 0 && tupletNum != tupletDen)) {
    throw const ScoreImportException('暂不支持此时值或连音组');
  }
  final brushType = _asNum(beat['brushType']).toInt();
  if (_asNum(beat['beamingMode']) != 0 ||
      beat['fadeIn'] == true ||
      beat['hasRasgueado'] == true ||
      beat['pop'] == true ||
      beat['slap'] == true ||
      beat['tap'] == true ||
      _asNum(beat['whammyBarType']) != 0 ||
      (brushType != 0 && ![1, 2, 3, 4].contains(brushType)) ||
      _asNum(beat['vibrato']) != 0 ||
      _asNum(beat['pickStroke']) != 0 ||
      (beat['tremoloSpeed'] != null && _asNum(beat['tremoloSpeed']) != 0) ||
      _asNum(beat['crescendo']) != 0) {
    throw const ScoreImportException('曲谱含暂不支持的演奏效果或显式分组');
  }
  // 谱面时长必须与播放时长一致（codex 同款一致性断言）：不一致说明
  // 「画的」和「播的」会对不上，直接拒绝。
  final expectedTicks = 3840 / duration * (2 - 1 / math.pow(2, dots));
  final playbackDuration = _asNum(beat['playbackDuration']);
  if ((playbackDuration - expectedTicks).abs() > 1e-8) {
    throw const ScoreImportException('音符时值与播放时间不一致');
  }
  if (_asNum(beat['displayStart']) != _asNum(beat['playbackStart'])) {
    throw const ScoreImportException('音符时值与播放时间不一致');
  }
  const ticksPerQuarter = 960.0;
  final offset = _asNum(beat['playbackStart']) / ticksPerQuarter;
  final length = playbackDuration / ticksPerQuarter;
  if (offset.isNaN ||
      length.isNaN ||
      offset < 0 ||
      length <= 0 ||
      offset + length > quarterBeats + 1e-8) {
    throw const ScoreImportException('音符时间超出小节或数据无效');
  }
  final notes = <RefNote>[];
  for (final note in _list(beat, 'notes', '曲谱数据格式无效')) {
    if (note is! Map) throw const ScoreImportException('弦号或品位数据无效');
    final sourceString = _asInt(note['string'], '弦号或品位数据无效');
    final stringNo = tuning.length + 1 - sourceString;
    final fret = _asInt(note['fret'], '弦号或品位数据无效');
    if (stringNo < 1 || stringNo > 4 || fret < 0) {
      throw const ScoreImportException('弦号或品位数据无效');
    }
    final harmonicType = _asNum(note['harmonicType']).toInt();
    final slideOut = _asNum(note['slideOutType']).toInt();
    if (_asNum(note['bendType']) != 0 ||
        _asNum(note['slideInType']) != 0 ||
        (slideOut != 0 && slideOut != 2) ||
        _asNum(note['vibrato']) != 0 ||
        note['isHammerPullOrigin'] == true ||
        note['isSlurDestination'] == true ||
        note['isDead'] == true ||
        note['isGhost'] == true ||
        note['isPalmMute'] == true ||
        note['isLetRing'] == true ||
        note['isStaccato'] == true ||
        note['isLeftHandTapped'] == true ||
        _asNum(note['accentuated']) != 0 ||
        (harmonicType != 0 && harmonicType != 1)) {
      throw const ScoreImportException('曲谱含暂不支持的音符效果');
    }
    final tieOrigin = note['tieOriginNoteId'];
    notes.add(RefNote(
      id: _asInt(note['id'], '曲谱数据格式无效'),
      stringNo: stringNo,
      fret: fret,
      midi: tuning[stringNo - 1] + fret + capo,
      isTieDestination: note['isTieDestination'] == true,
      tieOriginNoteId: tieOrigin is int && tieOrigin >= 0 ? tieOrigin : null,
      isNaturalHarmonic: harmonicType == 1,
      hasSlideOut: slideOut == 2,
      sourceString: sourceString,
    ));
  }
  final chordId = beat['chordId'];
  final chordRaw = chordId is String ? chords[chordId] : null;
  final chord = chordRaw is Map
      ? RefChord(
          name: chordRaw['name'] is String ? chordRaw['name'] as String : '',
          firstFret: _asInt(chordRaw['firstFret'], '曲谱数据格式无效'),
          strings: [
            for (final s in _list(chordRaw, 'strings', '曲谱数据格式无效'))
              _asInt(s, '曲谱数据格式无效'),
          ],
          showName: chordRaw['showName'] != false,
          showDiagram: chordRaw['showDiagram'] != false,
        )
      : null;
  return RefEvent(
    id: _asInt(beat['id'], '曲谱数据格式无效'),
    measureIndex: measureIndex,
    voiceIndex: voiceIndex,
    startSeconds: measureStart + offset * 60 / tempo,
    durationSeconds: length * 60 / tempo,
    notes: notes,
    chord: chord,
    brushType: brushType,
    durationValue: duration,
    dots: dots,
    startTick: _asInt(beat['playbackStart'], '曲谱数据格式无效'),
  );
}

// ---- DTO 读取小工具：类型不对一律按数据格式错误拒绝 ----

/// 与移植源的 JS 真值语义对齐：0、空串、空列表、空映射为假，其余为真。
/// DTO 里「无反复结尾」等标记用 0 表示而非 null，不能用 `!= null` 判断。
bool _truthy(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.isNotEmpty;
  if (value is List) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}


List _list(Map map, String key, String message) {
  final value = map[key];
  if (value is List) return value;
  if (value == null) return const [];
  throw ScoreImportException(message);
}

Map _map(Map map, String key, String message) {
  final value = map[key];
  if (value is Map) return value;
  throw ScoreImportException(message);
}

num _asNum(Object? value) {
  if (value is num) return value;
  if (value == null) return 0;
  throw const ScoreImportException('曲谱数据格式无效');
}

int _asInt(Object? value, String message) {
  if (value is int) return value;
  if (value is num && value.toInt() == value) return value.toInt();
  throw ScoreImportException(message);
}
