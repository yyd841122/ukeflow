/// 识谱源校验器(工单 42,spec 测试缝⑥):ScoreIr → 逐条阻塞错误
/// (人话,供工单 44 导入页整屏列出)。合法 = 空表;非空 = 坏源,**禁止
/// 带病物化**(物化器先过本校验,工单 43 的 Broken 兜底吃这份清单)。
///
/// 规则(ADR-0009 证据链/转录纪律的机器化):
/// - 每声部每小节拍长闭合——事件(音+声部休止)与 4/4 小节线严丝合缝,
///   空洞/重叠/跨小节/整小节空白都是转录缺陷(工单 25「小节和=4 拍
///   逐小节校验」的自动版);
/// - 弦品合法(1..4 弦、0..[scoreIrMaxFret] 品),冗余 midi 与弦品换算
///   一致(GCEA 高 G,换算域事实 UkeString.midi);
/// - 同弦同刻冲突——**声部内**判定:双轨模型里旋律层与伴奏层本就是
///   两份独立转录,跨声部同拍同弦是常态(金标准:主轴拍 20 旋律②3 与
///   伴奏 E 堆②4 并存),不作冲突;声部内同拍同弦才是坏数据;
/// - 音域越界([scoreIrMaxFret] = 识别端读出的荒唐品位数;
///   validateTabChart 的负品位拦在物化后,这里前移到源);
/// - 不支持记号逐条阻塞——禁止静默丢(ADR-0009);
/// - tempoMap/keyMap 多条阻塞——v1 物化只产出单速/单调号(运行时
///   TabChart.tempo / ScoreSheetDef.keySignature),放多条必被静默丢,
///   与「禁止静默丢」同纪律:先在源里归并,bump schema 再议变逐段;
/// - 事件表(和弦锚/扫弦/震音/显示休止/滑音)拍位升序、出骨架拦下
///   (运行时 ScoreSheetDef 的字段契约:「严格按拍位升序」),滑音端点
///   必须落在伴奏声部的音上。
library;

import '../model/uke_string.dart';
import 'score_ir.dart';

/// 实用音域上限(品):金标准旋律最高 ①12(双轨混播 +4 → ①16 合法),
/// 15 品以上按识别误读处理。不是模型硬限——运行时 validateTabChart 只
/// 拦负品位;这道闸拦的是源端的荒唐数。
const int scoreIrMaxFret = 15;

