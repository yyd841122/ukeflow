import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// 图片谱入库校验(工单 18):相册选来的字节入库前先解码验真——
/// 是不是一张真图、多大多大。解码失败抛 [ArgumentError](报错即可读,
/// 文案在选图流程层给)。与自建谱「读出闸」同一姿态:不信任输入,
/// 不让文本/截断文件混进图片谱库。
///
/// 真解码(引擎级 codec),不是魔数 sniff:能过这关,photo_view 那头
/// 就一定能显示。
Future<Size> validateImageBytes(Uint8List bytes) async {
  final ui.Codec codec;
  try {
    codec = await ui.instantiateImageCodec(bytes);
  } on Object {
    throw ArgumentError('图片数据无法解码(不是图片,或文件已损坏)');
  }
  final frame = await codec.getNextFrame();
  final size = Size(
    frame.image.width.toDouble(),
    frame.image.height.toDouble(),
  );
  frame.image.dispose();
  codec.dispose();
  if (size.isEmpty) {
    throw ArgumentError('图片尺寸异常(${size.width}×${size.height})');
  }
  return size;
}
