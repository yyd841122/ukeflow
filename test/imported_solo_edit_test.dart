import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
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
import 'package:webview_flutter/webview_flutter.dart';
import 'package:ukeflow/features/play/score_sheet_page.dart';
import 'package:ukeflow/features/play/tab_chart_layout.dart';
import 'package:ukeflow/features/play/tab_chart_page.dart';

import 'helpers/fake_webview_platform.dart';
import 'helpers/score_ir_fixtures.dart';

/// 工单 45 页面接线:导入谱页(谱面视图/四线谱跟练)点选音 → 微调面板
/// → 存回 → 导入谱流推新源 → 页面重物化换源。真内存库
/// (closeStreamsSynchronously 收口 drift 流计时器)+ FakeAudioEngine。
/// 票05 追加:原谱视图入口(条目带 sourceHtml 才显,点入 WebView 页——
/// 平台视图在 widget 测试不渲染,只锁入口显隐与导航)。
void main() {
  late AppDatabase db;
  late ImportedSoloChartsDao dao;
  late int rowId;
  late ScoreIrMaterialization materialization;

  setUp(() async {
    // 平台桩全文件共享(接口不允许置 null 复位;桩无状态,跨测试安全)。
    WebViewPlatform.instance = FakeWebViewPlatform();
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
      sourceHtml: '<html><head><style>@font-face{}</style></head><body>'
          '<div id="ukeflow-strip" style="display:none">'
          '<svg xmlns="http://www.w3.org/2000/svg" width="2000" height="148" '
          'viewBox="0 0 2000 148"></svg></div>'
          '<script type="application/json" id="ukeflow-strip-meta">'
          '{"width":2000,"height":148,'
          '"bars":[{"seq":0,"x":0.0,"w":200.0}]}</script>'
          '</body></html>',
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
            // 微调/跟练流程锁自绘谱面;默认原样视图的切回在另一测
            faithfulFirst: false,
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

  testWidgets('原样流水默认体:切换钮出、横带页装进 WebView、拍位驱动 JS', (tester) async {
    final platform = WebViewPlatform.instance as FakeWebViewPlatform;
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

    expect(find.byKey(const Key('toggle-score-view')), findsOneWidget);
    // 横带 WebView 页装的是工作台植入的横带节点(单行流水)。
    expect(platform.loadedHtml, isNotEmpty);
    expect(containsStripContent(platform.loadedHtml.last), isTrue,
        reason: '流水 WebView 加载横带页(css+svg+播放头脚本)');
  });

  testWidgets('原谱入口:sourceHtml 清空后无入口(旧条目不炸不显示)', (tester) async {
    // updateSource 不动 sourceHtml 列——直更清空该列模拟旧条目。
    await (dao.update(db.importedSoloCharts)
          ..where((tbl) => tbl.id.equals(rowId)))
        .write(const ImportedSoloChartsCompanion(sourceHtml: Value(null)));

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
            // 微调/跟练流程锁自绘谱面;默认原样视图的切回在另一测
            faithfulFirst: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('toggle-score-view')), findsNothing);
  });
}
