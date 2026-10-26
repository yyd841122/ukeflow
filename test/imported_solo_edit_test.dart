import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/import/score_ir.dart';
import 'package:ukeflow/core/import/score_ir_materializer.dart';
import 'package:ukeflow/core/practice/score_sheet_layout.dart';
import 'package:ukeflow/data/chart_providers.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/data/imported_solo_charts_dao.dart';
import 'package:ukeflow/features/play/score_sheet_page.dart';
import 'package:ukeflow/features/play/tab_chart_layout.dart';
import 'package:ukeflow/features/play/tab_chart_page.dart';

import 'helpers/score_ir_fixtures.dart';

/// 工单 45 页面接线:导入谱页(谱面视图/四线谱跟练)点选音 → 微调面板
/// → 存回 → 导入谱流推新源 → 页面重物化换源。真内存库
/// (closeStreamsSynchronously 收口 drift 流计时器)+ FakeAudioEngine。
void main() {
  late AppDatabase db;
  late ImportedSoloChartsDao dao;
  late int rowId;
  late ScoreIrMaterialization materialization;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    dao = db.importedSoloChartsDao;
    addTearDown(db.close);
    final ir = validTinyIr();
    materialization = materializeScoreIr(ir);
    rowId = await dao.add(
      title: '接线谱',
      sourceJson: jsonEncode(ir.toJson()),
      schemaVersion: scoreIrSchemaVersion,
      reviewedAt: '2026-10-26T10:00:00.000',
    );
  });

  /// 流推送与读取存在竞速:以空转让步轮询到断言成立。
  Future<void> pollUntil(WidgetTester tester, bool Function() test) async {
    for (var i = 0; i < 100; i++) {
      if (test()) return;
      await tester.pump(const Duration(milliseconds: 10));
    }
    fail('轮询超时:导入谱流未推送新源');
  }

  ReadyImportedSolo? entryOf(WidgetTester tester, int id) =>
      ProviderScope.containerOf(tester.element(find.byType(ScoreSheetPage)))
              .read(importedSoloChartsProvider)
              .value
              ?.where((e) => e.id == id)
              .firstOrNull
          as ReadyImportedSolo?;

  testWidgets('谱面视图:点伴奏音 → 面板改品 → 存回流推新源,重开面板见新值', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
        ],
        child: MaterialApp(
          home: ScoreSheetPage(
            def: materialization.def,
            tabChart: materialization.accompaniment,
            melodyChart: materialization.melody,
            importedSoloRowId: rowId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 夹具伴奏首音(④4@4):横带 x = stripX(beat),弦线 y = ④。
    final stripOrigin = tester.getTopLeft(find.byKey(const Key('score-strip')));
    final layout = ScoreSheetLayout(
      def: materialization.def,
      tabChart: materialization.accompaniment,
      melodyChart: materialization.melody,
    );
    final note = layout.tabNotes.first;
    await tester.tapAt(
      stripOrigin +
          Offset(
            layout.stripX(note.beat),
            ScoreSheetLayout.tabBandTop +
                (note.string - 1) * ScoreSheetLayout.tabLineGap,
          ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-tune-panel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tune-fret-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tune-save')));
    await tester.pumpAndSettle();

    await pollUntil(tester, () {
      final entry = entryOf(tester, rowId);
      return entry != null && entry.accompaniment.notes.first.fret == 5;
    });
    // 面板关了,条目已换新源(重物化由读出管线完成)。
    expect(find.byKey(const Key('note-tune-panel')), findsNothing);

    // 重开面板:初值即新值(源刷新到位)。
    await tester.tapAt(
      stripOrigin +
          Offset(
            layout.stripX(note.beat),
            ScoreSheetLayout.tabBandTop +
                (note.string - 1) * ScoreSheetLayout.tabLineGap,
          ),
    );
    await tester.pumpAndSettle();
    expect(find.text('5'), findsWidgets);
  });

  testWidgets('四线谱跟练:点音改品存回,会话谱随流换新', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
        ],
        child: MaterialApp(
          home: TabChartPage(
            chart: materialization.accompaniment,
            importedSoloRowId: rowId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 画布点选:noteX(4) × ④弦线 y(画布原点在弦号列右侧)。
    final canvasOrigin = tester.getTopLeft(
      find.byKey(const Key('tab-chart-canvas')),
    );
    await tester.tapAt(
      canvasOrigin +
          Offset(TabChartLayout.firstPad + 4 * 44, TabChartLayout.stringY(4)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-tune-panel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tune-fret-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tune-save')));
    await tester.pumpAndSettle();

    await pollUntil(tester, () {
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TabChartPage)),
      );
      final entry =
          container
                  .read(importedSoloChartsProvider)
                  .value
                  ?.where((e) => e.id == rowId)
                  .firstOrNull
              as ReadyImportedSolo?;
      return entry != null && entry.accompaniment.notes.first.fret == 5;
    });
    expect(find.byKey(const Key('note-tune-panel')), findsNothing);
  });
}
