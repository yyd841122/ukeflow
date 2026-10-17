import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/chart/image_ingest.dart';

import 'helpers/image_fixtures.dart';

/// 工单 18 图片谱入库校验:相册选来的字节入库前先验「真图、可解码」,
/// 不让文本/截断文件混进图片谱库(不信任输入,与自建谱读出闸同一姿态)。
/// 测试素材用真 PNG(测试引擎里有真解码器),统一取 helpers。
void main() {
  test('合法 PNG:通过,报出尺寸', () async {
    final size = await validateImageBytes(tinyPngBytes);
    expect(size.width, 1);
    expect(size.height, 1);
  });

  test('空字节:拒绝', () async {
    await expectLater(
      validateImageBytes(Uint8List(0)),
      throwsArgumentError,
    );
  });

  test('垃圾字节(文本冒充):拒绝', () async {
    await expectLater(validateImageBytes(notImageBytes), throwsArgumentError);
  });

  test('截断 PNG:拒绝', () async {
    await expectLater(
      validateImageBytes(tinyPngBytes.sublist(0, 20)),
      throwsArgumentError,
    );
  });
}