/// 校验:[ir] 的全部阻塞错误,逐条人话;空表 = 合法。
List<String> validateScoreIr(ScoreIr ir) {
  final errors = <String>[];
  void err(String message) => errors.add(message);

  if (ir.schemaVersion != scoreIrSchemaVersion) {
    err('schemaVersion 不符:期望 $scoreIrSchemaVersion,实际 ${ir.schemaVersion}'
        '(旧版源请先在工作台重导出)');
  }
  if (ir.id.trim().isEmpty) err('id(曲目 id)为空');
  if (ir.title.trim().isEmpty) err('title(曲名)为空');
  if (ir.meter.beatsPerMeasure < 1 || ir.meter.beatUnit < 1) {
    err('拍号非法:每小节 ${ir.meter.beatsPerMeasure} 拍、${ir.meter.beatUnit} '
        '分音符为一拍,均须 ≥1');
  }
  final beatsPerMeasure = ir.meter.beatsPerMeasure < 1
      ? 4
      : ir.meter.beatsPerMeasure; // 骨架计算的容身值;坏拍号已单独报。

  if (ir.tempoMap.isEmpty) {
    err('tempoMap 为空(首条必须落在拍 0)');
  } else {
    if (ir.tempoMap.length > 1) {
      err('tempoMap 有 ${ir.tempoMap.length} 条变速点:v1 物化仅支持单速,'
          '中途变速会被静默丢——先在源里归并');
    }
    if (ir.tempoMap.first.beat != 0) {
      err('tempoMap 首条必须落在拍 0,实际 @${ir.tempoMap.first.beat}');
    }
    for (final t in ir.tempoMap) {
      if (t.bpm <= 0) err('tempoMap bpm 须正:@${t.beat} = ${t.bpm}');
    }
  }
  if (ir.keyMap.isEmpty) {
    err('keyMap 为空(首条必须落在拍 0)');
  } else {
    if (ir.keyMap.length > 1) {
      err('keyMap 有 ${ir.keyMap.length} 条调号点:v1 物化仅支持单调号,'
          '中途转调会被静默丢——先在源里归并');
    }
    if (ir.keyMap.first.beat != 0) {
      err('keyMap 首条必须落在拍 0,实际 @${ir.keyMap.first.beat}');
    }
    for (final k in ir.keyMap) {
      if (k.key.trim().isEmpty) err('keyMap 调号为空白:@${k.beat}');
    }
  }

  if (ir.measures.isEmpty) {
    err('measures(小节骨架)为空');
  } else {
    for (var i = 0; i < ir.measures.length; i++) {
      final m = ir.measures[i];
      if (m.number != i + 1) {
        err('measures 小节号须自 1 连续:第 ${i + 1} 条 number=${m.number}');
      }
      if (m.startBeat != (m.number - 1) * beatsPerMeasure) {
        err('measures[$i].startBeat 与拍号不符:number=${m.number} 应起于拍 '
            '${(m.number - 1) * beatsPerMeasure},实际 ${m.startBeat}');
      }
    }
  }
  final gridEnd = ir.measures.isEmpty
      ? 0.0
      : ir.measures.last.startBeat + beatsPerMeasure;

  if (ir.melodyAlignBeats < 0) {
    err('melodyAlignBeats(旋律对齐偏移)为负:${ir.melodyAlignBeats}');
  }
  _validateVoice(ir.accompaniment, '伴奏', 0, gridEnd, beatsPerMeasure, err);
  _validateVoice(ir.melody, '旋律', ir.melodyAlignBeats, gridEnd,
      beatsPerMeasure, err);

  _validateChordAnchors(ir.chordAnchors, gridEnd, err);
  _checkAscendingInBounds(
      [for (final s in ir.strums) s.beat], '扫弦事件', gridEnd, err);
  _checkAscendingInBounds(
      [for (final t in ir.tremolos) t.beat], '震音记号', gridEnd, err);
  for (final r in ir.rests) {
    if (r.beats.isNaN || r.beats.isInfinite || r.beats <= 0) {
      err('显示休止拍数须正有限:@${r.beat} 休 ${r.beats}');
    }
  }
  _checkAscendingInBounds(
      [for (final r in ir.rests) r.beat], '显示休止', gridEnd, err);
  _validateSlides(ir.slides, ir.accompaniment, gridEnd, err);
  for (final u in ir.unsupportedSymbols) {
    err('不支持记号「${u.kind}」${u.beat == null ? '' : '@${u.beat}'}:禁止静默丢,'
        '须在校对台消解后再导出${u.note == null ? '' : '(${u.note})'}');
  }
  return errors;
}

