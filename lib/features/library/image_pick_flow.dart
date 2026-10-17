import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/chart/image_ingest.dart';

/// 相册选图流程(工单 18,GLOSSARY「图片谱」):选图 → 解码验真 →
/// 命名确认 → 落库。控制器只管前三步的可测编排(picker 注入,测试
/// 不碰平台通道),命名对话框与 snackbar 是薄 UI,归曲库页。
///
/// 权限姿态(工单 18 验收③「权限流程正确」):生产 picker 走系统
/// 照片选择器(Android 13+ photo picker,更旧版本 ACTION_GET_CONTENT
/// 系统选择),按次授权——App 全程不申请、不持有存储权限,「拒绝
/// 授权」在系统选择器路径上不存在;用户在选择器里取消即 [ImagePickCancelled]
/// 静默返回。极少数平台层失败(选择器缺失/读取中断)落 [ImagePickFailed],
/// 可读文案给引导,不崩溃。
sealed class ImagePickOutcome {
  const ImagePickOutcome();
}

/// 选到好图:已验真,等命名确认。
class ImagePicked extends ImagePickOutcome {
  const ImagePicked({required this.bytes, required this.suggestedTitle});

  final Uint8List bytes;

  /// 建议命名:文件名去扩展名;选图器没给名字就为 null,命名交给对话框。
  final String? suggestedTitle;
}

/// 用户在选择器里取消:静默返回,库里无新增、界面无报错。
class ImagePickCancelled extends ImagePickOutcome {
  const ImagePickCancelled();
}

/// 选图或验真失败:给可读引导文案(含重试建议),库里无新增。
class ImagePickFailed extends ImagePickOutcome {
  const ImagePickFailed(this.message);

  final String message;
}

typedef ImagePickerFn =
    Future<({Uint8List bytes, String? name})?> Function();

class ImagePickFlow {
  ImagePickFlow({ImagePickerFn? pick}) : pick = pick ?? pickImageFromGallery;

  /// 选图来源(注入缝:测试给假 picker,生产走系统照片选择器)。
  final ImagePickerFn pick;

  Future<ImagePickOutcome> pickAndValidate() async {
    final ({Uint8List bytes, String? name})? result;
    try {
      result = await pick();
    } on Object catch (error) {
      debugPrint('UkeFlow: 相册选图失败 $error');
      // 权限姿态:系统照片选择器按次授权,App 不申请存储权限,「去设置
      // 开权限」在结构上不存在——文案只指引真实可行的动作(重试)。
      return const ImagePickFailed('打开相册没成功——请再试一次');
    }
    if (result == null) return const ImagePickCancelled();
    try {
      await validateImageBytes(result.bytes);
      return ImagePicked(
        bytes: result.bytes,
        suggestedTitle: _suggestTitle(result.name),
      );
    } on ArgumentError catch (error) {
      return ImagePickFailed(error.message as String? ?? '图片无法解码');
    } on Object catch (error) {
      debugPrint('UkeFlow: 图片验真失败 $error');
      return const ImagePickFailed('图片读取失败——请换一张试试');
    }
  }

  /// 文件名去扩展名作建议名;空名/纯扩展名不给建议,交对话框默认。
  static String? _suggestTitle(String? name) {
    if (name == null) return null;
    final stem = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    final trimmed = stem.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// 生产选图:系统照片选择器按次授权(见类注释的权限姿态)。
/// 返回 null = 用户取消。
Future<({Uint8List bytes, String? name})?> pickImageFromGallery() async {
  final xfile = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (xfile == null) return null;
  final bytes = await xfile.readAsBytes();
  return (bytes: bytes, name: xfile.name);
}
