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
import 'package:ukeflow/features/library/library_page.dart';
import 'package:ukeflow/features/play/chart_meta.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';

/// 曲库页(工单 15):内置弹唱谱+自建弹唱谱(同一弹唱谱区,数据源接通)
/// 与内置指弹谱(指弹谱区)。内置谱注入 fixture,自建谱走真内存库
/// (closeStreamsSynchronously 收口 drift 流计时器,见 path_page_test);
/// 引擎一律 FakeAudioEngine(点曲进跟练页会预热)。
void main() {
  late AppDatabase db;
  late FakeAudioEngine engine;

  Future<void> pumpLibrary(WidgetTester tester) async {
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
          builtinChartsFixtureOverride([
            (id: 'test-chart-a', chart: practiceFixtureChart),
            (
              id: 'test-chart-b',
              chart: parseChart('{title: 第二首}\n{tempo: 96}\n[C]词\n'),
            ),
          ]),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('渲染:弹唱谱/指弹谱两区即类型标识,内置曲目齐全,工具行在顶', (tester) async {
    await pumpLibrary(tester);

    expect(find.text('弹唱谱'), findsOneWidget);
    expect(find.text('指弹谱'), findsOneWidget);
    expect(find.text('测试曲'), findsOneWidget);
    expect(find.text('测试者 · C 调 · 80 BPM'), findsOneWidget);
    expect(find.text('第二首'), findsOneWidget);
    // 指弹谱区来自 Dart 常量目录(零资产,不注入也可见)。
    expect(find.text('小星星'), findsOneWidget);
    expect(find.text('指弹 · 传统童谣 · 90 BPM'), findsOneWidget);
    expect(find.text('欢乐颂'), findsOneWidget);
    // 练琴工具行(工单 15 后续:跟练页签裁撤,工具并入曲库页顶部)。
    expect(find.text('节拍器'), findsOneWidget);
    expect(find.text('节奏型训练'), findsOneWidget);
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

  testWidgets('弹唱谱区有 Cifra Club 搜索源入口(工单 17)', (tester) async {
    await pumpLibrary(tester);

    // 只验入口在:点进会构造 WebView(真平台件),widget 测试环境没有,
    // 页面本身由真机验收(票 17 验收①)。
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
    await pumpLibrary(tester);

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
    expect(find.text('我自己 · 88 BPM'), findsOneWidget, reason: '元信息行取自源文本');

    // 自建谱与内置谱同一待遇:点开直达跟练。
    await tester.tap(find.byKey(const Key('custom-chart-1')));
    await tester.pumpAndSettle();
    expect(find.text('开始跟练'), findsOneWidget);
  });

  testWidgets('坏谱降级:单条自建谱读不出只标记自身,整库不株连', (tester) async {
    await pumpLibrary(tester);

    // 绕过导入管线直写坏谱(DAO 层不校验,读出层才校验)——
    // 模拟存储损坏/白名单漂移后的存量坏行。
    await db.customChartsDao.add(title: '坏谱歌', source: '{start_of_verse}\n[C]词');
    await tester.pumpAndSettle();

    // 坏条目:保留在列(不静默缺曲目)、标记不可跟练。
    expect(find.text('坏谱歌'), findsOneWidget);
    expect(find.text('谱面读不出,暂不可跟练'), findsOneWidget);
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
        child: const MaterialApp(home: LibraryPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('曲库加载失败'), findsOneWidget);
    expect(find.textContaining('内置谱炸了'), findsOneWidget);
  });

  testWidgets('窄屏(360dp)列表不溢出', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await pumpLibrary(tester);
    expect(tester.takeException(), isNull);
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
