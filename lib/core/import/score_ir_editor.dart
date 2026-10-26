/// 识谱源单音微调编辑器(工单 45,ADR-0009「物化器是纯函数」的另一半):
/// App 内轻改 = 改源再物化,本库只改 [ScoreIr] 数据,物化/校验原样复用
/// ——编辑结果永远要过 [validateScoreIr] 全绿才准落库(会话层把关,
/// 见 features/play/score_ir_edit_session.dart)。
///
/// 微移语义 = 「槽尾锚定,前槽跟随」。识谱源的声部是拍长闭合的事件槽
/// 链(每小节严丝合缝,校验器契约),单动一个音的拍位必然在链上开洞
/// 或重叠——所以微移不是自由改 beat,而是链上换位:
/// - 音槽终点不动(与后槽的接缝锚定);
/// - 音槽起点随音走(槽内同拍音堆整体走,时值同调);
/// - 前一事件槽(音堆或声部休止)的终点跟到新拍位(补上/让出空档)。
/// 闭合在两次微移间恒保持,约束只有三条:右移不得吃光本槽时值;压
/// 小节线的音不可把前槽拽过线;左移不得越出当小节、不得吃光前槽。
/// 限界由 [scoreIrShiftLimits] 给出(UI 据此禁按钮),越界当场拒。
///
/// 删除语义:堆内删除 = 余音填满原槽;独槽删除 = 空档由相邻槽吞下
/// (前槽在同小节则前槽延长,否则后槽回拉)——谱面视图的节奏杆由拍位
/// 推导,删除后视觉上就是「这个音没了」,不出现空洞。滑音端点等事件
/// 表引用本编辑器不碰:删了端点音校验器会拦「滑音起点无音」,由会话
/// 层堵门,不静默修。
library;

import '../model/uke_string.dart';
import 'score_ir.dart';
import 'score_ir_validator.dart';

/// 声部别(编辑定位用):旋律层拍位是层内本地拍,伴奏层是主轴拍。
enum ScoreIrVoiceKind { melody, accompaniment }

/// 一个被编辑音的引用:(弦, 拍) 在声部内唯一(校验器禁同弦同刻),
/// 三元组即身份,不依赖列表序。
class ScoreIrNoteRef {
  const ScoreIrNoteRef({
    required this.voice,
    required this.string,
    required this.beat,
  });

  final ScoreIrVoiceKind voice;
  final int string;
  final double beat;

  @override
  bool operator ==(Object other) =>
      other is ScoreIrNoteRef &&
      voice == other.voice &&
      string == other.string &&
      beat == other.beat;

  @override
  int get hashCode => Object.hash(voice, string, beat);

  @override
  String toString() => '$voice 弦$string @$beat';
}

/// 单音微调操作(工单 45 面板的三类动作)。
sealed class ScoreIrNoteEdit {
  const ScoreIrNoteEdit();

  /// 操作目标。
  ScoreIrNoteRef get ref;
}

/// 换弦/品:落新弦新品,midi 现算(冗余校验字段随弦品走)。
class ScoreIrReFret extends ScoreIrNoteEdit {
  const ScoreIrReFret({
    required this.ref,
    required this.string,
    required this.fret,
  });

  @override
  final ScoreIrNoteRef ref;
  final int string;
  final int fret;
}

/// 拍位微移:[delta] 有符号拍数(面板步进 ±0.25/±0.5),受
/// [scoreIrShiftLimits] 约束,越界抛 [ArgumentError]。
class ScoreIrShift extends ScoreIrNoteEdit {
  const ScoreIrShift({required this.ref, required this.delta});

  @override
  final ScoreIrNoteRef ref;
  final double delta;
}

/// 删除该音(堆内删单音,独槽删除带槽补位)。
class ScoreIrDelete extends ScoreIrNoteEdit {
  const ScoreIrDelete({required this.ref});

  @override
  final ScoreIrNoteRef ref;
}