/// 声部校验:逐音合法性 + 每小节拍长闭合。[shift] = 层 → 主轴拍格偏移
/// (伴奏 0,旋律 melodyAlignBeats);闭合核对全部在主轴拍格上进行。
void _validateVoice(
  ScoreIrVoice voice,
  String name,
  double shift,
  double gridEnd,
  int beatsPerMeasure,
  void Function(String) err,
) {
  if (voice.notes.isEmpty) {
    err('$name 声部没有任何音');
    return;
  }
  final seenStringBeats = <(int, double)>{};
  for (var i = 0; i < voice.notes.length; i++) {
    final n = voice.notes[i];
    if (n.beat.isNaN || n.beat.isInfinite || n.beat < 0) {
      err('$name 声部拍位须非负有限:@${n.beat}');
    }
    if (n.durationBeats.isNaN ||
        n.durationBeats.isInfinite ||
        n.durationBeats <= 0) {
      err('$name 声部时值须正有限:@${n.beat} 时值 ${n.durationBeats}');
    }
    if (n.lyric != null && n.lyric!.trim().isEmpty) {
      err('$name 声部歌词缀字为空白:@${n.beat}');
    }
    if (n.string < 1 || n.string > UkeString.values.length) {
      err('$name 声部弦号越界(1..${UkeString.values.length}):'
          '@${n.beat} 弦 ${n.string}');
    } else {
      final openMidi = UkeString.byNumber(n.string).midi;
      if (n.fret < 0) {
        err('$name 声部品位为负:@${n.beat} 弦${n.string} ${n.fret} 品');
      } else if (n.fret > scoreIrMaxFret) {
        err('$name 声部音域越界(品 > $scoreIrMaxFret):'
            '@${n.beat} 弦${n.string} ${n.fret} 品');
      }
      if (n.midi != openMidi + n.fret) {
        err('$name 声部冗余 midi 不一致:@${n.beat} 弦${n.string} ${n.fret} 品 '
            'midi=${n.midi},应为 ${openMidi + n.fret}');
      }
      // 同弦同刻按声部内判定(跨声部同拍同弦是双轨常态,见文件头)。
      if (!seenStringBeats.add((n.string, n.beat))) {
        err('$name 声部同弦同刻冲突:弦${n.string} 在拍 ${n.beat} 有多个音');
      }
    }
    if (i > 0 && n.beat < voice.notes[i - 1].beat) {
      err('$name 声部录入序错乱(拍位须不降):'
          '@${n.beat} 排在 @${voice.notes[i - 1].beat} 之后');
    }
  }
  for (final r in voice.rests) {
    if (r.beat.isNaN || r.beat.isInfinite || r.beat < 0) {
      err('$name 声部休止拍位须非负有限:@${r.beat}');
    }
    if (r.beats.isNaN || r.beats.isInfinite || r.beats <= 0) {
      err('$name 声部休止拍数须正有限:@${r.beat} 休 ${r.beats}');
    }
  }

  // ── 每声部每小节拍长闭合:事件槽与 4/4 小节线严丝合缝。同拍多音
  // (和弦堆)是同一时值槽,槽时值 = 组内最大跨度;槽内音休混杂、多
  // 休止同槽、后槽起点落进前槽内才是转录缺陷。──
  final slots = <double, _IrSlot>{};
  void addSlot(double start, double end, bool isNote, String what) {
    final slot = slots[start];
    if (slot == null) {
      slots[start] = _IrSlot()..add(end, what, isNote);
      return;
    }
    final clash = isNote ? slot.hasRest : slot.hasRest || slot.hasNote;
    if (clash) err('$name 声部同拍事件重叠:$what 与 ${slot.label}');
    slot.add(end, what, isNote);
  }

  for (final n in voice.notes) {
    addSlot(n.beat, n.beat + n.durationBeats, true, '音@${n.beat}');
  }
  for (final r in voice.rests) {
    addSlot(r.beat, r.beat + r.beats, false, '休止@${r.beat}');
  }
  if (slots.isEmpty) return;
  final firstStart = slots.keys.reduce((a, b) => a < b ? a : b) + shift;
  final lastEnd =
      slots.values.map((s) => s.end).reduce((a, b) => a > b ? a : b) + shift;
  if (lastEnd > gridEnd + 1e-9) {
    err('$name 声部事件超出小节骨架(层内末尾 @${lastEnd - shift},'
        '主轴骨架到拍 $gridEnd)');
  }
  final bar = beatsPerMeasure.toDouble();
  final firstM = (firstStart / bar).floor();
  final lastM = ((lastEnd - 1e-9) / bar).floor();
  for (var mi = firstM; mi <= lastM && mi < (gridEnd / bar).ceil(); mi++) {
    final ms = mi * bar;
    final me = ms + bar;
    final starts =
        slots.keys.where((s) => s + shift >= ms && s + shift < me).toList()
          ..sort();
    if (starts.isEmpty) {
      err('$name 声部第 ${mi + 1} 小节无任何事件,拍长不闭合');
      continue;
    }
    var cursor = mi == firstM ? firstStart : ms;
    for (final s in starts) {
      final start = s + shift;
      final end = slots[s]!.end + shift;
      if (start < cursor - 1e-9) {
        err('$name 声部第 ${mi + 1} 小节事件重叠:槽@$s 落在前槽内');
      } else if (start > cursor + 1e-9) {
        err('$name 声部第 ${mi + 1} 小节拍位空洞(@$s 前缺 '
            '${_beats(start - cursor)} 拍),拍长不闭合');
      }
      if (end > me + 1e-9) {
        err('$name 声部第 ${mi + 1} 小节事件跨小节:槽@$s 延到 @${end - shift}');
      }
      cursor = end > cursor ? end : cursor;
    }
    if (cursor < me - 1e-9) {
      err('$name 声部第 ${mi + 1} 小节末尾缺 ${_beats(me - cursor)} 拍,拍长不闭合');
    }
  }
}

