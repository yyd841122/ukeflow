import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/import/score_ir_materializer.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/providers.dart';
import 'package:ukeflow/features/library/score_source_import_flow.dart';
import 'package:ukeflow/features/library/score_source_import_page.dart';
import 'package:ukeflow/features/play/faithful_score_view.dart';
import 'package:ukeflow/features/play/score_sheet_view.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'helpers/fake_webview_platform.dart';
import 'helpers/score_ir_fixtures.dart';

/// 工单 44 导入预览页:试物化三源出谱面视图横带 + 命名 + 确认入库。
/// 落库走真内存库(closeStreamsSynchronously 收口 drift 流计时器);
/// ready 夹具直接由 validTinyIr 构造(选文件环节在 flow 测试覆盖)。
void main() {
  late AppDatabase db;

  ScoreSourceReady readyFor({String? suggestedTitle, String? sourceHtml}) {
    final ir = validTinyIr();
    return ScoreSourceReady(
      sourceJson: jsonEncode(ir.toJson()),
      ir: ir,
      materialization: materializeScoreIr(ir),
      suggestedTitle: suggestedTitle,
      sourceHtml: sourceHtml,
    );
  }

  /// 从启动页推入预览页:存入后的 pop 有处可回(验收「退页回列表」)。
  /// [extraOverrides] 供单测注入故障(如落库口)。
  Future<void> pumpPage(
    WidgetTester tester,
    ScoreSourceReady ready, {
    List<Override> extraOverrides = const [],
  }) async {
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
          ...extraOverrides,
        ],
        child: MaterialApp(
          // 启动页包 Scaffold:SnackBar 由 ScaffoldMessenger 挂到可见
          // Scaffold 上,真实流退回的曲库页本就有,夹具照实补齐。
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ImportScoreSourcePage(ready: ready),
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

  testWidgets('试物化出谱面视图横带,曲名预填源内曲名(无建议名兜底)', (tester) async {
    await pumpPage(tester, readyFor());

    expect(find.byKey(const Key('score-strip-scroll')), findsOneWidget,
        reason: '预览 = 谱面视图横带(静态读谱态)');
    expect(find.text('测试小谱'), findsOneWidget,
        reason: '建议名缺省回退源内曲名(校验器保证非空白)');
  });

  testWidgets('建议名优先于源内曲名', (tester) async {
    await pumpPage(tester, readyFor(suggestedTitle: 'ai-ni-score'));

    expect(find.text('ai-ni-score'), findsOneWidget);
  });

  testWidgets('清空曲名 → 内联报错,不落库', (tester) async {
    await pumpPage(tester, readyFor(suggestedTitle: 'x'));

    await tester.enterText(find.byKey(const Key('import-score-title')), ' ');
    await tester.tap(find.byKey(const Key('import-score-save')));
    await tester.pumpAndSettle();

    expect(find.text('先给这首谱起个名字'), findsOneWidget);
    expect(await db.importedSoloChartsDao.getAll(), isEmpty);
  });

  testWidgets('确认入库:入库名落行(覆盖源内曲名),reviewedAt 照录,提示后退页', (tester) async {
    await pumpPage(tester, readyFor(suggestedTitle: 'ai-ni-score'));

    await tester.enterText(
      find.byKey(const Key('import-score-title')),
      '爱你不是两三天',
    );
    await tester.tap(find.byKey(const Key('import-score-save')));
    await tester.pumpAndSettle();

    final row = (await db.importedSoloChartsDao.getAll()).single;
    expect(row.title, '爱你不是两三天', reason: '展示名 = 入库名,覆盖源内曲名');
    expect(row.schemaVersion, scoreIrSchemaVersionOf(row.sourceJson));
    expect(row.reviewedAt, '2026-10-26T10:00:00.000', reason: '源复核状态照录');
    expect(find.text('「爱你不是两三天」已存入曲库'), findsOneWidget);
    expect(find.text('open'), findsOneWidget, reason: '入库后退页回列表');
  });

  testWidgets('sourceHtml 落独立列,sourceJson 剥离内嵌键(票05)', (tester) async {
    await pumpPage(
      tester,
      readyFor(suggestedTitle: '带原谱', sourceHtml: '<html>原谱</html>'),
    );

    await tester.tap(find.byKey(const Key('import-score-save')));
    await tester.pumpAndSettle();

    final row = (await db.importedSoloChartsDao.getAll()).single;
    expect(row.sourceHtml, '<html>原谱</html>', reason: '原谱原文单独落列');
    final map = jsonDecode(row.sourceJson) as Map;
    expect(map.containsKey('sourceHtml'), isFalse,
        reason: 'IR 真源保持纯语义');
  });

  testWidgets('落库失败 → 留页给可读引导,可重试', (tester) async {
    // 故障注入走 provider 覆盖(内存库 close 后 add 照常完成,关库不是
    // 故障——探针证伪);read 落在 try 内,炸点就是入库口本身。
    await pumpPage(
      tester,
      readyFor(suggestedTitle: 'x'),
      extraOverrides: [
        importedSoloChartsDaoProvider.overrideWith(
          (ref) => throw StateError('注入故障'),
        ),
      ],
    );

    await tester.enterText(find.byKey(const Key('import-score-title')), '任意名');
    await tester.tap(find.byKey(const Key('import-score-save')));
    await tester.pumpAndSettle();

    expect(find.text('没存进曲库——请再试一次'), findsOneWidget);
    expect(find.byKey(const Key('import-score-save')), findsOneWidget,
        reason: '留在预览页,不假成功');
  });

  testWidgets('源带横带:预览用原样流水视图(与谱面页同款,所见即所得)',
      (tester) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    await pumpPage(
      tester,
      readyFor(suggestedTitle: '带横带', sourceHtml: stripHtmlFixture()),
    );

    final platform = WebViewPlatform.instance as FakeWebViewPlatform;
    expect(platform.loadedHtml, isNotEmpty, reason: '预览横带走 WebView 装载');
    expect(containsStripContent(platform.loadedHtml.first), isTrue,
        reason: '装载内容含横带 SVG 与播放头脚本');
    expect(find.byType(FaithfulStripView), findsOneWidget);
    expect(find.byType(ScoreStripView), findsNothing,
        reason: '预览不再出另一套自绘渲染');
  });

  testWidgets('纯 IR 源(无横带):回退自绘 ScoreStripView', (tester) async {
    WebViewPlatform.instance = FakeWebViewPlatform();
    await pumpPage(tester, readyFor(suggestedTitle: '纯谱'));

    final platform = WebViewPlatform.instance as FakeWebViewPlatform;
    expect(platform.loadedHtml, isEmpty, reason: '无横带不进 WebView');
    expect(find.byType(ScoreStripView), findsOneWidget);
  });
}

/// 源 schemaVersion 照录的验法

/// 源 schemaVersion 照录的验法:从行内源 JSON 读回,不经内存对象。
int scoreIrSchemaVersionOf(String sourceJson) =>
    (jsonDecode(sourceJson) as Map)['schemaVersion'] as int;

/// 最小横带源页(标记节点与工作台植入同构)。
String stripHtmlFixture() => '<html><head><style>@font-face{}</style></head>'
    '<body><div id="ukeflow-strip" style="display:none">'
    '<svg xmlns="http://www.w3.org/2000/svg" width="2000" height="148" '
    'viewBox="0 0 2000 148"></svg></div>'
    '<script type="application/json" id="ukeflow-strip-meta">'
    '{"width":2000,"height":148,'
    '"bars":[{"bar":1,"x":0.0,"w":200.0}]}</script></body></html>';
