import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/import/score_ir.dart';
import 'package:ukeflow/core/import/score_ir_editor.dart';
import 'package:ukeflow/core/import/score_ir_validator.dart';

import '../../helpers/score_ir_fixtures.dart';

/// 工单 45 编辑器(纯函数缝):单音微调三操作——换弦品/拍位微移/删除。
/// 微移语义 = 「槽尾锚定,前槽跟随」:音槽的终点不动、起点随音走、
/// 前一事件槽(音堆或声部休止)的终点跟到新拍位——拍长闭合在两次
/// 微移间保持,任何结果都须过 [validateScoreIr] 全绿。
void main() {
  group('换弦品', () {
    test('改弦/品并现算 midi,其余字段与原 IR 不动', () {
      final ir = validTinyIr();
      final edited = applyScoreIrNoteEdit(
        ir,
        const ScoreIrReFret(
          ref: ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.melody,
            string: 2,
            beat: 0,
          ),
          string: 1,
          fret: 5,
        ),
      );
      // ①弦 5 品 = A4(69) + 5 = 74。
      final note = edited.melody.notes.singleWhere((n) => n.beat == 0);
      expect(note.string, 1);
      expect(note.fret, 5);
      expect(note.midi, 74);
      // 其余字段原样(夹具该音带 lyric 与 evidence)。
      expect(note.durationBeats, 1);
      expect(note.lyric, '你');
      expect(note.evidence, isNotNull);
      expectVoiceEqual(edited.accompaniment, ir.accompaniment, 'accompaniment');
      // 纯函数:输入 IR 不被改写。
      expect(ir.melody.notes.first.string, 2);
      expect(ir.melody.notes.first.fret, 3);
      expect(ir.melody.notes.first.midi, 67);
    });

    test('空弦品 midi 照 UkeString(③弦 0 品 = C4=60),校验全绿', () {
      final edited = applyScoreIrNoteEdit(
        validTinyIr(),
        const ScoreIrReFret(
          ref: ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.melody,
            string: 2,
            beat: 1,
          ),
          string: 3,
          fret: 0,
        ),
      );
      final note = edited.melody.notes.singleWhere((n) => n.beat == 1);
      expect(note.midi, 60);
      expect(validateScoreIr(edited), isEmpty);
    });

    test('弦/品出界当场拒(ArgumentError,不过 UI 手)', () {
      final ir = validTinyIr();
      const ref = ScoreIrNoteRef(
        voice: ScoreIrVoiceKind.melody,
        string: 2,
        beat: 0,
      );
      expect(
        () => applyScoreIrNoteEdit(
          ir,
          const ScoreIrReFret(ref: ref, string: 5, fret: 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => applyScoreIrNoteEdit(
          ir,
          const ScoreIrReFret(ref: ref, string: 2, fret: scoreIrMaxFret + 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('拍位微移(伴奏层)', () {
    test('右移:音走槽走,前槽(音)补位,槽尾锚定,校验全绿', () {
      // 夹具 validTinyIr 伴奏两音都是滑音端点(移哪个都被滑音校验拦,
      // 滑音纠缠归「删滑音端点音」用例),伴奏微移换 _threeBarIr 验。
      final edited = applyScoreIrNoteEdit(
        _threeBarIr(),
        const ScoreIrShift(
          ref: ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.accompaniment,
            string: 3,
            beat: 6,
          ),
          delta: 0.5,
        ),
      );
      // 三小节源伴奏 @6(2) 右移 0.5:@6.5(1.5),前音 @4 补到 2.5,
      // 槽尾 8 锚定,后休止 @8 不动。
      expect(validateScoreIr(edited), isEmpty);
      final moved = edited.accompaniment.notes.singleWhere(
        (n) => n.beat == 6.5,
      );
      expect(moved.durationBeats, 1.5);
      expect(moved.string, 3);
      final prev = edited.accompaniment.notes.singleWhere((n) => n.beat == 4);
      expect(prev.durationBeats, 2.5);
      expect(edited.accompaniment.rests.last.beat, 8);
      expect(edited.accompaniment.rests.last.beats, 4);
    });

    test('左移:前槽收缩,本音时值加长补足,槽尾锚定,校验全绿', () {
      final edited = applyScoreIrNoteEdit(
        validTinyIr(),
        const ScoreIrShift(
          ref: ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.melody,
            string: 1,
            beat: 1.5,
          ),
          delta: -0.25,
        ),
      );
      // 夹具旋律:@0(1) @1(0.5) @1.5(0.5) 休止@2(2)。左移后 @1.25(0.75),
      // 前音 @1 收到 0.25,槽尾 2 不动。
      expect(validateScoreIr(edited), isEmpty);
      final moved = edited.melody.notes.singleWhere((n) => n.beat == 1.25);
      expect(moved.durationBeats, 0.75);
      expect(
        edited.melody.notes.singleWhere((n) => n.beat == 1).durationBeats,
        0.25,
      );
    });

    test('微移限界:左受前槽余量与当小节起点收,右受本槽时值收', () {
      final ir = validTinyIr();
      // 伴奏 @5:右限 = 本槽时值 0.5(槽尾 5.5 锚定);左限 = min(前音余量
      // 1, 当小节内 5−4=1) = 1。
      expect(
        scoreIrShiftLimits(
          ir,
          const ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.accompaniment,
            string: 3,
            beat: 5,
          ),
        ),
        (left: 1.0, right: 0.5),
      );
      // 旋律层拍位是层内本地拍:melodyAlignBeats=4,@0 的主轴拍 4 即
      // 第 2 小节头——左移出小节不可,左限 0。
      expect(
        scoreIrShiftLimits(
          ir,
          const ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.melody,
            string: 2,
            beat: 0,
          ),
        ),
        (left: 0.0, right: 1.0),
      );
    });

    test('小节线双禁:线上音右移压前槽跨线不可,左移出线不可', () {
      // 自编三小节源:伴奏 @0(2)+休止@2(2) | @4(2) @6(2) | 休止@8(4)。
      // @4 在小节线上且带前槽(休止@2):右移须前槽补位,前槽跨线即坏,
      // 右限 0;左限 0(当小节起点)。@6 左限 = min(前音余量 2, 小节内
      // 偏移 2) = 2,右限 = 本槽时值 2。
      final ir = _threeBarIr();
      expect(
        scoreIrShiftLimits(
          ir,
          const ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.accompaniment,
            string: 4,
            beat: 4,
          ),
        ),
        (left: 0.0, right: 0.0),
      );
      // @6 左移受前音 @4 余量(2)与当小节内偏移(6−4=2)= 2。
      expect(
        scoreIrShiftLimits(
          ir,
          const ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.accompaniment,
            string: 3,
            beat: 6,
          ),
        ),
        (left: 2.0, right: 2.0),
      );
    });

    test('压线音右移不可(前槽跨线),限界为 0', () {
      // 伴奏 @0(4) | @4(2) @6(2):@4 在线上且有前槽——右移要前槽补位,
      // 前槽一跨线即坏,右限 0。
      final ir = _crossBarIr();
      expect(
        scoreIrShiftLimits(
          ir,
          const ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.accompaniment,
            string: 4,
            beat: 4,
          ),
        ),
        (left: 0.0, right: 0.0),
      );
    });

    test('超限微移当场拒(ArgumentError)', () {
      final ir = _threeBarIr();
      expect(
        () => applyScoreIrNoteEdit(
          ir,
          const ScoreIrShift(
            ref: ScoreIrNoteRef(
              voice: ScoreIrVoiceKind.accompaniment,
              string: 3,
              beat: 6,
            ),
            delta: 2.5,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('同拍音堆整体微移:堆内各音同走,时值同调,校验全绿', () {
      final edited = applyScoreIrNoteEdit(
        _stackIr(),
        const ScoreIrShift(
          ref: ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.melody,
            string: 2,
            beat: 0,
          ),
          delta: 0.25,
        ),
      );
      expect(validateScoreIr(edited), isEmpty);
      final stack = edited.melody.notes.where((n) => n.beat == 0.25).toList();
      expect(stack.length, 2);
      // 时值同调(各 −δ),堆内相对形状保持。
      expect({for (final n in stack) n.durationBeats}, {0.75, 0.25});
    });
  });

  group('删除', () {
    test('独槽删除:前槽(同小节)补位吞下空档,校验全绿', () {
      final edited = applyScoreIrNoteEdit(
        validTinyIr(),
        const ScoreIrDelete(
          ref: ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.melody,
            string: 1,
            beat: 1.5,
          ),
        ),
      );
      // 夹具旋律 @1.5(0.5) 独槽 [1.5,2):删后前音 @1 由 0.5 补到 1.0。
      expect(validateScoreIr(edited), isEmpty);
      expect(edited.melody.notes.length, 2);
      expect(
        edited.melody.notes.singleWhere((n) => n.beat == 1).durationBeats,
        1.0,
      );
      expect(edited.melody.rests.single.beat, 2);
    });

    test('堆内删除:同堆余音填满原槽,槽尾锚定,校验全绿', () {
      final edited = applyScoreIrNoteEdit(
        _stackIr(),
        const ScoreIrDelete(
          ref: ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.melody,
            string: 1,
            beat: 0,
          ),
        ),
      );
      // 删的是堆内长音(时值 1):余音 ②弦0.5 补满到槽尾 1.0。
      expect(validateScoreIr(edited), isEmpty);
      expect(edited.melody.notes.length, 2);
      expect(edited.melody.notes.first.durationBeats, 1.0);
    });

    test('小节头删除且前槽在上一小节:后槽回拉吞位,校验全绿', () {
      final edited = applyScoreIrNoteEdit(
        _threeBarIr(),
        const ScoreIrDelete(
          ref: ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.accompaniment,
            string: 4,
            beat: 4,
          ),
        ),
      );
      // 三小节源:| @0(2) 休止@2(2) | @4(2) @6(2) | 休止@8(4) |。删 @4
      // (第 2 小节头,前槽是上一小节的休止):后音 @6 回拉到 @4,时值
      // 2→4 吞满 [4,8)。
      expect(validateScoreIr(edited), isEmpty);
      final pulled = edited.accompaniment.notes.singleWhere((n) => n.beat == 4);
      expect(pulled.string, 3);
      expect(pulled.durationBeats, 4);
      expect(edited.accompaniment.notes.length, 2);
    });

    test('声部末音不可删(删则声部空,ArgumentError)', () {
      // _threeBarIr 旋律是单音单槽声部。
      final ir = _threeBarIr();
      expect(
        () => applyScoreIrNoteEdit(
          ir,
          const ScoreIrDelete(
            ref: ScoreIrNoteRef(
              voice: ScoreIrVoiceKind.melody,
              string: 1,
              beat: 0,
            ),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('删滑音端点音不静默修滑音:校验器拦,由会话层堵门', () {
      final edited = applyScoreIrNoteEdit(
        validTinyIr(),
        const ScoreIrDelete(
          ref: ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.accompaniment,
            string: 4,
            beat: 4,
          ),
        ),
      );
      // 夹具滑音 fromBeat=4:音删了滑音还在——编辑器不碰事件表,
      // validateScoreIr 报「滑音起点无音」,落库由会话层校验挡下。
      expect(validateScoreIr(edited), isNotEmpty);
    });
  });

  test('引用不存在的音当场拒(ArgumentError)', () {
    final ir = validTinyIr();
    expect(
      () => applyScoreIrNoteEdit(
        ir,
        const ScoreIrReFret(
          ref: ScoreIrNoteRef(
            voice: ScoreIrVoiceKind.accompaniment,
            string: 4,
            beat: 99,
          ),
          string: 1,
          fret: 0,
        ),
      ),
      throwsArgumentError,
    );
  });
}

/// 三小节伴奏源( melodyAlignBeats=4,旋律占第 1 小节):
/// 伴奏 | @0(2) 休止@2(2) | @4(2) @6(2) | 休止@8(4) |,4/4 拍长闭合。
ScoreIr _threeBarIr() => ScoreIr(
  schemaVersion: scoreIrSchemaVersion,
  id: 'test-three-bar',
  title: '三小节测试谱',
  meter: const ScoreIrMeter(beatsPerMeasure: 4, beatUnit: 4),
  tempoMap: const [ScoreIrTempoChange(beat: 0, bpm: 80)],
  keyMap: const [ScoreIrKeyChange(beat: 0, key: '1=C')],
  measures: const [
    ScoreIrMeasure(number: 1, startBeat: 0),
    ScoreIrMeasure(number: 2, startBeat: 4),
    ScoreIrMeasure(number: 3, startBeat: 8),
  ],
  melodyAlignBeats: 0,
  tabChartId: 'test-three-bar',
  melodyChartId: 'test-three-bar-melody',
  melody: const ScoreIrVoice(
    notes: [
      ScoreIrNote(beat: 0, durationBeats: 4, string: 1, fret: 0, midi: 69),
    ],
  ),
  accompaniment: ScoreIrVoice(
    notes: const [
      ScoreIrNote(beat: 0, durationBeats: 2, string: 4, fret: 0, midi: 67),
      ScoreIrNote(beat: 4, durationBeats: 2, string: 4, fret: 2, midi: 69),
      ScoreIrNote(beat: 6, durationBeats: 2, string: 3, fret: 0, midi: 60),
    ],
    rests: const [
      ScoreIrRest(beat: 2, beats: 2),
      ScoreIrRest(beat: 8, beats: 4),
    ],
  ),
);

/// 压线场景:伴奏 | @0(4) | @4(2) @6(2) |,首小节整小节长音,
/// @4 是小节头且带前槽——右移须前槽补位,前槽跨线即坏。
ScoreIr _crossBarIr() => ScoreIr(
  schemaVersion: scoreIrSchemaVersion,
  id: 'test-cross-bar',
  title: '压线测试谱',
  meter: const ScoreIrMeter(beatsPerMeasure: 4, beatUnit: 4),
  tempoMap: const [ScoreIrTempoChange(beat: 0, bpm: 80)],
  keyMap: const [ScoreIrKeyChange(beat: 0, key: '1=C')],
  measures: const [
    ScoreIrMeasure(number: 1, startBeat: 0),
    ScoreIrMeasure(number: 2, startBeat: 4),
  ],
  melodyAlignBeats: 0,
  tabChartId: 'test-cross-bar',
  melodyChartId: 'test-cross-bar-melody',
  melody: const ScoreIrVoice(
    notes: [
      ScoreIrNote(beat: 0, durationBeats: 8, string: 1, fret: 0, midi: 69),
    ],
  ),
  accompaniment: const ScoreIrVoice(
    notes: [
      ScoreIrNote(beat: 0, durationBeats: 4, string: 4, fret: 0, midi: 67),
      ScoreIrNote(beat: 4, durationBeats: 2, string: 4, fret: 2, midi: 69),
      ScoreIrNote(beat: 6, durationBeats: 2, string: 3, fret: 0, midi: 60),
    ],
  ),
);

/// 同拍音堆源:旋律 @0 双音(①0.5 / ②1)+ @1(1),休止@2(2)。
ScoreIr _stackIr() => ScoreIr(
  schemaVersion: scoreIrSchemaVersion,
  id: 'test-stack',
  title: '音堆测试谱',
  meter: const ScoreIrMeter(beatsPerMeasure: 4, beatUnit: 4),
  tempoMap: const [ScoreIrTempoChange(beat: 0, bpm: 80)],
  keyMap: const [ScoreIrKeyChange(beat: 0, key: '1=C')],
  measures: const [
    ScoreIrMeasure(number: 1, startBeat: 0),
    ScoreIrMeasure(number: 2, startBeat: 4),
  ],
  melodyAlignBeats: 0,
  tabChartId: 'test-stack',
  melodyChartId: 'test-stack-melody',
  melody: const ScoreIrVoice(
    notes: [
      ScoreIrNote(beat: 0, durationBeats: 1, string: 2, fret: 0, midi: 64),
      ScoreIrNote(beat: 0, durationBeats: 0.5, string: 1, fret: 0, midi: 69),
      ScoreIrNote(beat: 1, durationBeats: 1, string: 1, fret: 2, midi: 71),
    ],
    rests: [ScoreIrRest(beat: 2, beats: 2)],
  ),
  accompaniment: const ScoreIrVoice(
    notes: [
      ScoreIrNote(beat: 4, durationBeats: 4, string: 4, fret: 0, midi: 67),
    ],
  ),
);
