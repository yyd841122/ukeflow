import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/checkin.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/features/path/path_page.dart';

/// 工单 14:路径页接线测试(缝3)——域逻辑(缝1)与 DAO(缝2)已各自
/// 锁死,这里验「页面把两边接对」:今日任务推进、打卡/补卡呈现、进度与
/// 连续天数显示。窄屏 360dp 防溢出(真机面宽,默认测试面 800dp 抓不到)。
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
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: Scaffold(body: PathPage())),
  );

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
    await tester.tap(find.text('打卡'));
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
}
