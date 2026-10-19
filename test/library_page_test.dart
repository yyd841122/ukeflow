import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/data/chart_providers.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/data/settings_dao.dart';
import 'package:ukeflow/features/library/image_chart_viewer_page.dart';
import 'package:ukeflow/features/library/image_pick_flow.dart';
import 'package:ukeflow/features/library/library_page.dart';
import 'package:ukeflow/features/play/chart_meta.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';
import 'helpers/image_fixtures.dart';

/// 曲库页(工单 15):内置弹唱谱+自建弹唱谱(同一弹唱谱区,数据源接通)
/// 与内置指弹谱(指弹谱区)。内置谱注入 fixture,自建谱走真内存库
/// (closeStreamsSynchronously 收口 drift 流计时器,见 path_page_test);
/// 引擎一律 FakeAudioEngine(点曲进跟练页会预热)。
void main() {
  late AppDatabase db;
  late FakeAudioEngine engine;

  Future<void> pumpLibrary(
    WidgetTester tester, {
    ImagePickFlow? imagePickFlow,
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
          builtinChartsFixtureOverride([
            (id: 'test-chart-a', chart: practiceFixtureChart),
            (
              id: 'test-chart-b',
              chart: parseChart('{title: 第二首}\n{tempo: 96}\n[C]词\n'),
            ),
          ]),
        ],
        child: MaterialApp(
          home: Scaffold(body: LibraryPage(imagePickFlow: imagePickFlow)),
        ),
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
        child: const MaterialApp(home: Scaffold(body: LibraryPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('曲库加载失败'), findsOneWidget);
    expect(find.textContaining('内置谱炸了'), findsOneWidget);
  });

  // ── 工单 32:删除(自建谱/用户图片谱真删,内置谱隐藏)──

  testWidgets('三类曲目卡都带删除钮,内置卡删除钮与进入钮并存', (tester) async {
    await pumpLibrary(tester);

    expect(find.byKey(const Key('delete-chart-test-chart-a')), findsOneWidget);
    expect(
      find.byKey(const Key('delete-tab-chart-xiao-xing-xing')),
      findsOneWidget,
    );
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
    expect(find.textContaining('可随时在设置页恢复'), findsOneWidget,
        reason: '文案讲清是隐藏不是真删');

    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chart-test-chart-a')), findsNothing,
        reason: '卡片即时退场(流推送)');
    expect(find.byKey(const Key('chart-test-chart-b')), findsOneWidget,
        reason: '其余内置谱不受牵连');
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
    expect(find.textContaining('还没有自建谱'), findsOneWidget,
        reason: '空态提示回场');
  });

  testWidgets('损坏自建谱同样可删(自救路径补齐,工单 16 遗留)', (tester) async {
    await pumpLibrary(tester);

    await db.customChartsDao.add(title: '坏谱歌', source: '{start_of_verse}\n[C]词');
    await tester.pumpAndSettle();
    expect(find.text('谱面读不出,暂不可跟练'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-custom-chart-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('坏谱歌'), findsNothing);
    expect(await db.customChartsDao.getAll(), isEmpty);
  });

  testWidgets('指弹谱删除=隐藏:确认后退场(其余指弹曲不动)', (tester) async {
    await pumpLibrary(tester);

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

  testWidgets('用户图片谱删除=数据库行硬删', (tester) async {
    await pumpLibrary(tester);

    await db.imageChartsDao.add(title: '用户图片谱', image: tinyPngBytes);
    await tester.pumpAndSettle();
    // 图片谱区在长列表底部:滚到可见再断言/点按(ListView 懒构建)。
    await tester.scrollUntilVisible(
      find.byKey(const Key('user-image-1')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('user-image-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-user-image-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('user-image-1')), findsNothing);
    expect(await db.imageChartsDao.getAll(), isEmpty);
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

  group('图片谱区(工单 18,ADR-0002 只读边界)', () {
    testWidgets('内置图片谱在列,区头与卡片都标识只读,有相册选图入口', (tester) async {
      await pumpLibrary(tester);

      // 区在长列表折叠线下,滚到可见再断言。
      await tester.scrollUntilVisible(
        find.text('Big Big World(图片版)'),
        200,
      );
      expect(find.text('图片谱'), findsOneWidget);
      expect(find.text('Big Big World(图片版)'), findsOneWidget);
      // 「只读」标识逐卡可见:图片谱不能跟练是 v1 物理边界(ADR-0002)。
      expect(find.text('图片谱 · 只读'), findsOneWidget);
      expect(find.text('相册选图'), findsOneWidget);
    });

    testWidgets('数据源接通:相册图片入库即自动入列,同样标识只读', (tester) async {
      await pumpLibrary(tester);

      await db.imageChartsDao.add(title: '相册来的谱', image: tinyPngBytes);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('相册来的谱'), 200);

      expect(find.text('相册来的谱'), findsOneWidget);
      expect(find.byKey(const Key('user-image-1')), findsOneWidget);
      // 内置 1 张 + 相册 1 张,只读标识两张都在。
      expect(find.text('图片谱 · 只读'), findsNWidgets(2));
    });

    testWidgets('点图片谱进查看器:全程无跟练入口(ADR-0002)', (tester) async {
      await pumpLibrary(tester);

      await db.imageChartsDao.add(title: '相册来的谱', image: tinyPngBytes);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('相册来的谱'), 200);
      await tester.tap(find.byKey(const Key('user-image-1')));
      // 定步 pump 不 pumpAndSettle:测试 FakeAsync 区里真图片解码不走
      // 真异步,photo_view 的加载转圈(无限动画)会把 settle 拖死;
      // 查看器页本身的断言不依赖图片出帧(出帧在 viewer 测试里验)。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ImageChartViewerPage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ImageChartViewerPage),
          matching: find.text('相册来的谱'),
        ),
        findsOneWidget,
        reason: '查看器标题(曲库卡片在路由下层,需限定)',
      );
      expect(find.text('只读'), findsOneWidget, reason: '查看器内只读徽标');
      expect(find.text('开始跟练'), findsNothing, reason: '不出现跟练入口');
    });

    testWidgets('相册选图失败给可读引导,不崩溃不入库', (tester) async {
      // 假 picker 直接抛平台异常(选择器打不开的情形);
      // widget 测试 FakeAsync 区里真通道调用永远等不到响应,必须打桩。
      ImagePickerPlatform.instance = _ThrowingPickerPlatform();
      addTearDown(() => ImagePickerPlatform.instance = _originalPickerPlatform);
      await pumpLibrary(tester);

      await tester.scrollUntilVisible(find.text('相册选图'), 200);
      // 再拖一点让按钮离开视口边缘,settle 后再点(按钮在区头右缘,
      // 滚停即点容易脱靶)。
      await tester.drag(find.byType(ListView), const Offset(0, -60));
      await tester.pumpAndSettle();
      await tester.tap(find.text('相册选图'));
      await tester.pumpAndSettle();

      expect(find.textContaining('打开相册没成功'), findsOneWidget);
      expect(find.byKey(const Key('user-image-1')), findsNothing);
    });

    testWidgets('相册选图全链路:选图→命名→落库→自动入列', (tester) async {
      // 选图+验真一环打桩(引擎解码在测试 FakeAsync 区不走真异步,
      // 真选图链在 image_pick_flow_test 真异步下覆盖);对话框→命名→
      // 落库→出卡走真链路。
      await pumpLibrary(tester, imagePickFlow: _StubPickedFlow());

      await tester.scrollUntilVisible(find.text('相册选图'), 200);
      await tester.drag(find.byType(ListView), const Offset(0, -60));
      await tester.pumpAndSettle();
      await tester.tap(find.text('相册选图'));
      await tester.pumpAndSettle();

      // 命名对话框:预填文件名去扩展名,改个名确认。
      expect(find.byKey(const Key('image-chart-title-input')), findsOneWidget);
      expect(
        find.text('my-chart'),
        findsOneWidget,
        reason: '建议名 = 文件名去扩展名',
      );
      await tester.enterText(find.byKey(const Key('image-chart-title-input')), '相册真图');
      await tester.tap(find.text('存入曲库'));
      await tester.pumpAndSettle();

      // 曲库流自动入列:改的名落卡。
      expect(find.text('相册真图'), findsOneWidget);
      expect(
        find.byKey(const Key('user-image-1')),
        findsOneWidget,
        reason: '内存库首行 id=1(内置示例是资产条目,不占库 id)',
      );
    });
  });
}

/// image_picker 平台打桩:widget 测试 FakeAsync 区里真通道调用永远等
/// 不到响应(不会抛 MissingPluginException,是挂死),必须从平台接口
/// 缝注入。生产代码同走 ImagePickerPlatform.instance,别无旁门。
final ImagePickerPlatform _originalPickerPlatform = ImagePickerPlatform.instance;

/// 选择器打不开/平台异常路。
class _ThrowingPickerPlatform extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    throw PlatformException(code: 'picker_unavailable', message: '没有可用的相册选择器');
  }
}

/// 选到好图路:直接给 ImagePicked(跳过平台选图与引擎解码,见全链路
/// 测试注释)。
class _StubPickedFlow extends ImagePickFlow {
  @override
  Future<ImagePickOutcome> pickAndValidate() async => ImagePicked(
    bytes: tinyPngBytes,
    suggestedTitle: 'my-chart',
  );
}
