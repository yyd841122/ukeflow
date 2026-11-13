import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/features/play/flowing/flowing_gate_page.dart';

/// 票08 体检闸门页 widget 测试:三种体检结论的报告渲染与拒绝语义。
/// (可练自动进跟练的动线不经 widget 测——推入 FlowingScorePage 需全套
/// 音频覆盖,由真机机检走常规入口验证。)
void main() {
  final goodSource = jsonDecode(
    File('assets/scores/sky-city-guistudy.json').readAsStringSync(),
  );
  final brokenSource = jsonDecode(
    File('assets/scores/selftest-broken.json').readAsStringSync(),
  );

  Future<void> pumpGate(
    WidgetTester tester, {
    required Object? Function() load,
    bool autoEnter = false,
    bool selftest = false,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        flowingGateJsonLoaderProvider.overrideWithValue((assetKey) async {
          final source = load();
          if (source == null) throw const FormatException('坏 JSON');
          return source;
        }),
      ],
      child: MaterialApp(
        home: FlowingScoreGatePage(
          autoEnter: autoEnter,
          selftest: selftest,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('好谱:可练横幅 + 清点 + 进入按钮(不自动进时)', (tester) async {
    await pumpGate(tester, load: () => goodSource);
    expect(find.text('可以练'), findsOneWidget);
    expect(find.textContaining('守门放行'), findsOneWidget);
    expect(find.text('《天空之城》谱面概览'), findsOneWidget);
    expect(find.text('A4 E4 C4 G4'), findsOneWidget);
    expect(find.text('4/4'), findsOneWidget);
    expect(find.textContaining('第 50 小节起 80→82 BPM'), findsOneWidget);
    expect(find.text('进入跟练'), findsOneWidget);
    expect(find.textContaining('未支持记号'), findsNothing);
  });

  testWidgets('坏谱:缺规则待补报告逐项可读,不误导入', (tester) async {
    await pumpGate(tester, load: () => brokenSource);
    expect(find.text('缺规则待补'), findsOneWidget);
    expect(find.textContaining('4 处暂不支持的记号'), findsOneWidget);
    // 明细卡在懒构建视口外,滚动到位再断言。
    await tester.scrollUntilVisible(
      find.text('未支持记号(4 处)'),
      200,
      maxScrolls: 50,
    );
    expect(find.text('未支持记号(4 处)'), findsOneWidget);
    // 逐项:类别分组 + 位置明细(消息自带小节号已去重,不双写)。
    await tester.scrollUntilVisible(
      find.textContaining('· 第 17 小节:有延音记号'),
      200,
      maxScrolls: 50,
    );
    expect(find.textContaining('反复 · 1 处'), findsOneWidget);
    expect(find.textContaining('· 第 5 小节:为反复起点'), findsOneWidget);
    expect(find.textContaining('· 第 13 小节:有 3:2 连音'), findsOneWidget);
    expect(find.textContaining('· 第 17 小节:有延音记号'), findsOneWidget);
    // 拒绝语义:不出现进入跟练,附未导入注记(注记在明细卡下方)。
    await tester.scrollUntilVisible(
      find.textContaining('该谱未导入'),
      200,
      maxScrolls: 50,
    );
    expect(find.text('进入跟练'), findsNothing);
    expect(find.textContaining('该谱未导入'), findsOneWidget);
  });

  testWidgets('装载失败:按资料不够呈现', (tester) async {
    await pumpGate(tester, load: () => null);
    expect(find.text('资料不够'), findsOneWidget);
    expect(find.textContaining('资料读取失败'), findsOneWidget);
    expect(find.text('进入跟练'), findsNothing);
  });
}
