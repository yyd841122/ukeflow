import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:ukeflow/features/library/image_chart_viewer_page.dart';

import 'helpers/image_fixtures.dart';

/// 工单 18 图片谱查看器(photo_view 缩放平移):只读,能看不能跟练
/// (ADR-0002)。缩放平移是手势体验,widget 测试验「渲染就绪 + 无跟练
/// 入口 + 坏图可读报错」,流畅度归真机验收。
///
/// 注:测试 FakeAsync 区里引擎级图片解码不走真异步,好图路径用
/// runAsync 预热图片缓存(同一 provider 实例 → 缓存命中 → 同步出帧);
/// 坏图路径走错误完成,FakeAsync 下本就可达。
void main() {
  testWidgets('渲染:标题+只读徽标+图片视图就绪,无跟练入口', (tester) async {
    final provider = MemoryImage(tinyPngBytes);
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    await tester.runAsync(() => precacheImage(provider, capturedContext));

    await tester.pumpWidget(
      MaterialApp(
        home: ImageChartViewerPage(title: '测试图片谱', imageProvider: provider),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试图片谱'), findsOneWidget);
    expect(find.text('只读'), findsOneWidget);
    expect(find.byType(PhotoView), findsOneWidget);
    // ADR-0002:图片谱只读——页面上不存在任何跟练发起件。
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('开始跟练'), findsNothing);
  });

  testWidgets('坏图:可读报错,不崩溃不白屏', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImageChartViewerPage(
          title: '坏图',
          imageProvider: MemoryImage(notImageBytes),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('图片加载失败'), findsOneWidget);
  });
}
