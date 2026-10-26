import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/import/score_ir.dart';
import 'package:ukeflow/core/import/score_ir_editor.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/imported_solo_charts_dao.dart';
import 'package:ukeflow/features/play/score_ir_edit_session.dart';

import 'helpers/score_ir_fixtures.dart';

/// 工单 45 轻改会话:改 IR → 校验总闸 → 存回自动记 reviewedAt。
/// 真内存库(纯 Dart test,不走 widget 泵);重物化刷新由既有读出
/// 管线负责,本组只锁「存回什么、拦什么」。
void main() {
  late AppDatabase db;
  late ImportedSoloChartsDao dao;
  late ScoreIrEditSession session;
  late int rowId;
  late String originalJson;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.importedSoloChartsDao;
    addTearDown(db.close);
    originalJson = jsonEncode(validTinyIr().toJson());
    rowId = await dao.add(
      title: '我的独奏',
      sourceJson: originalJson,
      schemaVersion: scoreIrSchemaVersion,
      reviewedAt: '2026-10-26T10:00:00.000',
    );
    session = ScoreIrEditSession(dao, rowId: rowId);
  });

  test('load:现读现析出源 IR', () async {
    final ir = await session.load();
    expect(ir.id, 'test-tiny-solo');
    expect(ir.melody.notes.first.beat, 0);
  });

  test('合法编辑:存回新源,contentSha 变,reviewedAt 自动盖章(源内+行列)', () async {
    final outcome = await session.apply(
      const ScoreIrReFret(
        ref: ScoreIrNoteRef(voice: ScoreIrVoiceKind.melody, string: 2, beat: 0),
        string: 1,
        fret: 5,
      ),
    );
    expect(outcome, isA<ScoreIrEditSaved>());

    final row = (await dao.getAll()).single;
    expect(row.sourceJson, isNot(originalJson), reason: '源 JSON 已更新');
    expect(
      row.contentSha,
      ImportedSoloChartsDao.shaOf(row.sourceJson),
      reason: 'contentSha 随新源现算',
    );
    // 轻改自动记复核时刻:行列与源内 review 同步盖章,且不早于原值。
    expect(row.reviewedAt, isNot('2026-10-26T10:00:00.000'));
    final stored = ScoreIr.fromJson(
      jsonDecode(row.sourceJson) as Map<String, dynamic>,
    );
    expect(stored.review?.reviewedAt, row.reviewedAt, reason: '行列照录源内复核时刻');
    // 存回的 IR 真的改了那个音。
    final note = stored.melody.notes.singleWhere((n) => n.beat == 0);
    expect(note.string, 1);
    expect(note.fret, 5);
    expect(note.midi, 74);
    // 展示名不动(入库名覆盖纪律,轻改不碰)。
    expect(row.title, '我的独奏');
  });

  test('非法编辑(同弦同刻冲突):拦下逐条人话,行原样可重试', () async {
    // 同弦同刻冲突须同拍:换带音堆的源(②0 与 ①0 同拍 @1),把 ①0
    // 改到 ②弦0 即撞 ②0@1。
    final stacked = validTinyIr();
    final rowId2 = await dao.add(
      title: '音堆谱',
      sourceJson: jsonEncode(
        ScoreIr(
          schemaVersion: stacked.schemaVersion,
          id: stacked.id,
          title: stacked.title,
          artist: stacked.artist,
          meter: stacked.meter,
          tempoMap: stacked.tempoMap,
          keyMap: stacked.keyMap,
          measures: stacked.measures,
          melodyAlignBeats: stacked.melodyAlignBeats,
          tabChartId: stacked.tabChartId,
          melodyChartId: stacked.melodyChartId,
          melody: const ScoreIrVoice(
            notes: [
              ScoreIrNote(
                beat: 0,
                durationBeats: 1,
                string: 2,
                fret: 3,
                midi: 67,
              ),
              ScoreIrNote(
                beat: 1,
                durationBeats: 0.5,
                string: 2,
                fret: 0,
                midi: 64,
              ),
              ScoreIrNote(
                beat: 1,
                durationBeats: 0.5,
                string: 1,
                fret: 0,
                midi: 69,
              ),
            ],
            rests: [ScoreIrRest(beat: 1.5, beats: 2.5)],
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
          review: stacked.review,
        ).toJson(),
      ),
      schemaVersion: scoreIrSchemaVersion,
      reviewedAt: '2026-10-26T10:00:00.000',
    );
    final stackedSession = ScoreIrEditSession(dao, rowId: rowId2);
    final outcome = await stackedSession.apply(
      const ScoreIrReFret(
        ref: ScoreIrNoteRef(voice: ScoreIrVoiceKind.melody, string: 1, beat: 1),
        string: 2,
        fret: 0,
      ),
    );
    expect(outcome, isA<ScoreIrEditBlocked>());
    final errors = (outcome as ScoreIrEditBlocked).errors;
    expect(errors, isNotEmpty);
    expect(errors.join(), contains('同弦同刻'));

    final row = (await dao.getAll()).where((r) => r.id == rowId2).single;
    expect(
      row.sourceJson,
      isNot(contains('"string":2,"fret":0,"midi":64,"beat":1.0')),
      reason: '被拦行不动(该音仍 ①弦0)',
    );
    expect(row.reviewedAt, '2026-10-26T10:00:00.000', reason: '未落库不盖章');
  });

  test('编辑违约(引用不存在/越界):归入 Blocked 不抛出', () async {
    final outcome = await session.apply(
      const ScoreIrReFret(
        ref: ScoreIrNoteRef(
          voice: ScoreIrVoiceKind.accompaniment,
          string: 4,
          beat: 99,
        ),
        string: 1,
        fret: 0,
      ),
    );
    expect(outcome, isA<ScoreIrEditBlocked>());
    expect((outcome as ScoreIrEditBlocked).errors, isNotEmpty);
  });

  test('滑音端点被删:校验器拦「滑音起点无音」,行不动', () async {
    final outcome = await session.apply(
      const ScoreIrDelete(
        ref: ScoreIrNoteRef(
          voice: ScoreIrVoiceKind.accompaniment,
          string: 4,
          beat: 4,
        ),
      ),
    );
    final errors = (outcome as ScoreIrEditBlocked).errors;
    // 删 @4:前槽为空,后音 @5 回拉到 @4——滑音 fromBeat 落了音,
    // toBeat @5 悬空,校验器报终点。
    expect(errors.join(), contains('滑音终点无音'));
    expect((await dao.getAll()).single.sourceJson, originalJson);
  });
}
