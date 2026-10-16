import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/custom_charts_dao.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/features/library/text_import_page.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';

/// 文本导入页(工单 16):粘贴 → 校验(失败可读报错、原文不动) →
/// 报告+命名 → 入库(重名明确处置) → 成功页直接跟练。
/// 全链路真内存库;引擎 Fake(去跟练会预热);和弦库 fixture 白名单。
void main() {
  late AppDatabase db;
  late FakeAudioEngine engine;

  Future<void> pumpImport(
    WidgetTester tester, {
    String? initialSource,
    String? notice,
  }) async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(engine),
          chordLibraryFixtureOverride(),
        ],
        child: MaterialApp(
          home: TextImportPage(
            initialSource: initialSource,
            notice: notice,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> paste(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('import-source')), text);
    await tester.tap(find.byKey(const Key('import-validate')));
    await tester.pumpAndSettle();
  }

  testWidgets('空粘贴拦下:提示先粘贴谱文本,不进报告', (tester) async {
    await pumpImport(tester);

    await paste(tester, '  \n');

    expect(find.text('先粘贴谱文本'), findsOneWidget);
    expect(find.byKey(const Key('import-save')), findsNothing);
  });

  testWidgets('坏谱被拦:错误可读可定位,原文原样可改', (tester) async {
    await pumpImport(tester);

    const bad = '{start_of_verse}\n[C]词\n[Xx9]词\n[F]词';
    await paste(tester, bad);

    // 可读可定位:段落未闭合、解析不了的和弦名、库里没有的和弦名,齐。
    expect(find.textContaining('没有闭合'), findsOneWidget);
    expect(find.textContaining('不是能识别的和弦名'), findsOneWidget);
    expect(find.textContaining('不在和弦库中'), findsOneWidget);
    // 原文不动:同一个输入框里原样可改。
    final field = tester.widget<TextField>(
      find.byKey(const Key('import-source')),
    );
    expect(field.controller!.text, bad);
    expect(find.byKey(const Key('import-save')), findsNothing,
        reason: '没过校验不给入库');
  });

  testWidgets('好谱:报告展示和弦清单+段落结构,曲名按源文本预填,校验不落库', (tester) async {
    await pumpImport(tester);

    await paste(tester, importFixtureSource);

    final title = tester.widget<TextField>(
      find.byKey(const Key('import-title')),
    );
    expect(title.controller!.text, '网上找的谱', reason: '按源文本 {title} 预填');
    expect(find.text('和弦清单'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('G7'), findsOneWidget);
    expect(find.text('Am'), findsOneWidget);
    expect(find.text('Bm'), findsOneWidget);
    expect(find.text('自由段 · 4 行'), findsOneWidget);
    expect(find.byKey(const Key('import-save')), findsOneWidget);
    expect(await db.customChartsDao.getAll(), isEmpty,
        reason: '校验只是预览,存入曲库才落库');
  });

  testWidgets('未命名拦下:提示起名,不落库', (tester) async {
    await pumpImport(tester);

    await paste(tester, importFixtureSource);
    await tester.enterText(find.byKey(const Key('import-title')), '  ');
    await tester.tap(find.byKey(const Key('import-save')));
    await tester.pumpAndSettle();

    expect(find.text('先给这首谱起个名字'), findsOneWidget);
    expect(await db.customChartsDao.getAll(), isEmpty);
  });

  testWidgets('入库成功:成功页展示校验报告,库里有了,去跟练直达会话页', (tester) async {
    await pumpImport(tester);

    await paste(tester, importFixtureSource);
    await tester.tap(find.byKey(const Key('import-save')));
    await tester.pumpAndSettle();

    expect(find.text('导入成功'), findsOneWidget);
    expect(find.text('和弦清单'), findsOneWidget, reason: '导入完成后仍有校验报告');
    expect(find.byKey(const Key('import-practice')), findsOneWidget);

    final rows = await db.customChartsDao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.title, '网上找的谱');
    expect(rows.single.source, importFixtureSource);

    await tester.tap(find.byKey(const Key('import-practice')));
    await tester.pumpAndSettle();
    expect(find.text('开始跟练'), findsOneWidget, reason: '直达跟练会话页空闲面板');
  });

  testWidgets('同名重复:弹处置对话框,覆盖原谱=原地替换不新增', (tester) async {
    await pumpImport(tester);
    await db.customChartsDao.add(title: '网上找的谱', source: '[C]旧词\n');
    await tester.pumpAndSettle();

    await paste(tester, importFixtureSource);
    await tester.tap(find.byKey(const Key('import-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('曲库已有同名'), findsOneWidget);

    await tester.tap(find.text('覆盖原谱'));
    await tester.pumpAndSettle();

    expect(find.text('导入成功'), findsOneWidget);
    final rows = await db.customChartsDao.getAll();
    expect(rows, hasLength(1), reason: '覆盖不新增行');
    expect(rows.single.source, importFixtureSource);
  });

  testWidgets('同名重复:两个都保留=两行同列', (tester) async {
    await pumpImport(tester);
    await db.customChartsDao.add(title: '网上找的谱', source: '[C]旧词\n');
    await tester.pumpAndSettle();

    await paste(tester, importFixtureSource);
    await tester.tap(find.byKey(const Key('import-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('两个都保留'));
    await tester.pumpAndSettle();

    expect(find.text('导入成功'), findsOneWidget);
    expect(await db.customChartsDao.getAll(), hasLength(2));
  });

  testWidgets('同名第三次导入(库里已两行同名):处置照常,覆盖最早行不炸', (tester) async {
    await pumpImport(tester);
    // 「两个都保留」的产物:库里已有两行同名。
    await db.customChartsDao.add(title: '网上找的谱', source: '[C]第一份\n');
    await db.customChartsDao.add(title: '网上找的谱', source: '[Am]第二份\n');
    await tester.pumpAndSettle();

    await paste(tester, importFixtureSource);
    await tester.tap(find.byKey(const Key('import-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('覆盖原谱'));
    await tester.pumpAndSettle();

    expect(find.text('导入成功'), findsOneWidget);
    final rows = await db.customChartsDao.getAll();
    expect(rows, hasLength(2), reason: '覆盖不新增行');
    expect(rows[0].source, importFixtureSource, reason: '覆盖的是最早那份');
    expect(rows[1].source, '[Am]第二份\n', reason: '后入库的不动');
  });

  testWidgets('同名重复:取消=留在报告页不落库', (tester) async {
    await pumpImport(tester);
    await db.customChartsDao.add(title: '网上找的谱', source: '[C]旧词\n');
    await tester.pumpAndSettle();

    await paste(tester, importFixtureSource);
    await tester.tap(find.byKey(const Key('import-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('导入成功'), findsNothing);
    expect(find.byKey(const Key('import-save')), findsOneWidget);
    expect(await db.customChartsDao.getAll(), hasLength(1));
  });

  testWidgets('无源名的谱:命名后去跟练,会话页标题=入库名(非「未命名」)', (tester) async {
    await pumpImport(tester);

    await paste(tester, '[C]hello [G7]world');
    await tester.enterText(find.byKey(const Key('import-title')), '起的名');
    await tester.tap(find.byKey(const Key('import-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('import-practice')));
    await tester.pumpAndSettle();

    expect(find.text('起的名'), findsOneWidget, reason: '会话页标题=入库名');
    expect(find.text('未命名'), findsNothing);
    expect(find.text('开始跟练'), findsOneWidget);
  });

  testWidgets('两行式谱被拦:零和弦给可读指引,不给入库', (tester) async {
    await pumpImport(tester);

    // 网上最常见的两行式排版原样粘贴(和弦悬在歌词上方)。
    await paste(tester, "Em\nThey told him, don't you ever come around here\n");

    expect(find.textContaining('两行式'), findsOneWidget);
    expect(find.byKey(const Key('import-save')), findsNothing,
        reason: '零和弦空谱不入库');
  });

  testWidgets('窄屏(360dp)不溢出', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await pumpImport(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('预填直达校验(搜索源导入路径):进页即报告,{title} 预填曲名', (
    tester,
  ) async {
    await pumpImport(
      tester,
      initialSource: practiceFixtureChartText,
    );

    expect(find.byKey(const Key('import-validate')), findsNothing,
        reason: '不落粘贴态');
    expect(find.byKey(const Key('import-save')), findsOneWidget);
    expect(find.text('测试曲'), findsOneWidget,
        reason: '曲名按源文本 {title} 预填');
  });

  testWidgets('预填坏谱:落回粘贴态给可读错误,原文可改可重校', (tester) async {
    await pumpImport(
      tester,
      initialSource: '{start_of_verse: 主歌}\n[Am]没闭合\n',
    );

    expect(find.byKey(const Key('import-validate')), findsOneWidget);
    expect(find.byKey(const Key('import-save')), findsNothing);
    expect(find.textContaining('没有闭合'), findsOneWidget);
    // 原文预填在粘贴框里,改完可原地重校。
    expect(
      find.byKey(const Key('import-source')),
      findsOneWidget,
    );
  });

  testWidgets('预填后改名入库:曲库名=用户输入名(非源 {title})', (tester) async {
    await pumpImport(tester, initialSource: practiceFixtureChartText);

    await tester.enterText(find.byKey(const Key('import-title')), '新名字');
    await tester.tap(find.byKey(const Key('import-save')));
    await tester.pumpAndSettle();

    expect(find.text('导入成功'), findsOneWidget);
  });

  testWidgets('带 notice(ukulele 版缺失回退告知):报告页顶部可见', (tester) async {
    await pumpImport(
      tester,
      initialSource: practiceFixtureChartText,
      notice: '此歌没有 Ukulele 版,已按原版导入。',
    );

    expect(find.textContaining('没有 Ukulele 版'), findsOneWidget);
    expect(find.byKey(const Key('import-save')), findsOneWidget);
  });

  testWidgets('保存失败(库写错误):可读错误就地可见,报告与原文保留可重试(审计30 #30)', (tester) async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(engine),
          chordLibraryFixtureOverride(),
          customChartsDaoProvider.overrideWith((ref) => ExplodingDao(db)),
        ],
        child: const MaterialApp(home: TextImportPage()),
      ),
    );
    await tester.pumpAndSettle();

    await paste(tester, '[C]门前大桥下游过一群鸭\n');
    await tester.enterText(find.byKey(const Key('import-title')), '测试谱');
    await tester.tap(find.byKey(const Key('import-save')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '库错误不得逃逸成未处理异常');
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.byKey(const Key('import-save')), findsOneWidget,
        reason: '仍在报告页,可重试');
  });
}

/// add 必炸的 DAO:制造库写失败现场。
class ExplodingDao extends CustomChartsDao {
  ExplodingDao(super.db);

  @override
  Future<int> add({required String title, required String source}) =>
      throw Exception('库写失败(注入)');

}