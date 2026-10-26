import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/import/score_ir.dart';
import 'package:ukeflow/core/import/score_ir_editor.dart';
import 'package:ukeflow/core/import/score_ir_validator.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/imported_solo_charts_dao.dart';
import 'package:ukeflow/features/play/note_tune_panel.dart';
import 'package:ukeflow/features/play/score_ir_edit_session.dart';

import 'helpers/score_ir_fixtures.dart';

/// 工单 45 微调面板:点选音的工作副本 + 步进/微移限界预禁用 + 存回
/// 落库自动记 reviewedAt + 被拦错误亮在面板。真内存库落库
/// (closeStreamsSynchronously 收口 drift 流计时器,仓库纪律)。
void main() {
  late AppDatabase db;
  late ImportedSoloChartsDao dao;
  late int rowId;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    dao = db.importedSoloChartsDao;
    addTearDown(db.close);
    rowId = await dao.add(
      title: '面板谱',
      sourceJson: jsonEncode(validTinyIr().toJson()),
      schemaVersion: scoreIrSchemaVersion,
      reviewedAt: '2026-10-26T10:00:00.000',
    );
  });

  Future<void> pumpPanel(WidgetTester tester, ScoreIrNoteRef noteRef) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: NoteTunePanel(
              session: ScoreIrEditSession(dao, rowId: rowId),
              noteRef: noteRef,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // 载入源的 Future 落定
  }

  /// 弹层包 Scaffold:存回后的 pop 有 Navigator 可退。
  Future<void> pumpInSheet(WidgetTester tester, ScoreIrNoteRef noteRef) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => NoteTunePanel(
                      session: ScoreIrEditSession(dao, rowId: rowId),
                      noteRef: noteRef,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('载入选中音:弦/品/拍位初值照源显示', (tester) async {
    await pumpPanel(
      tester,
      const ScoreIrNoteRef(voice: ScoreIrVoiceKind.melody, string: 2, beat: 0),
    );
    // 夹具旋律 @0 = ②弦3品,主轴拍 0+4=第 2 小节头?melodyAlignBeats=4
    // → 第 2 小节 0 拍。
    expect(find.byKey(const Key('tune-string-value')), findsOneWidget);
    expect(find.text('②'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('第 2 小节 0 拍'), findsOneWidget);
  });

  testWidgets('改品存回:落库新源,reviewedAt 自动盖章', (tester) async {
    await pumpInSheet(
      tester,
      const ScoreIrNoteRef(voice: ScoreIrVoiceKind.melody, string: 2, beat: 0),
    );
    await tester.tap(find.byKey(const Key('tune-fret-plus')));
    await tester.pump();
    expect(find.byKey(const Key('tune-save')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tune-save')));
    await tester.pumpAndSettle();

    final row = (await dao.getAll()).single;
    final stored = ScoreIr.fromJson(
      jsonDecode(row.sourceJson) as Map<String, dynamic>,
    );
    final note = stored.melody.notes.singleWhere((n) => n.beat == 0);
    expect(note.fret, 4);
    expect(note.midi, 68, reason: 'midi 随品现算(②弦空弦 64 + 4)');
    expect(
      row.reviewedAt,
      isNot('2026-10-26T10:00:00.000'),
      reason: '轻改自动记 reviewedAt',
    );
    expect(stored.review?.reviewedAt, row.reviewedAt);
  });

  testWidgets('拍位微移:限界预禁用(小节头左移钮灰),+¼拍可存', (tester) async {
    // 旋律 @0 主轴拍 4(第 2 小节头):左移出小节不可 → −½/−¼钮禁用。
    await pumpInSheet(
      tester,
      const ScoreIrNoteRef(voice: ScoreIrVoiceKind.melody, string: 2, beat: 0),
    );
    final minusHalf = tester.widget<IconButton>(
      find.byKey(const Key('tune-beat-minus-half')),
    );
    expect(minusHalf.onPressed, isNull, reason: '小节头左移禁用');
    final plusQuarter = tester.widget<OutlinedButton>(
      find.byKey(const Key('tune-beat-plus-quarter')),
    );
    expect(plusQuarter.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('tune-beat-plus-quarter')));
    await tester.pump();
    expect(find.text('第 2 小节 0.25 拍'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tune-save')));
    await tester.pumpAndSettle();

    final stored = ScoreIr.fromJson(
      jsonDecode((await dao.getAll()).single.sourceJson)
          as Map<String, dynamic>,
    );
    // 微移语义:音到 @0.25,前音 @1 补位收紧,槽尾锚定。
    expect(stored.melody.notes.singleWhere((n) => n.beat == 0.25), isNotNull);
    expect(validateScoreIr(stored), isEmpty);
  });

  testWidgets('微移+换弦一起存:两步编辑落一个终态', (tester) async {
    // 夹具伴奏两音都是滑音端点(移哪个都被滑音校验拦),组合编辑换
    // 旋律 @1(②0,右限 0.5):+¼拍后改弦到 ③,一并存。
    await pumpInSheet(
      tester,
      const ScoreIrNoteRef(voice: ScoreIrVoiceKind.melody, string: 2, beat: 1),
    );
    await tester.tap(find.byKey(const Key('tune-beat-plus-quarter')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tune-string-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tune-save')));
    await tester.pumpAndSettle();

    final stored = ScoreIr.fromJson(
      jsonDecode((await dao.getAll()).single.sourceJson)
          as Map<String, dynamic>,
    );
    final moved = stored.melody.notes.singleWhere((n) => n.beat == 1.25);
    expect(moved.string, 3);
    expect(moved.fret, 0);
    expect(moved.midi, 60, reason: '③弦空弦 C4');
    expect(validateScoreIr(stored), isEmpty);
  });

  testWidgets('组合编辑半提交:微移落库后被拦,基线跟进重试只补后一步', (tester) async {
    // 音堆源:旋律 @1 同拍 ②0+①0。点选 ①0:+¼拍(音堆同移到 1.25,落库)
    // 后改弦到 ②——撞堆内 ②0@1.25,被拦;再改到 ③,重试只补换弦一步。
    final stackRow = await dao.add(
      title: '半提交谱',
      sourceJson: jsonEncode(
        ScoreIr(
          schemaVersion: scoreIrSchemaVersion,
          id: 'test-half-commit',
          title: '半提交测试谱',
          meter: const ScoreIrMeter(beatsPerMeasure: 4, beatUnit: 4),
          tempoMap: const [ScoreIrTempoChange(beat: 0, bpm: 80)],
          keyMap: const [ScoreIrKeyChange(beat: 0, key: '1=C')],
          measures: const [
            ScoreIrMeasure(number: 1, startBeat: 0),
            ScoreIrMeasure(number: 2, startBeat: 4),
          ],
          melodyAlignBeats: 0,
          tabChartId: 'test-half-commit',
          melodyChartId: 'test-half-commit-melody',
          melody: const ScoreIrVoice(
            notes: [
              ScoreIrNote(
                beat: 1,
                durationBeats: 1,
                string: 2,
                fret: 0,
                midi: 64,
              ),
              ScoreIrNote(
                beat: 1,
                durationBeats: 1,
                string: 1,
                fret: 0,
                midi: 69,
              ),
            ],
            rests: [ScoreIrRest(beat: 2, beats: 2)],
          ),
          accompaniment: const ScoreIrVoice(
            notes: [
              ScoreIrNote(
                beat: 4,
                durationBeats: 4,
                string: 4,
                fret: 0,
                midi: 67,
              ),
            ],
          ),
        ).toJson(),
      ),
      schemaVersion: scoreIrSchemaVersion,
      reviewedAt: '2026-10-26T10:00:00.000',
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => NoteTunePanel(
                      session: ScoreIrEditSession(dao, rowId: stackRow),
                      noteRef: const ScoreIrNoteRef(
                        voice: ScoreIrVoiceKind.melody,
                        string: 1,
                        beat: 1,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 第一步:+¼拍 + 改弦到 ② → 微移落库,换弦被同弦同刻拦下。
    await tester.tap(find.byKey(const Key('tune-beat-plus-quarter')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tune-string-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tune-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tune-errors')),
      findsOneWidget,
      reason: '换弦撞堆内 ②0@1.25,被拦',
    );

    // 第二步:改弦到 ③ 直接重试——只补换弦一步,不重放微移。
    await tester.tap(find.byKey(const Key('tune-string-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tune-save')));
    await tester.pumpAndSettle();

    final stored = ScoreIr.fromJson(
      jsonDecode(
            (await dao.getAll())
                .where((r) => r.id == stackRow)
                .single
                .sourceJson,
          )
          as Map<String, dynamic>,
    );
    final moved = stored.melody.notes.singleWhere((n) => n.string == 3);
    expect(moved.beat, 1.25, reason: '换弦落 ③(微移后的拍位)');
    expect(
      stored.melody.notes.singleWhere((n) => n.string == 2).beat,
      1.25,
      reason: '堆内 ②0 同移落定(第一步的微移)',
    );
    expect(validateScoreIr(stored), isEmpty);
  });

  testWidgets('被拦编辑:错误逐条亮在面板,行不动可重试', (tester) async {
    // 删滑音端点音(伴奏 @4 是夹具滑音 fromBeat)→ 校验器拦。
    await pumpInSheet(
      tester,
      const ScoreIrNoteRef(
        voice: ScoreIrVoiceKind.accompaniment,
        string: 4,
        beat: 4,
      ),
    );
    await tester.tap(find.byKey(const Key('tune-delete')));
    await tester.pumpAndSettle(); // 确认对话框
    await tester.tap(find.byKey(const Key('tune-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tune-errors')), findsOneWidget);
    expect(find.textContaining('滑音'), findsOneWidget);
    // 行不动,面板仍在(可改了重试)。
    final row = (await dao.getAll()).single;
    expect(row.reviewedAt, '2026-10-26T10:00:00.000');
    expect(find.byKey(const Key('note-tune-panel')), findsOneWidget);
  });
}
