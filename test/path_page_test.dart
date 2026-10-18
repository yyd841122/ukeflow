import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/model/checkin.dart';
import 'package:ukeflow/data/checkins_dao.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/data/settings_providers.dart';
import 'package:ukeflow/features/path/path_page.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';

/// 工单 14:路径页接线测试(缝3)——域逻辑(缝1)与 DAO(缝2)已各自
/// 锁死,这里验「页面把两边接对」:今日任务推进、打卡/补卡呈现、进度与
/// 连续天数显示。窄屏 360dp 防溢出(真机面宽,默认测试面 800dp 抓不到)。
/// 工单 22 起页面还会直达目标页(和弦详情/节奏型训练/跟练),直达目标
/// 依赖的 provider 一并注入测试缝(引擎 Fake、和弦库/内置曲库 fixture)。
void main() {
  late AppDatabase db;

  // closeStreamsSynchronously:drift 流缓存的收尾 Timer 在 fake zone 里
  // 永不过期(挂起计时器不变量+死锁双重问题,drift 文档明言该开关即为此设)。
  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    addTearDown(db.close); // drift 注释要求 widget 测试里显式关库
  });

  Widget app() => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      // 直达目标解析缝(工单 22):和弦库/内置曲库 fixture,不碰真资产
      // (testWidgets 的 FakeAsync 里 rootBundle 真实文件 I/O 完不成)。
      chordLibraryFixtureOverride(),
      builtinChartsFixtureOverride([
        (id: 'cang-hai-yi-sheng-xiao', chart: practiceFixtureChart),
      ]),
      // 直达打开的训练/跟练页要引擎与默认 BPM 缝(与各自页测试同款)。
      audioEngineProvider.overrideWithValue(FakeAudioEngine()),
      defaultBpmProvider.overrideWithValue(80),
    ],
    child: const MaterialApp(home: Scaffold(body: PathPage())),
  );

  /// 把今日任务推到第 n+1 天:第 1..n 天都记为昨天打卡(全部「完成」,
  /// 连续天数与打卡种类不构成这些用例的变量)。
  Future<void> seedDays(int n) async {
    final yesterday = epochDayOf(DateTime.now()) - 1;
    for (var day = 1; day <= n; day++) {
      await db.checkInsDao.checkIn(
        day: day,
        kind: CheckInKind.completed,
        checkedOnDay: yesterday,
      );
    }
  }

  testWidgets('初始:第 1 天今日任务+30 天全貌+进度 0/30+连续 0 天', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('第 1 天'), findsWidgets);
    expect(find.text('打卡'), findsOneWidget);
    expect(find.text('0/30'), findsOneWidget);
    expect(find.text('连续 0 天'), findsOneWidget);
    expect(find.text('未到'), findsNWidgets(29)); // 第 2..30 天
  });

  testWidgets('打卡:今日任务推进到第 2 天,第 1 天标完成,进度 1/30', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('打卡'));
    await tester.pumpAndSettle();

    expect(find.text('1/30'), findsOneWidget);
    expect(find.textContaining('第 2 天'), findsWidgets);
    expect(find.text('完成'), findsOneWidget); // 第 1 天徽章
    expect(find.text('打卡'), findsOneWidget); // 新今日任务的打卡钮
  });

  testWidgets('双击打卡:写入进行中按钮禁用,只落一条打卡', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 连续两击不等帧:第一击进入写入、按钮禁用,第二击落在禁用态上。
    await tester.tap(find.text('打卡'), warnIfMissed: false);
    await tester.tap(find.text('打卡'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(await db.checkInsDao.completedCount(), 1);
    expect(find.text('1/30'), findsOneWidget);
  });

  testWidgets('补卡:隔了几日才回来,打卡标补卡,连续天数从今天重数', (tester) async {
    final today = epochDayOf(DateTime.now());
    await db.checkInsDao.checkIn(
      day: 1,
      kind: CheckInKind.completed,
      checkedOnDay: today - 3,
    );
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('第 2 天'), findsWidgets); // 今日任务已推进
    // 工单 22 起,隔日回来打卡钮预告「补卡」——点按钮本体(key),不依标签。
    await tester.tap(find.byKey(const Key('path-checkin')));
    await tester.pumpAndSettle();

    expect(find.text('完成'), findsOneWidget); // 第 1 天
    expect(find.text('补卡'), findsOneWidget); // 第 2 天
    expect(find.text('连续 1 天'), findsOneWidget); // 今天打了,从今天重数
  });

  testWidgets('回看:点已打卡的天进详情页看内容,显示已打卡与打卡日期', (tester) async {
    await db.checkInsDao.checkIn(
      day: 1,
      kind: CheckInKind.completed,
      checkedOnDay: 20740, // 独立锚点:= 2026-10-14(见 checkin_logic_test)
    );
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 今日任务卡已是第 2 天,「持琴与调音」只在全貌列表出现——点它进详情。
    await tester.tap(find.text('持琴与调音'));
    await tester.pumpAndSettle();

    expect(find.text('第 1 天'), findsOneWidget); // 详情页 AppBar
    expect(find.text('学什么'), findsOneWidget);
    expect(find.text('练什么'), findsOneWidget);
    expect(find.textContaining('已打卡 · 完成'), findsOneWidget);
    expect(find.text('打卡日期 2026-10-14'), findsOneWidget);
  });

  testWidgets('回看:补卡天的详情把打卡日期标成补练日期(工单22 补卡体验收口)', (tester) async {
    await db.checkInsDao.checkIn(
      day: 1,
      kind: CheckInKind.madeUp,
      checkedOnDay: 20740, // 补练发生在 2026-10-14
    );
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('持琴与调音'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已打卡 · 补卡'), findsOneWidget);
    expect(find.text('补练日期 2026-10-14'), findsOneWidget);
    expect(find.text('打卡日期 2026-10-14'), findsNothing);
  });

  testWidgets('30 天全打卡:毕业卡替掉今日任务,不再有打卡钮', (tester) async {
    final today = epochDayOf(DateTime.now());
    for (var day = 1; day <= 30; day++) {
      await db.checkInsDao.checkIn(
        day: day,
        kind: CheckInKind.completed,
        checkedOnDay: today - (31 - day),
      );
    }
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('30/30'), findsOneWidget);
    expect(find.textContaining('全部完成'), findsOneWidget);
    expect(find.text('打卡'), findsNothing);
    expect(find.text('连续 30 天'), findsOneWidget); // 30 个连续日历日(末于昨天)
  });

  testWidgets('打卡失败(库错误):可读错误就地可见,不逃逸成未处理异常(审计30 #31)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          checkInsDaoProvider.overrideWith((ref) => ExplodingCheckInsDao(db)),
        ],
        child: const MaterialApp(home: Scaffold(body: PathPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('打卡'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '库错误不得逃逸成未处理异常');
    expect(find.textContaining('打卡没有存上'), findsOneWidget);
    expect(find.text('打卡'), findsOneWidget, reason: '仍在今日任务卡,可重试');
  });

  testWidgets('打卡流加载失败:可见报错,原文直接展示,不带病进路径(工单23)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          checkInsProvider.overrideWith(
            (ref) => Stream<List<CheckIn>>.error(StateError('打卡流炸了(注入)')),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: PathPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('打卡数据加载失败'), findsOneWidget);
    expect(find.textContaining('打卡流炸了(注入)'), findsOneWidget);
  });

  testWidgets('直达:今日任务卡显示目标 chips,点和弦 chip 进和弦详情(工单22)', (tester) async {
    await db.checkInsDao.checkIn(
      day: 1,
      kind: CheckInKind.completed,
      checkedOnDay: epochDayOf(DateTime.now()) - 1,
    );
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 今日任务 = 第 2 天「第一个和弦 C」,学/练点名 C → C chip 可见。
    expect(find.byKey(const Key('task-target-C')), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-target-C')));
    await tester.pumpAndSettle();

    expect(find.text('C'), findsWidgets, reason: '和弦详情页 AppBar 与文案');
    expect(find.text('按法要点'), findsOneWidget, reason: '落在和弦详情页');
  });

  testWidgets('直达:点节奏型 chip 进训练器且该型已预选(工单22)', (tester) async {
    // 今日任务推到第 11 天(目标 = 「下上 下上 下上 下上」):训练器默认
    // 型是「下 下 下 下」,预选生效才选中 eighth-du——测试不与默认共谋。
    await seedDays(10);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    const chip = Key('task-target-下上 下上 下上 下上');
    expect(find.byKey(chip), findsOneWidget);
    await tester.tap(find.byKey(chip));
    await tester.pumpAndSettle();

    expect(find.text('节奏型训练'), findsOneWidget, reason: '落在训练器');
    expect(
      tester.widget<ChoiceChip>(
        find.byKey(const Key('pattern-eighth-du')),
      ).selected,
      isTrue,
      reason: '带上下文直达:任务点名的节奏型已预选',
    );
    expect(
      tester.widget<ChoiceChip>(
        find.byKey(const Key('pattern-all-down')),
      ).selected,
      isFalse,
      reason: '默认型不得仍选中',
    );
  });

  testWidgets('直达:点曲目 chip 进跟练页并带上该谱(工单22)', (tester) async {
    // 今日任务推到第 24 天(目标 = 《沧海一声笑》);fixture 曲库把该 id
    // 映到测试谱——进跟练页见到测试谱,即证「按 id 解析出的谱对象」被带上。
    await seedDays(23);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-target-沧海一声笑')), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-target-沧海一声笑')));
    await tester.pumpAndSettle();

    expect(find.text('测试曲'), findsOneWidget, reason: '跟练页 AppBar 带上解析出的谱');
    expect(find.text('引擎就绪'), findsOneWidget, reason: '落在跟练会话页');
  });

  testWidgets('直达降级:目标解析不到不渲染假可点,文字提示就地可见(工单22)', (tester) async {
    // 第 6 天目标 G7+G;ui fixture 库只有 A7/Am/Bm/C/G7——G 查不到即
    // 降级现场(G7 同卡可解析,证明不是整排失效)。
    await seedDays(5);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-target-G7')), findsOneWidget,
        reason: '解析得到的目标照常可点');
    expect(find.byKey(const Key('task-target-G')), findsNothing,
        reason: '缺失目标不渲染假可点');
    expect(find.text('「G」暂不可直达'), findsOneWidget, reason: '降级为文字提示');
  });

  testWidgets('补卡体验:隔日以上回来,打卡钮标「补卡」并说明;打完恢复「打卡」(工单22)', (tester) async {
    await db.checkInsDao.checkIn(
      day: 1,
      kind: CheckInKind.completed,
      checkedOnDay: epochDayOf(DateTime.now()) - 3,
    );
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('补卡'), findsOneWidget, reason: '打卡钮预告本次是补卡');
    expect(find.text('打卡'), findsNothing);
    expect(find.textContaining('记为补卡'), findsOneWidget, reason: '一句说明,不焦虑');

    await tester.tap(find.byKey(const Key('path-checkin')));
    await tester.pumpAndSettle();

    expect(find.textContaining('记为补卡'), findsNothing, reason: '说明随打卡消退');
    expect(find.text('补卡'), findsOneWidget, reason: '全貌徽章:第 2 天记补卡');
    expect(find.text('打卡'), findsOneWidget, reason: '下次打卡恢复常规(紧邻日=完成)');
  });

  testWidgets('补卡体验:常规按日打卡钮仍是「打卡」(工单22)', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('打卡'), findsOneWidget);
    expect(find.text('补卡'), findsNothing);
    expect(find.textContaining('记为补卡'), findsNothing);
  });
}

/// getAll 必炸的 DAO:制造库读失败现场。
class ExplodingCheckInsDao extends CheckInsDao {
  ExplodingCheckInsDao(super.db);

  @override
  Future<List<CheckIn>> getAll() => throw Exception('库读失败(注入)');
}

