
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/data/chart_providers.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/data/settings_dao.dart';
import 'package:ukeflow/features/library/library_page.dart';
import 'package:ukeflow/features/play/chart_meta.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';

/// 曲库目录与各类型列表:内置谱注入 fixture,自建谱走真内存库
/// (closeStreamsSynchronously 收口 drift 流计时器,见 path_page_test);
/// 引擎一律 FakeAudioEngine(点曲进跟练页会预热)。
void main() {
  late AppDatabase db;
  late FakeAudioEngine engine;

  Future<void> openCategory(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> pumpLibrary(
    WidgetTester tester, {
    String? category = '弹唱谱',
    Future<void> Function(AppDatabase db)? seed,
  }) async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    if (seed != null) await seed(db);
    engine = FakeAudioEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(engine),
          chordLibraryFixtureOverride(),
          builtinChartsFixtureOverride([
            (id: 'test-chart-a', chart: practiceFixtureChart),
            (
              id: 'test-chart-b',
              chart: parseChart('{title: 第二首}\n{tempo: 96}\n[C]词\n'),
            ),
          ]),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: const LibraryPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (category != null) await openCategory(tester, category);
  }

  testWidgets('目录三类入口齐全,逐类往返,工具行保留', (tester) async {
    await pumpLibrary(tester, category: null);
    expect(find.text('节拍器'), findsOneWidget);
    expect(find.text('节奏型训练'), findsOneWidget);
    expect(find.text('测试曲'), findsNothing);
    expect(find.text('导入'), findsNothing);
    expect(find.text('Cifra Club'), findsNothing);
    expect(find.text('相册选图'), findsNothing);
    for (final title in ['弹唱谱', '指弹谱']) {
      expect(find.text(title), findsOneWidget);
      await openCategory(tester, title);
      expect(find.widgetWithText(AppBar, title), findsOneWidget);
      if (title == '弹唱谱') {
        expect(find.text('测试曲'), findsOneWidget);
        expect(find.text('测试者 · C 调 · 80 BPM'), findsOneWidget);
        expect(find.text('第二首'), findsOneWidget);
        expect(find.text('导入'), findsOneWidget);
        expect(find.text('Cifra Club'), findsOneWidget);
      } else {
        expect(find.text('测试曲'), findsNothing);
        expect(find.text('导入'), findsNothing);
        expect(find.text('Cifra Club'), findsNothing);
      }
      if (title == '指弹谱') {
        expect(find.text('小星星'), findsOneWidget);
        expect(find.text('欢乐颂'), findsOneWidget);
        expect(find.text('指弹 · 传统童谣 · 90 BPM'), findsOneWidget);
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('弹唱谱区有文本导入入口,点进导入页', (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('import-source')),
      findsOneWidget,
      reason: '进入文本导入页',
    );
  });

  testWidgets('弹唱谱列表有 Cifra Club 搜索源入口', (tester) async {
    await pumpLibrary(tester);

    // 搜索页自身的平台交互由专属测试覆盖,此处只验入口随迁。
    expect(find.text('Cifra Club'), findsOneWidget);
  });

  testWidgets('点弹唱谱进跟练页,弹回回曲库', (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.byKey(const Key('chart-test-chart-a')));
    await tester.pumpAndSettle();
    expect(find.text('开始跟练'), findsOneWidget, reason: '会话页空闲面板');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('弹唱谱'), findsOneWidget);
  });

  testWidgets('点指弹谱进指弹跟练页,弹回回曲库', (tester) async {
    await pumpLibrary(tester, category: '指弹谱');

    await tester.tap(find.byKey(const Key('tab-chart-xiao-xing-xing')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('tab-chart-canvas')),
      findsOneWidget,
      reason: '进入指弹谱会话页',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('指弹谱'), findsOneWidget);
  });

  testWidgets('数据源接通:自建谱入库即自动入列,点开直达跟练', (tester) async {
    await pumpLibrary(tester);

    // 初态:自建谱为空,给友好空态提示。
    expect(find.textContaining('还没有自建谱'), findsOneWidget);
    expect(find.byKey(const Key('custom-chart-1')), findsNothing);

    // 走真链路:DAO 写入 → 流推送 → 解析 → 曲库出卡。
    await db.customChartsDao.add(
      title: '曲库自建歌',
      source: '{title: 曲库自建歌}\n{artist: 我自己}\n{tempo: 88}\n[C]词\n',
    );
    await tester.pumpAndSettle();

    expect(find.text('曲库自建歌'), findsOneWidget);
    expect(find.byKey(const Key('custom-chart-1')), findsOneWidget);
    expect(find.textContaining('还没有自建谱'), findsNothing, reason: '空态提示退场');
    expect(find.text('自建 · 我自己 · 88 BPM'), findsOneWidget, reason: '元信息行取自源文本');

    // 自建谱与内置谱同一待遇:点开直达跟练。
    await tester.tap(find.byKey(const Key('custom-chart-1')));
    await tester.pumpAndSettle();
    expect(find.text('开始跟练'), findsOneWidget);
  });

  testWidgets('坏谱降级:单条自建谱读不出只标记自身,整库不株连', (tester) async {
    await pumpLibrary(tester);

    // 绕过导入管线直写坏谱(DAO 层不校验,读出层才校验)——
    // 模拟存储损坏/白名单漂移后的存量坏行。
    await db.customChartsDao.add(
      title: '坏谱歌',
      source: '{start_of_verse}\n[C]词',
    );
    await tester.pumpAndSettle();

    // 坏条目:保留在列(不静默缺曲目)、标记不可跟练。
    expect(find.text('坏谱歌'), findsOneWidget);
    expect(find.text('自建 · 谱面读不出,暂不可跟练'), findsOneWidget);
    expect(find.textContaining('还没有自建谱'), findsNothing);
    await tester.tap(find.byKey(const Key('custom-chart-1')));
    await tester.pumpAndSettle();
    expect(find.text('开始跟练'), findsNothing, reason: '坏谱条目不可点进跟练');

    // 整库不株连:内置谱照常在列、照常可进跟练。
    expect(find.text('测试曲'), findsOneWidget);
    await tester.tap(find.byKey(const Key('chart-test-chart-a')));
    await tester.pumpAndSettle();
    expect(find.text('开始跟练'), findsOneWidget);
  });

  testWidgets('加载失败:可见报错,不带病进列表', (tester) async {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          chordLibraryFixtureOverride(),
          builtinChartsProvider.overrideWith(
            (ref) async => throw StateError('内置谱炸了'),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: LibraryPage())),
      ),
    );
    await tester.pumpAndSettle();

    await openCategory(tester, '弹唱谱');
    expect(find.text('曲库加载失败'), findsOneWidget);
    expect(find.textContaining('内置谱炸了'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
    expect(find.text('Cifra Club'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  // ── 工单 32:删除(自建谱真删,内置谱隐藏;图片谱线已终止 ADR-0013)──

  testWidgets('弹唱谱卡删除钮与进入钮并存', (tester) async {
    await pumpLibrary(tester);

    expect(find.byKey(const Key('delete-chart-test-chart-a')), findsOneWidget);

    // 删除钮不顶掉进入:点卡仍直达跟练。
    await tester.tap(find.byKey(const Key('chart-test-chart-a')));
    await tester.pumpAndSettle();
    expect(find.text('开始跟练'), findsOneWidget);
  });

  testWidgets('内置弹唱谱删除=隐藏:确认后退场,settings 行落库', (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.byKey(const Key('delete-chart-test-chart-a')));
    await tester.pumpAndSettle();
    expect(find.text('把「测试曲」移出曲库?'), findsOneWidget);
    expect(
      find.textContaining('可随时在设置页恢复'),
      findsOneWidget,
      reason: '文案讲清是隐藏不是真删',
    );

    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('chart-test-chart-a')),
      findsNothing,
      reason: '卡片即时退场(流推送)',
    );
    expect(
      find.byKey(const Key('chart-test-chart-b')),
      findsOneWidget,
      reason: '其余内置谱不受牵连',
    );
    expect(
      await db.settingsDao.getString(SettingsKeys.hiddenBuiltinStrums),
      'test-chart-a',
    );
  });

  testWidgets('内置谱删除确认框取消:留在曲库,不落库', (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.byKey(const Key('delete-chart-test-chart-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-test-chart-a')), findsOneWidget);
    expect(
      await db.settingsDao.getString(SettingsKeys.hiddenBuiltinStrums),
      isNull,
    );
  });

  testWidgets('自建谱删除=数据库行硬删:确认后卡片退场', (tester) async {
    await pumpLibrary(tester);

    await db.customChartsDao.add(
      title: '曲库自建歌',
      source: '{title: 曲库自建歌}\n[C]词\n',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('custom-chart-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-custom-chart-1')));
    await tester.pumpAndSettle();
    expect(find.text('删除「曲库自建歌」?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('custom-chart-1')), findsNothing);
    expect(await db.customChartsDao.getAll(), isEmpty);
    expect(find.textContaining('还没有自建谱'), findsOneWidget, reason: '空态提示回场');
  });

  testWidgets('损坏自建谱同样可删(自救路径补齐,工单 16 遗留)', (tester) async {
    await pumpLibrary(tester);

    await db.customChartsDao.add(
      title: '坏谱歌',
      source: '{start_of_verse}\n[C]词',
    );
    await tester.pumpAndSettle();
    expect(find.text('自建 · 谱面读不出,暂不可跟练'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-custom-chart-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('坏谱歌'), findsNothing);
    expect(await db.customChartsDao.getAll(), isEmpty);
  });

  testWidgets('指弹谱删除=隐藏:确认后退场(其余指弹曲不动)', (tester) async {
    await pumpLibrary(tester, category: '指弹谱');

    await tester.tap(find.byKey(const Key('delete-tab-chart-xiao-xing-xing')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tab-chart-xiao-xing-xing')), findsNothing);
    expect(find.byKey(const Key('tab-chart-huan-le-song')), findsOneWidget);
    expect(
      await db.settingsDao.getString(SettingsKeys.hiddenBuiltinTabs),
      'xiao-xing-xing',
    );
  });

  testWidgets('窄屏(360dp)列表不溢出', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await pumpLibrary(tester);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    for (final title in ['指弹谱']) {
      await openCategory(tester, title);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  test('chartMetaLine:空白字段剔除,不产孤立分隔符', () {
    final chart = parseChart(
      '{title: T}\n{artist: }\n{key: }\n{tempo: 96}\n[C]词\n',
    );
    expect(chartMetaLine(chart), '96 BPM');

    expect(
      chartMetaLine(parseChart('{title: T}\n[C]词\n')),
      isNull,
      reason: '全空返回 null 而非空串',
    );
  });


}