/// 应用一次编辑:返回新 [ScoreIr](纯函数,入参不改写)。
/// [ir] 应是已过校验的源(会话层只喂 Ready 谱);引用不存在、越界、
/// 删空声部等违约当场抛 [ArgumentError]——面板按限界先行禁用,这里
/// 是最后一道闸。
ScoreIr applyScoreIrNoteEdit(ScoreIr ir, ScoreIrNoteEdit edit) {
  final voice = _voiceOf(ir, edit.ref.voice);
  final index = _indexOf(voice, edit.ref);
  if (index < 0) {
    throw ArgumentError('编辑引用的音不存在:${edit.ref}');
  }
  return switch (edit) {
    ScoreIrReFret(:final string, :final fret) => _copyWithVoice(
      ir,
      edit.ref.voice,
      _reFret(voice, index, string, fret),
    ),
    ScoreIrShift(:final delta) => _copyWithVoice(
      ir,
      edit.ref.voice,
      _shift(
        voice,
        index,
        delta,
        _shiftBounds(ir, voice, index, edit.ref.voice),
      ),
    ),
    ScoreIrDelete() => _copyWithVoice(
      ir,
      edit.ref.voice,
      _delete(ir, voice, index, edit.ref.voice),
    ),
  };
}

/// 拍位微移限界(拍,严格界:|δ| 须小于界值;0 = 不可移)。
/// 左受「当小节起点 + 前槽余量」收,右受「本槽时值 + 压线不可拽前槽
/// 跨线」收——推导见文件头。
({double left, double right}) scoreIrShiftLimits(
  ScoreIr ir,
  ScoreIrNoteRef ref,
) {
  final voice = _voiceOf(ir, ref.voice);
  final index = _indexOf(voice, ref);
  if (index < 0) {
    throw ArgumentError('限界引用的音不存在:$ref');
  }
  return _shiftBounds(ir, voice, index, ref.voice);
}

// ── 内核:槽结构上的三种操作 ────────────────────────────────────────

ScoreIrVoice _voiceOf(ScoreIr ir, ScoreIrVoiceKind kind) =>
    kind == ScoreIrVoiceKind.melody ? ir.melody : ir.accompaniment;

int _indexOf(ScoreIrVoice voice, ScoreIrNoteRef ref) =>
    voice.notes.indexWhere((n) => n.string == ref.string && n.beat == ref.beat);

ScoreIr _copyWithVoice(ScoreIr ir, ScoreIrVoiceKind kind, ScoreIrVoice voice) =>
    ScoreIr(
      schemaVersion: ir.schemaVersion,
      id: ir.id,
      title: ir.title,
      artist: ir.artist,
      meter: ir.meter,
      tempoMap: ir.tempoMap,
      keyMap: ir.keyMap,
      measures: ir.measures,
      melodyAlignBeats: ir.melodyAlignBeats,
      tabChartId: ir.tabChartId,
      melodyChartId: ir.melodyChartId,
      melody: kind == ScoreIrVoiceKind.melody ? voice : ir.melody,
      accompaniment: kind == ScoreIrVoiceKind.melody ? ir.accompaniment : voice,
      rests: ir.rests,
      slides: ir.slides,
      tremolos: ir.tremolos,
      strums: ir.strums,
      chordAnchors: ir.chordAnchors,
      unsupportedSymbols: ir.unsupportedSymbols,
      review: ir.review,
    );

ScoreIrVoice _reFret(ScoreIrVoice voice, int index, int string, int fret) {
  if (string < 1 || string > UkeString.values.length) {
    throw ArgumentError('弦号越界(1..${UkeString.values.length}):$string');
  }
  if (fret < 0 || fret > scoreIrMaxFret) {
    throw ArgumentError('品位越界(0..$scoreIrMaxFret):$fret');
  }
  final notes = _patchNotes(voice.notes, {
    index: (n) => _reNote(
      n,
      string: string,
      fret: fret,
      midi: UkeString.byNumber(string).midi + fret,
    ),
  });
  return ScoreIrVoice(notes: notes, rests: voice.rests);
}

/// 拍位微移(限界已核,越界抛 [ArgumentError])。
ScoreIrVoice _shift(
  ScoreIrVoice voice,
  int index,
  double delta,
  ({double left, double right}) bounds,
) {
  final overRight = delta > 1e-9 && delta >= bounds.right - 1e-9;
  final overLeft = delta < -1e-9 && -delta >= bounds.left - 1e-9;
  if (overRight || overLeft) {
    throw ArgumentError(
      '微移越界:δ$delta 超限(左 ${bounds.left} / 右 ${bounds.right})',
    );
  }
  final slots = _buildSlots(voice);
  final note = voice.notes[index];
  final slot = slots.singleWhere((s) => s.start == note.beat);
  final prev = _neighbor(slots, slot, before: true);
  final newBeat = note.beat + delta;

  final patches = <int, ScoreIrNote Function(ScoreIrNote)>{};
  // 前槽终点跟到新拍位(音堆逐音调时值,休止调 beats)。
  if (prev != null) {
    final grow = newBeat - prev.end;
    for (final i in prev.noteIndexes) {
      patches[i] = (n) => _reNote(n, durationBeats: n.durationBeats + grow);
    }
  }
  // 本槽:起点随音走,终点锚定(时值 −δ)。
  for (final i in slot.noteIndexes) {
    patches[i] = (n) =>
        _reNote(n, beat: newBeat, durationBeats: n.durationBeats - delta);
  }
  final notes = _patchNotes(voice.notes, patches);
  final rests = prev?.rest == null
      ? voice.rests
      : _patchRests(voice.rests, {
          for (var i = 0; i < voice.rests.length; i++)
            if (voice.rests[i].beat == prev!.start)
              i: (r) => ScoreIrRest(
                beat: r.beat,
                beats: r.beats + (newBeat - prev.end),
                evidence: r.evidence,
              ),
        });
  return ScoreIrVoice(notes: _resort(notes), rests: rests);
}