String _beats(double v) =>
    v == v.truncateToDouble() ? v.truncate().toString() : '$v';

/// 闭合核算的事件槽:同起点的一组音(和弦堆)或一个休止。
class _IrSlot {
  bool hasNote = false;
  bool hasRest = false;
  double end = 0;
  String label = '';

  void add(double slotEnd, String what, bool isNote) {
    hasNote = hasNote || isNote;
    hasRest = hasRest || !isNote;
    label = what;
    if (slotEnd > end) end = slotEnd;
  }
}

/// 事件表通用核对:拍位界内 + 严格升序([what] 点名事件种类;运行时
/// ScoreSheetDef 各事件表的「严格按拍位升序」契约在源端前移执行)。
void _checkAscendingInBounds(
  List<double> beats,
  String what,
  double gridEnd,
  void Function(String) err,
) {
  for (var i = 0; i < beats.length; i++) {
    if (beats[i] < 0 || beats[i] >= gridEnd) {
      err('$what 拍位超出小节骨架:@${beats[i]}');
    }
    if (i > 0 && beats[i] <= beats[i - 1]) {
      err('$what 拍位须严格升序:@${beats[i]}');
    }
  }
}

void _validateChordAnchors(
  List<ScoreIrChordAnchor> anchors,
  double gridEnd,
  void Function(String) err,
) {
  for (final a in anchors) {
    if (a.label.trim().isEmpty) err('和弦锚 label 为空:@${a.beat}');
    if (a.fingering.frets.length != 4 || a.fingering.fingers.length != 4) {
      err('和弦锚指形 frets/fingers 须各 4 项:@${a.beat} ${a.label}');
    } else if (a.fingering.frets.any((f) => f < -1)) {
      err('和弦锚指形 frets 须 ≥ -1(× 闷音):@${a.beat} ${a.label}');
    }
    if (a.fingering.baseFret < 1) {
      err('和弦锚指形 baseFret 须 ≥ 1:@${a.beat} ${a.label}');
    }
    if (a.fingering.barres.any((b) => b < 1)) {
      err('和弦锚指形 barres 须 ≥ 1:@${a.beat} ${a.label}');
    }
  }
  _checkAscendingInBounds(
      [for (final a in anchors) a.beat], '和弦锚', gridEnd, err);
}

void _validateSlides(
  List<ScoreIrSlideEvent> slides,
  ScoreIrVoice accompaniment,
  double gridEnd,
  void Function(String) err,
) {
  for (final s in slides) {
    if (s.fromBeat >= s.toBeat) {
      err('滑音方向非法(fromBeat 须先于 toBeat):'
          '@${s.fromBeat} → ${s.toBeat}');
    }
    if (s.toBeat < 0 || s.toBeat >= gridEnd) {
      err('滑音拍位超出小节骨架:@${s.fromBeat} → ${s.toBeat}');
    }
    if (!accompaniment.notes.any((n) => n.beat == s.fromBeat)) {
      err('滑音起点无音(须落在伴奏声部):@${s.fromBeat}');
    }
    if (!accompaniment.notes.any((n) => n.beat == s.toBeat)) {
      err('滑音终点无音(须落在伴奏声部):@${s.toBeat}');
    }
  }
  _checkAscendingInBounds(
      [for (final s in slides) s.fromBeat], '滑音', gridEnd, err);
}
