import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/app.dart';

void main() {
  // 每个用例各建一个 ProviderScope，各自创建并关闭 AppDatabase；关闭是异步的，
  // 下一个用例建库时会撞上 drift「重复建库」调试启发式误报。测试用例之间没有
  // 共享 executor 的竞态，按 drift 给出的口径关掉该警告。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  Finder navLabel(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  // 工单 01 验收：App 启动渲染出导航壳。
  testWidgets('启动渲染五页签导航壳，初始落在调音器', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: UkeFlowApp()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    for (final label in ['调音器', '和弦', '跟练', '路径', '曲库']) {
      expect(navLabel(label), findsOneWidget, reason: '页签 $label 应存在');
    }
    // 当前页（调音器）= 页签 label + 页面标题各一份；未切到的页只出现在页签上。
    expect(find.text('调音器'), findsNWidgets(2));
    expect(find.text('曲库'), findsOneWidget);
  });

  testWidgets('点击页签可在五个页面间切换', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: UkeFlowApp()));
    await tester.pumpAndSettle();

    for (final label in ['和弦', '跟练', '路径', '曲库', '调音器']) {
      await tester.tap(navLabel(label));
      await tester.pumpAndSettle();
      expect(find.text(label), findsNWidgets(2), reason: '点 $label 后其页面应显示');
    }
  });
}