ScoreIrVoice _delete(
  ScoreIr ir,
  ScoreIrVoice voice,
  int index,
  ScoreIrVoiceKind kind,
) {
  final shift = kind == ScoreIrVoiceKind.melody ? ir.melodyAlignBeats : 0.0;
  final bar = ir.meter.beatsPerMeasure.toDouble();
  final note = voice.notes[index];
  final slots = _buildSlots(voice);
  final slot = slots.singleWhere((s) => s.start == note.beat);
  final prev = _neighbor(slots, slot, before: true);
  final next = _neighbor(slots, slot, before: false);

  final patches = <int, ScoreIrNote Function(ScoreIrNote)>{};
  var rests = voice.rests;
  var remove = true;

  if (slot.noteIndexes.length > 1) {
    // 堆内删除:余音填满原槽(槽尾锚定,闭合不变)。
    remove = false;
    for (final i in slot.noteIndexes) {
      if (i == index) continue;
      patches[i] = (n) => _reNote(n, durationBeats: slot.end - n.beat);
    }
  } else {
    final sameMeasure =
        prev != null &&
        ((prev.start + shift) ~/ bar) == ((note.beat + shift) ~/ bar);
    if (prev != null && sameMeasure) {
      // 前槽(同小节)吞下空档。
      final grow = slot.end - prev.end;
      for (final i in prev.noteIndexes) {
        patches[i] = (n) => _reNote(n, durationBeats: n.durationBeats + grow);
      }
      if (prev.rest != null) {
        rests = _patchRests(rests, {
          for (var i = 0; i < rests.length; i++)
            if (rests[i].beat == prev.start)
              i: (r) => ScoreIrRest(
                beat: r.beat,
                beats: r.beats + grow,
                evidence: r.evidence,
              ),
        });
      }
    } else if (next != null) {
      // 后槽(仅邻槽,更后者锚定不动)回拉到空档头
      // (前槽在上一小节或不存在时)。
      final pull = next.start - note.beat;
      for (final i in next.noteIndexes) {
        patches[i] = (n) => _reNote(
          n,
          beat: n.beat - pull,
          durationBeats: n.durationBeats + pull,
        );
      }
      if (next.rest != null) {
        rests = _patchRests(rests, {
          for (var i = 0; i < rests.length; i++)
            if (rests[i].beat == next.start)
              i: (r) => ScoreIrRest(
                beat: r.beat - pull,
                beats: r.beats + pull,
                evidence: r.evidence,
              ),
        });
      }
    } else {
      throw ArgumentError('声部末音不可删除(删则声部空):$note');
    }
  }
  final notes = <ScoreIrNote>[];
  for (var i = 0; i < voice.notes.length; i++) {
    if (i == index && remove) continue;
    final patched = patches[i]?.call(voice.notes[i]) ?? voice.notes[i];
    if (i == index) continue; // 堆内删除:目标音直接出局。
    notes.add(patched);
  }
  return ScoreIrVoice(notes: _resort(notes), rests: rests);
}

// ── 槽结构:同拍音堆为一槽,声部休止自成一槽;按起点升序。──

class _Slot {
  _Slot({
    required this.start,
    required this.end,
    required this.minDuration,
    required this.noteIndexes,
    this.rest,
  });

  final double start;

  /// 槽尾(max(音起点+时值) 或 休止起点+beats)。构建期累加,建成后只读。
  double end;

  /// 槽内最短事件时长(收缩限界用;休止即其 beats)。同上构建期累加。
  double minDuration;
  final List<int> noteIndexes;

