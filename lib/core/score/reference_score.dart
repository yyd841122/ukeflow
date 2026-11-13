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

import 'score_gate.dart';

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

/// 调号 → 调名(原谱曲头「key = C 4/4」画谱用;按五度圈)。
String keyName(int keySignature) => const {
      0: 'C', 1: 'G', 2: 'D', 3: 'A', 4: 'E', 5: 'B', 6: 'F#', 7: 'C#',
      -1: 'F', -2: 'Bb', -3: 'Eb', -4: 'Ab', -5: 'Db', -6: 'Gb', -7: 'Cb',
    }[keySignature] ?? 'C';

/// 转换产物：整首曲子的练习时间表。
class ReferenceScore {
  const ReferenceScore({
    required this.title,
    required this.artist,
    required this.sourceTempo,
    required this.startingTempo,
    required this.keySignature,
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

  /// 调号(五度圈整数,0 = C;原谱曲头标记画谱用)。
  final int keySignature;
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

/// 换歌体检入口(票08):与转换守门**同一趟 walk** 的采集式检查。
/// 违例逐条记录为 [ScoreViolation](能力类记下后继续清点,结构类当场
/// 中止),零违例时 [ScoreHealthReport.score] 带出转换产物。
ScoreHealthReport checkScoreHealth(
  Object source, {
  required double pageTempoBpm,
}) {
  final walk = _HealthWalk();
  walk.run(source, pageTempoBpm);
  return walk.finish();
}

/// 把播放器 DTO 转成练习时间表。结构限制与 codex 版一致：单轨、单谱表、
/// 单活动声部、无反复/跳转/弱起/连音/渐变速度；不满足即抛
/// [ScoreImportException]，绝不静默降级。守门与体检**同源**：内部就是
/// [checkScoreHealth] 同一趟采集式检查，违例即抛首条（顺序 = walk 序，
/// 消息 = 该条违例的用户可读文本，测试锁定）。
ReferenceScore buildReferenceScore(
  Object source, {
  required double pageTempoBpm,
}) {
  final report = checkScoreHealth(source, pageTempoBpm: pageTempoBpm);
  final score = report.score;
  if (score == null) {
    throw ScoreImportException(report.firstMessage);
  }
  return score;
}

/// 采集式守门/体检 walk（单一来源：守门与体检共用，绝不另写一套判别）。
/// 每个守门点要么 [flag]（能力类：记号认识但不支持，数据仍可信，继续
/// 走完清点），要么 [flagStop]（结构类：资料本身坏，当场中止深入）。
/// 中止点 = 原守门拒绝点，首条违例 = 原守门抛出的那条。
class _HealthWalk {
  final violations = <ScoreViolation>[];
  bool aborted = false;

  // 清点(谱面概览;中止后为部分数据,报告只采信中止前的部分)。
  int brushCount = 0;
  int harmonicCount = 0;
  int slideOutCount = 0;
  int tieCount = 0;
  int sectionCount = 0;
  int masterBarCount = 0;
  final timeSignatures = <String>{};
  final tempoChanges = <String>[];
  final measures = <RefMeasure>[];
  final events = <RefEvent>[];
  double startSeconds = 0;

  // 元数据与 walk 期常量(末段/事件构造要用)。
  String title = '';
  String artist = '';
  int sourceTempo = 0;
  int startingTempo = 0;
  int keySignature = 0;
  List<int>? tuning;
  int? capo;
  Map chords = const {};

  /// 能力类违例:记号认识但不支持,数据仍可信,记录后继续走完清点。
  void flag(String ruleId, GateCategory category, String message,
      {int? measure}) {
    violations.add(ScoreViolation(
      ruleId: ruleId,
      category: category,
      message: message,
      measure: measure,
    ));
  }

  /// 结构类违例:资料本身无法可靠读取,记录并中止深入。
  void flagStop(String ruleId, String message,
      {int? measure, GateCategory category = GateCategory.structure}) {
    violations.add(ScoreViolation(
      ruleId: ruleId,
      category: category,
      message: message,
      measure: measure,
      structural: true,
    ));
    aborted = true;
  }

  void run(Object source, double pageTempoBpm) {
    try {
      _walk(source, pageTempoBpm);
    } on ScoreImportException catch (error) {
      // 底层读取小工具(类型不符)抛的原始守门:按结构类记录,消息原样。
      if (!aborted) flagStop('data-format', error.message);
    }
  }

  void _walk(Object source, double pageTempoBpm) {
    if (source is! Map) {
      flagStop('data-format', '曲谱数据格式无效');
      return;
    }
    final tracks = _list(source, 'tracks', '曲谱数据格式无效');
    final track = tracks.isNotEmpty ? tracks.first : null;
    final staves =
        track is Map ? _list(track, 'staves', '曲谱数据格式无效') : const [];
    if (tracks.isEmpty || track is! Map || staves.isEmpty || staves.first is! Map) {
      flagStop('data-format', '曲谱数据格式无效');
      return;
    }
    if (tracks.length > 1 || staves.length > 1) {
      flag('multi-track', GateCategory.voices, '请选择一个曲轨；暂不支持多谱表');
    }
    final staff = staves.first as Map;

    final tempo = pageTempoBpm;
    if (!(tempo > 0) || tempo.isInfinite) {
      flagStop('tempo-invalid', '起始速度无效', category: GateCategory.tempo);
      return;
    }
    startingTempo = tempo.round();
    if (staff['stringTuning'] is! Map) {
      flagStop('tuning', '调弦或变调夹数据不受支持', category: GateCategory.tuning);
      return;
    }
    final tunings = (staff['stringTuning'] as Map)['tunings'];
    final capoRaw = staff.containsKey('capo') ? staff['capo'] : null;
    final tuningOk = tunings is List &&
        tunings.length == 4 &&
        tunings.every((t) => t is int) &&
        capoRaw is int &&
        capoRaw >= 0;
    if (!tuningOk) {
      flagStop('tuning', '调弦或变调夹数据不受支持', category: GateCategory.tuning);
      return;
    }
    tuning = [for (final t in tunings) t as int];
    capo = capoRaw;

    if (source['masterBars'] is! List) {
      flagStop('missing-bars', '缺少小节数据');
      return;
    }
    final masterBars = source['masterBars'] as List;
    masterBarCount = masterBars.length;
    if (staff['bars'] is! List) {
      flagStop('missing-bars', '小节数据缺失');
      return;
    }
    final bars = staff['bars'] as List;
    chords = staff.containsKey('chords') && staff['chords'] is Map
        ? staff['chords'] as Map
        : const {};

    var currentTempo = tempo.round();
    for (var index = 0; index < masterBars.length; index++) {
      final master = masterBars[index];
      if (master is! Map) {
        flagStop('data-format', '曲谱数据格式无效', measure: index + 1);
        return;
      }
      final tempoAutomation = master['tempoAutomation'];
      final isTempoAutomation = tempoAutomation is Map;
      // 先算(与原守门同点抛):ratioPosition 类型坏在反复记号清点前暴露。
      final hasUnsupportedTempo = isTempoAutomation &&
          ((tempoAutomation['isLinear'] == true) ||
              _asNum(tempoAutomation['ratioPosition']) != 0);
      final directions = master['directions'];
      final fermata = master['fermata'];
      final measureNo = index + 1;
      if (_truthy(master['repeatCount'])) {
        flag('repeat-count', GateCategory.repeat, '第 $measureNo 小节有反复次数标记(暂不支持反复)',
            measure: measureNo);
      }
      if (master['isRepeatStart'] == true) {
        flag('repeat-start', GateCategory.repeat, '第 $measureNo 小节为反复起点(暂不支持反复)',
            measure: measureNo);
      }
      if (_truthy(master['alternateEndings'])) {
        flag('repeat-endings', GateCategory.repeat, '第 $measureNo 小节有反复结尾替换(暂不支持反复)',
            measure: measureNo);
      }
      if (master['isAnacrusis'] == true) {
        flag('anacrusis', GateCategory.miscMark, '第 $measureNo 小节为弱起小节(暂不支持弱起)',
            measure: measureNo);
      }
      if (isTempoAutomation && tempoAutomation['isLinear'] == true) {
        flag('tempo-linear', GateCategory.tempo, '第 $measureNo 小节有渐变变速(暂不支持变速)',
            measure: measureNo);
      } else if (hasUnsupportedTempo) {
        flag('tempo-ratio', GateCategory.tempo, '第 $measureNo 小节有非拍头变速点(暂不支持变速)',
            measure: measureNo);
      }
      if (_truthy(master['tripletFeel'])) {
        flag('triplet-feel', GateCategory.miscMark, '第 $measureNo 小节有摇摆节奏记号(暂不支持)',
            measure: measureNo);
      }
      if (directions is List && directions.isNotEmpty) {
        flag('directions', GateCategory.repeat, '第 $measureNo 小节有跳转记号(D.C./Coda 等,暂不支持反复跳转)',
            measure: measureNo);
      }
      if (fermata is Map && fermata.isNotEmpty) {
        flag('fermata', GateCategory.effect, '第 $measureNo 小节有延长记号(暂不支持)',
            measure: measureNo);
      }
      // 小节头变速是支持的(恒速换挡);渐变/偏移已记,不再读值避免误报。
      if (index > 0 && isTempoAutomation && !hasUnsupportedTempo) {
        final nextTempo = _asInt(tempoAutomation['value'], '速度变化数据无效');
        if (nextTempo != currentTempo) {
          tempoChanges
              .add('第 $measureNo 小节起 $currentTempo→$nextTempo BPM');
          currentTempo = nextTempo;
        }
      }
      if (currentTempo <= 0) {
        flagStop('tempo-invalid', '速度变化数据无效',
            measure: measureNo, category: GateCategory.tempo);
        return;
      }
      final numerator = _tryAsInt(master['timeSignatureNumerator']);
      final denominator = _tryAsInt(master['timeSignatureDenominator']);
      if (numerator == null || denominator == null) {
        flagStop('time-signature-missing', '第 $measureNo 小节拍号数据缺失',
            measure: measureNo);
        return;
      }
      timeSignatures.add('$numerator/$denominator');
      var timeSigBroken = false;
      if (numerator < 1 || numerator > 32 || ![2, 4, 8, 16].contains(denominator)) {
        flag('time-signature', GateCategory.timeSignature,
            '第 $measureNo 小节拍号 $numerator/$denominator(暂不支持的拍号)',
            measure: measureNo);
        timeSigBroken = true;
      }
      // 拍号超界时按 4/4 走时间轴仅供清点(整谱已不可导入,不产谱)。
      final safeNumerator =
          timeSigBroken && (numerator < 1 || numerator > 32) ? 4 : numerator;
      final safeDenominator =
          timeSigBroken && ![2, 4, 8, 16].contains(denominator) ? 4 : denominator;
      final quarterBeats = safeNumerator * 4 / safeDenominator;
      final durationSeconds = quarterBeats * 60 / currentTempo;
      final section = master['section'];
      final sectionName =
          section is Map && section['text'] is String && (section['text'] as String).isNotEmpty
              ? section['text'] as String
              : null;
      if (sectionName != null) sectionCount++;
      measures.add(RefMeasure(
        index: index,
        startSeconds: startSeconds,
        durationSeconds: durationSeconds,
        tempo: currentTempo,
        numerator: safeNumerator,
        denominator: safeDenominator,
        section: sectionName,
      ));

      if (index >= bars.length) {
        flagStop('missing-bar', '第 $measureNo 小节小节数据缺失', measure: measureNo);
        return;
      }
      final bar = bars[index];
      if (bar is! Map) {
        flagStop('missing-bar', '第 $measureNo 小节小节数据缺失', measure: measureNo);
        return;
      }
      final voices = _list(bar, 'voices', '小节数据缺失');
      final activeVoices = voices
          .whereType<Map>()
          .where((v) => _list(v, 'beats', '小节数据缺失')
              .any((b) => b is Map && b['isEmpty'] != true))
          .length;
      if (activeVoices > 1) {
        flag('multi-voice', GateCategory.voices,
            '第 $measureNo 小节有多个同时演奏的声部(暂不支持)', measure: measureNo);
      }
      for (var voiceIndex = 0; voiceIndex < voices.length; voiceIndex++) {
        final voice = voices[voiceIndex];
        if (voice is! Map) continue;
        for (final beat in _list(voice, 'beats', '小节数据缺失')) {
          if (beat is! Map) continue;
          if (beat['isEmpty'] == true) continue;
          final event = _buildEvent(
            beat,
            measureIndex: index,
            measureNo: measureNo,
            voiceIndex: voiceIndex,
            measureStart: startSeconds,
            tempo: currentTempo,
            quarterBeats: quarterBeats,
          );
          if (event == null) return; // 结构中止
          events.add(event);
        }
      }
      startSeconds += durationSeconds;
    }
    if (bars.length != measures.length) {
      flagStop('bar-count', '小节数量不一致');
      return;
    }
    events.sort((a, b) {
      final byTime = a.startSeconds.compareTo(b.startSeconds);
      return byTime != 0 ? byTime : a.voiceIndex.compareTo(b.voiceIndex);
    });
    final firstMaster = masterBars.isNotEmpty && masterBars.first is Map
        ? masterBars.first as Map
        : const {};
    title = source['title'] is String ? source['title'] as String : '';
    artist = source['artist'] is String ? source['artist'] as String : '';
    sourceTempo = _asInt(source['tempo'], '曲谱数据格式无效');
    keySignature = firstMaster.containsKey('keySignature')
        ? _asInt(firstMaster['keySignature'], '曲谱数据格式无效')
        : 0;
  }

  RefEvent? _buildEvent(
    Map beat, {
    required int measureIndex,
    required int measureNo,
    required int voiceIndex,
    required double measureStart,
    required int tempo,
    required double quarterBeats,
  }) {
    final automations = beat['automations'];
    final hasMidTempo = automations is List &&
        automations.any((a) => a is Map && a['type'] == 0);
    if (hasMidTempo) {
      flag('tempo-mid', GateCategory.tempo, '第 $measureNo 小节有小节中途变速(暂不支持变速)',
          measure: measureNo);
    }
    if (_asNum(beat['graceType']) != 0) {
      flag('grace', GateCategory.effect, '第 $measureNo 小节有装饰音(暂不支持)',
          measure: measureNo);
    }
    final duration = _tryAsInt(beat['duration']);
    final dots = _tryAsInt(beat['dots']);
    if (duration == null || dots == null) {
      flagStop('duration-invalid', '第 $measureNo 小节时值数据无效',
          measure: measureNo);
      return null;
    }
    var timingBroken = false;
    if (![1, 2, 4, 8, 16, 32, 64].contains(duration)) {
      flag('duration-value', GateCategory.tuplet, '第 $measureNo 小节有时值 $duration(暂不支持的时值)',
          measure: measureNo);
      timingBroken = true;
    }
    if (dots < 0 || dots > 3) {
      flag('dots', GateCategory.tuplet, '第 $measureNo 小节有 $dots 个附点(暂不支持)',
          measure: measureNo);
      timingBroken = true;
    }
    final tupletNum = _asNum(beat['tupletNumerator']).toInt();
    final tupletDen = _asNum(beat['tupletDenominator']).toInt();
    if (tupletNum > 0 && tupletNum != tupletDen) {
      flag('tuplet', GateCategory.tuplet,
          '第 $measureNo 小节有 $tupletNum:$tupletDen 连音(暂不支持连音)', measure: measureNo);
      timingBroken = true;
    }
    final brushType = _asNum(beat['brushType']).toInt();
    if (_asNum(beat['beamingMode']) != 0) {
      flag('beaming', GateCategory.effect, '第 $measureNo 小节有显式符杠分组(暂不支持)',
          measure: measureNo);
    }
    if (beat['fadeIn'] == true) {
      flag('fade-in', GateCategory.effect, '第 $measureNo 小节有渐入记号(暂不支持)',
          measure: measureNo);
    }
    if (beat['hasRasgueado'] == true) {
      flag('rasgueado', GateCategory.effect, '第 $measureNo 小节有 Rasgueado 扫法(暂不支持)',
          measure: measureNo);
    }
    if (beat['pop'] == true) {
      flag('pop', GateCategory.effect, '第 $measureNo 小节有 Pop 技巧(暂不支持)',
          measure: measureNo);
    }
    if (beat['slap'] == true) {
      flag('slap', GateCategory.effect, '第 $measureNo 小节有 Slap 技巧(暂不支持)',
          measure: measureNo);
    }
    if (beat['tap'] == true) {
      flag('tap', GateCategory.effect, '第 $measureNo 小节有点弦(暂不支持)',
          measure: measureNo);
    }
    if (_asNum(beat['whammyBarType']) != 0) {
      flag('whammy-bar', GateCategory.effect, '第 $measureNo 小节有摇把记号(暂不支持)',
          measure: measureNo);
    }
    if (brushType != 0 && ![1, 2, 3, 4].contains(brushType)) {
      flag('brush-type', GateCategory.effect, '第 $measureNo 小节扫弦类型无效($brushType)',
          measure: measureNo);
    }
    if (_asNum(beat['vibrato']) != 0) {
      flag('beat-vibrato', GateCategory.effect, '第 $measureNo 小节有揉弦记号(暂不支持)',
          measure: measureNo);
    }
    if (_asNum(beat['pickStroke']) != 0) {
      flag('pick-stroke', GateCategory.effect, '第 $measureNo 小节有拨弦方向记号(暂不支持)',
          measure: measureNo);
    }
    if (beat['tremoloSpeed'] != null && _asNum(beat['tremoloSpeed']) != 0) {
      flag('tremolo', GateCategory.effect, '第 $measureNo 小节有震音记号(暂不支持)',
          measure: measureNo);
    }
    if (_asNum(beat['crescendo']) != 0) {
      flag('crescendo', GateCategory.effect, '第 $measureNo 小节有渐强渐弱记号(暂不支持)',
          measure: measureNo);
    }
    if (brushType >= 1 && brushType <= 4) brushCount++;

    // 谱面时长必须与播放时长一致(codex 同款一致性断言):不一致说明
    // 「画的」和「播的」会对不上,资料不可信,直接拒绝。时值已违例时跳过
    // (派生断言不可信,避免误报;整谱反正不产谱)。
    final playbackDuration = _asNum(beat['playbackDuration']);
    if (!timingBroken) {
      final expectedTicks = 3840 / duration * (2 - 1 / math.pow(2, dots));
      if ((playbackDuration - expectedTicks).abs() > 1e-8) {
        flagStop('timing-mismatch', '第 $measureNo 小节音符时值与播放时间不一致',
            measure: measureNo);
        return null;
      }
      if (_asNum(beat['displayStart']) != _asNum(beat['playbackStart'])) {
        flagStop('timing-mismatch', '第 $measureNo 小节音符显示位置与播放位置不一致',
            measure: measureNo);
        return null;
      }
      const ticksPerQuarter = 960.0;
      final offset = _asNum(beat['playbackStart']) / ticksPerQuarter;
      final length = playbackDuration / ticksPerQuarter;
      if (offset.isNaN ||
          length.isNaN ||
          offset < 0 ||
          length <= 0 ||
          offset + length > quarterBeats + 1e-8) {
        flagStop('timing-overflow', '第 $measureNo 小节音符时间超出小节或数据无效',
            measure: measureNo);
        return null;
      }
    }
    final notes = <RefNote>[];
    final rawNotes = beat['notes'];
    if (rawNotes != null && rawNotes is! List) {
      flagStop('data-format', '曲谱数据格式无效', measure: measureNo);
      return null;
    }
    for (final note in rawNotes is List ? rawNotes : const []) {
      final parsed = _parseNote(note, measureNo);
      if (parsed == null) return null; // 结构中止
      if (parsed.$2) harmonicCount++;
      if (parsed.$3) slideOutCount++;
      if (parsed.$1.isTieDestination) tieCount++;
      notes.add(parsed.$1);
    }
    final chordId = beat['chordId'];
    final chordRaw = chordId is String ? chords[chordId] : null;
    final chord = chordRaw is Map ? _parseChord(chordRaw) : null;
    return RefEvent(
      id: _asInt(beat['id'], '曲谱数据格式无效'),
      measureIndex: measureIndex,
      voiceIndex: voiceIndex,
      startSeconds:
          measureStart + (_asNum(beat['playbackStart']) / 960.0) * 60 / tempo,
      durationSeconds: playbackDuration / 960.0 * 60 / tempo,
      notes: notes,
      chord: chord,
      brushType: brushType,
      durationValue: duration,
      dots: dots,
      startTick: _asInt(beat['playbackStart'], '曲谱数据格式无效'),
    );
  }

  /// 单音解析:效果违例逐条 [flag](能力类),弦/品坏则 [flagStop] 中止
  /// (返回 null)。附 `(note, 是自然泛音, 有滑出)`。
  (RefNote, bool, bool)? _parseNote(Object note, int measureNo) {
    if (note is! Map) {
      flagStop('data-format', '曲谱数据格式无效', measure: measureNo);
      return null;
    }
    final sourceString = _tryAsInt(note['string']);
    final fret = _tryAsInt(note['fret']);
    if (sourceString == null || fret == null) {
      flagStop('string-fret', '第 $measureNo 小节弦号或品位数据无效',
          measure: measureNo);
      return null;
    }
    final stringNo = tuning!.length + 1 - sourceString;
    if (stringNo < 1 || stringNo > 4 || fret < 0) {
      flagStop('string-fret', '第 $measureNo 小节弦号或品位数据无效',
          measure: measureNo);
      return null;
    }
    final harmonicType = _asNum(note['harmonicType']).toInt();
    final slideOut = _asNum(note['slideOutType']).toInt();
    if (_asNum(note['bendType']) != 0) {
      flag('note-bend', GateCategory.effect,
          '第 $measureNo 小节有推弦记号(暂不支持的音符效果)', measure: measureNo);
    }
    if (_asNum(note['slideInType']) != 0) {
      flag('note-slide-in', GateCategory.effect,
          '第 $measureNo 小节有滑入记号(暂不支持的音符效果)', measure: measureNo);
    }
    if (slideOut != 0 && slideOut != 2) {
      flag('note-slide-out', GateCategory.effect,
          '第 $measureNo 小节滑出记号类型无效($slideOut)', measure: measureNo);
    }
    if (_asNum(note['vibrato']) != 0) {
      flag('note-vibrato', GateCategory.effect,
          '第 $measureNo 小节有揉弦记号(暂不支持的音符效果)', measure: measureNo);
    }
    if (note['isHammerPullOrigin'] == true) {
      flag('note-hammer-pull', GateCategory.effect,
          '第 $measureNo 小节有击勾音(HO/PO)(暂不支持的音符效果)', measure: measureNo);
    }
    if (note['isSlurDestination'] == true) {
      flag('note-slur', GateCategory.effect,
          '第 $measureNo 小节有连音线(slur)(暂不支持的音符效果)', measure: measureNo);
    }
    if (note['isDead'] == true) {
      flag('note-dead', GateCategory.effect, '第 $measureNo 小节有闷音(暂不支持的音符效果)',
          measure: measureNo);
    }
    if (note['isGhost'] == true) {
      flag('note-ghost', GateCategory.effect, '第 $measureNo 小节有幽灵音(暂不支持的音符效果)',
          measure: measureNo);
    }
    if (note['isPalmMute'] == true) {
      flag('note-palm-mute', GateCategory.effect,
          '第 $measureNo 小节有掌闷音(暂不支持的音符效果)', measure: measureNo);
    }
    if (note['isLetRing'] == true) {
      flag('note-let-ring', GateCategory.effect,
          '第 $measureNo 小节有延音记号(letRing)(暂不支持的音符效果)', measure: measureNo);
    }
    if (note['isStaccato'] == true) {
      flag('note-staccato', GateCategory.effect, '第 $measureNo 小节有断音(暂不支持的音符效果)',
          measure: measureNo);
    }
    if (note['isLeftHandTapped'] == true) {
      flag('note-left-tap', GateCategory.effect,
          '第 $measureNo 小节有左手点弦(暂不支持的音符效果)', measure: measureNo);
    }
    if (_asNum(note['accentuated']) != 0) {
      flag('note-accent', GateCategory.effect,
          '第 $measureNo 小节有重音记号(暂不支持的音符效果)', measure: measureNo);
    }
    if (harmonicType != 0 && harmonicType != 1) {
      flag('note-harmonic', GateCategory.effect,
          '第 $measureNo 小节泛音类型无效($harmonicType)', measure: measureNo);
    }
    final isTieDestination = note['isTieDestination'] == true;
    final tieOrigin = note['tieOriginNoteId'];
    return (
      RefNote(
        id: _asInt(note['id'], '曲谱数据格式无效'),
        stringNo: stringNo,
        fret: fret,
        midi: tuning![stringNo - 1] + fret + capo!,
        isTieDestination: isTieDestination,
        tieOriginNoteId: tieOrigin is int && tieOrigin >= 0 ? tieOrigin : null,
        isNaturalHarmonic: harmonicType == 1,
        hasSlideOut: slideOut == 2,
        sourceString: sourceString,
      ),
      harmonicType == 1,
      slideOut == 2,
    );
  }

  RefChord _parseChord(Map chordRaw) {
    return RefChord(
      name: chordRaw['name'] is String ? chordRaw['name'] as String : '',
      firstFret: _asInt(chordRaw['firstFret'], '曲谱数据格式无效'),
      strings: [
        for (final s in _list(chordRaw, 'strings', '曲谱数据格式无效'))
          _asInt(s, '曲谱数据格式无效'),
      ],
      showName: chordRaw['showName'] != false,
      showDiagram: chordRaw['showDiagram'] != false,
    );
  }

  ScoreHealthReport finish() {
    final hasStructural = violations.any((v) => v.structural);
    final verdict = violations.isEmpty
        ? ScoreHealthVerdict.ready
        : hasStructural
            ? ScoreHealthVerdict.insufficient
            : ScoreHealthVerdict.needsRules;
    final featureNotes = <String>[];
    if (brushCount > 0) featureNotes.add('扫弦/琶音 ×$brushCount');
    if (harmonicCount > 0) featureNotes.add('自然泛音 ×$harmonicCount');
    if (slideOutCount > 0) featureNotes.add('滑出 ×$slideOutCount');
    if (tieCount > 0) featureNotes.add('延音 ×$tieCount');
    if (sectionCount > 0) featureNotes.add('段落标记 ×$sectionCount');
    featureNotes.addAll(tempoChanges);
    ReferenceScore? score;
    if (verdict == ScoreHealthVerdict.ready) {
      score = ReferenceScore(
        title: title,
        artist: artist,
        sourceTempo: sourceTempo,
        startingTempo: startingTempo,
        keySignature: keySignature,
        tuning1to4: tuning!,
        measures: measures,
        events: events,
        durationSeconds: startSeconds,
      );
    }
    return ScoreHealthReport(
      verdict: verdict,
      violations: List.unmodifiable(violations),
      featureNotes: List.unmodifiable(featureNotes),
      title: title,
      artist: artist,
      measureCount: masterBarCount > 0 ? masterBarCount : null,
      eventCount: aborted ? null : events.length,
      noteCount: aborted
          ? null
          : events.fold<int>(0, (n, e) => n + e.notes.length),
      durationSeconds: !aborted && startSeconds > 0 ? startSeconds : null,
      tuning1to4: tuning,
      capo: capo,
      timeSignatures: Set.unmodifiable(timeSignatures),
      score: score,
    );
  }
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

int? _tryAsInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.toInt() == value) return value.toInt();
  return null;
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
