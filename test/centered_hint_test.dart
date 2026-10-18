import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/ui/centered_hint.dart';

/// 工单 23 空态/错误态收拢:居中提示壳(和弦搜索空态、Cifra 搜索
/// idle/零结果/失败四份同形收拢)。锁三点:主提示、detail 换行拼接、
/// 弱化色(onSurfaceVariant——M3 弱化可读文本,替代原先 chords 空态
/// 误用的 outline)。
void main() {
  testWidgets('主提示整段居中渲染', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CenteredHint(message: '没有匹配「C」的和弦')),
      ),
    );
    expect(find.text('没有匹配「C」的和弦'), findsOneWidget);
  });

  testWidgets('detail 换行拼接在主提示之后', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CenteredHint(message: '没有找到「x」', detail: '换个歌名试试'),
        ),
      ),
    );
    expect(find.text('没有找到「x」\n换个歌名试试'), findsOneWidget);
  });

  testWidgets('文字用 onSurfaceVariant 弱化色', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CenteredHint(message: '提示'))),
    );
    final context = tester.element(find.byType(CenteredHint));
    final text = tester.widget<Text>(find.text('提示'));
    expect(text.style?.color, Theme.of(context).colorScheme.onSurfaceVariant);
  });
}