  /// 非空 = 休止槽(此时 [noteIndexes] 为空)。
  final ScoreIrRest? rest;
}

List<_Slot> _buildSlots(ScoreIrVoice voice) {
  final slots = <_Slot>[];
  final byBeat = <double, _Slot>{};
  for (var i = 0; i < voice.notes.length; i++) {
    final n = voice.notes[i];
    final end = n.beat + n.durationBeats;
    final slot = byBeat[n.beat];
    if (slot == null) {
      byBeat[n.beat] = _Slot(
        start: n.beat,
        end: end,
        minDuration: n.durationBeats,
        noteIndexes: [i],
      );
    } else {
      slot.noteIndexes.add(i);
      if (end > slot.end) slot.end = end; // 槽尾 = 堆内最大跨度。
      if (n.durationBeats < slot.minDuration) {
        slot.minDuration = n.durationBeats;
      }
    }
  }
  slots.addAll(byBeat.values);
  for (final r in voice.rests) {
    slots.add(
      _Slot(
        start: r.beat,
        end: r.beat + r.beats,
        minDuration: r.beats,
        noteIndexes: const [],
        rest: r,
      ),
    );
  }
  slots.sort((a, b) => a.start.compareTo(b.start));
  return slots;
}

_Slot? _neighbor(List<_Slot> slots, _Slot slot, {required bool before}) {
  final i = slots.indexOf(slot);
  final j = before ? i - 1 : i + 1;
  return j >= 0 && j < slots.length ? slots[j] : null;
}

/// 微移限界核算(伴奏 shift=0,旋律 shift=melodyAlignBeats)。
({double left, double right}) _shiftBounds(
  ScoreIr ir,
  ScoreIrVoice voice,
  int index,
  ScoreIrVoiceKind kind,
) {
  final shift = kind == ScoreIrVoiceKind.melody ? ir.melodyAlignBeats : 0.0;
  final bar = ir.meter.beatsPerMeasure.toDouble();
  final note = voice.notes[index];
  final slots = _buildSlots(voice);
  final slot = slots.singleWhere((s) => s.start == note.beat);
  final prev = _neighbor(slots, slot, before: true);

  final mainBeat = note.beat + shift;
  final barStart = (mainBeat ~/ bar) * bar; // 当小节头(主轴)。
  // 左界:不越当小节头(层内本地拍;主轴头在层内为负时取 0)。
  final floorLocal = (barStart - shift < 0) ? 0.0 : barStart - shift;
  var left = note.beat - floorLocal;
  if (prev != null && left > prev.minDuration) left = prev.minDuration;
  // 右界:本槽时值;压小节线的音不可把前槽拽过线。
  var right = slot.minDuration;
  if (prev != null && mainBeat - barStart < 1e-9) right = 0;
  return (left: left, right: right);
}

// ── 小帮手:不可变补丁式重建。──

ScoreIrNote _reNote(
  ScoreIrNote n, {
  double? beat,
  double? durationBeats,
  int? string,
  int? fret,
  int? midi,
}) => ScoreIrNote(
  beat: beat ?? n.beat,
  durationBeats: durationBeats ?? n.durationBeats,
  string: string ?? n.string,
  fret: fret ?? n.fret,
  midi: midi ?? n.midi,
  lyric: n.lyric,
  evidence: n.evidence,
);

List<ScoreIrNote> _patchNotes(
  List<ScoreIrNote> notes,
  Map<int, ScoreIrNote Function(ScoreIrNote)> patches,
) => [
  for (var i = 0; i < notes.length; i++)
    patches.containsKey(i) ? patches[i]!(notes[i]) : notes[i],
];

List<ScoreIrRest> _patchRests(
  List<ScoreIrRest> rests,
  Map<int, ScoreIrRest Function(ScoreIrRest)> patches,
) => [
  for (var i = 0; i < rests.length; i++)
    patches.containsKey(i) ? patches[i]!(rests[i]) : rests[i],
];

/// 录入序修复:拍位升序、同拍保持原录入序(sortedTabNotes 同款复合键
/// ——List.sort 不保证稳定,契约显式进键)。
List<ScoreIrNote> _resort(List<ScoreIrNote> notes) {
  final indexed = [for (var (i, note) in notes.indexed) (i: i, note: note)];
  indexed.sort((a, b) {
    final byBeat = a.note.beat.compareTo(b.note.beat);
    return byBeat != 0 ? byBeat : a.i.compareTo(b.i);
  });
  return [for (final entry in indexed) entry.note];
}
