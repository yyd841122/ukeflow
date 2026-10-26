import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../core/import/imported_solo_charts.dart';
import '../../core/import/score_ir.dart';
import '../../core/import/score_ir_materializer.dart';
import '../../data/imported_solo_charts_dao.dart';

/// 识谱源文件导入流程(工单 44,同 image_pick_flow/backup_flow 模式):
/// 选 .json → 解码验形 → 校验全检 → 重导入查重 → Ready 出预览命名页。
/// 控制器只管「选文件→验检→查重」的可测编排(picker 与查重查询注入,
/// 测试不碰平台通道与库);预览、命名与落库是薄 UI,归导入预览页。
///
/// 权限姿态(与工单 21 备份导入同纪律):系统文件选择器按次授权,
/// App 全程不申请、不持有存储权限;用户取消即静默返回。选择器放行
/// 任意类型——坏内容在校验层拦下给逐条人话错误,不靠扩展名。
sealed class ScoreSourcePickOutcome {
  const ScoreSourcePickOutcome();
}

/// 选到合法识谱源:已过校验全检 + 查重未命中,等预览确认。
class ScoreSourceReady extends ScoreSourcePickOutcome {
  const ScoreSourceReady({
    required this.sourceJson,
    required this.ir,
    required this.materialization,
    required this.suggestedTitle,
  });

  /// 原样源 JSON(落库存储的就是它,contentSha 现算自这份文本)。
  final String sourceJson;

  /// 解析出的识谱源(schemaVersion/复核状态从这里照录)。
  final ScoreIr ir;

  /// 试物化三件套(谱面视图预览渲染用;正式展示名以入库名为准,
  /// 此处三源题是源内曲名,仅预览)。
  final ScoreIrMaterialization materialization;

  /// 建议命名:文件名去扩展名;选择器没给名字就为 null,命名回退
  /// 源内曲名(校验器保证曲名非空白)。
  final String? suggestedTitle;
}

/// 用户在选择器里取消:静默返回,库无变动、界面无报错。
class ScoreSourceCancelled extends ScoreSourcePickOutcome {
  const ScoreSourceCancelled();
}

/// 校验未过:阻塞错误逐条人话(解码失败单条/校验阻塞全量),导入页
/// 整屏列出;库无变动,源回工作台修。
class ScoreSourceInvalid extends ScoreSourcePickOutcome {
  const ScoreSourceInvalid(this.errors);

  final List<String> errors;
}

/// 同内容已入库(重导入去重,contentSha 指纹命中):提示已有条目,
/// 不重复落行。
class ScoreSourceDuplicate extends ScoreSourcePickOutcome {
  const ScoreSourceDuplicate({required this.existingTitle});

  final String existingTitle;
}

/// 选文件/读字节/解码失败:可读文案给引导,库无变动。
class ScoreSourceFailed extends ScoreSourcePickOutcome {
  const ScoreSourceFailed(this.message);

  final String message;
}

typedef ScoreSourcePickerFn =
    Future<({Uint8List bytes, String? name})?> Function();

/// 内容指纹 → 已入库条目名(null = 无同内容)。注入缝:测试给假查重,
/// 生产走 DAO.getByContentSha。
typedef ScoreSourceShaLookup = Future<String?> Function(String sha);

class ScoreSourceImportFlow {
  ScoreSourceImportFlow({
    ScoreSourcePickerFn? pick,
    ScoreSourceShaLookup? findDuplicateTitle,
  }) : pick = pick ?? pickScoreSourceFileFromDevice,
       findDuplicateTitle = findDuplicateTitle ?? _noDuplicate;

  /// 选文件来源(注入缝:测试给假 picker,生产走系统文件选择器)。
  final ScoreSourcePickerFn pick;

  /// 重导入查重出口。
  final ScoreSourceShaLookup findDuplicateTitle;

  /// 选文件并验检成待确认识谱源。取消静默;坏文件带逐条人话错误
  /// 返回,不崩溃、不落库。
  Future<ScoreSourcePickOutcome> pickAndValidate() async {
    final ({Uint8List bytes, String? name})? result;
    try {
      result = await pick();
    } on Object catch (error) {
      debugPrint('UkeFlow: 识谱源选文件失败 $error');
      return const ScoreSourceFailed('打开文件没成功——请再试一次');
    }
    if (result == null) return const ScoreSourceCancelled();

    final String sourceJson;
    try {
      sourceJson = utf8.decode(result.bytes);
    } on FormatException {
      return const ScoreSourceFailed('文件不是有效的文本内容——请选择工作台导出的 .json 识谱源');
    }

    final check = checkScoreIrSource(sourceJson);
    if (!check.isValid) return ScoreSourceInvalid(check.errors);

    final existingTitle = await findDuplicateTitle(
      ImportedSoloChartsDao.shaOf(sourceJson),
    );
    if (existingTitle != null) {
      return ScoreSourceDuplicate(existingTitle: existingTitle);
    }

    // 校验已过才走到这,物化理应成功;此处仍兜底——物化器与校验器
    // 若有不同步属代码缺陷,给可读文案不崩导入页。
    final ScoreIrMaterialization materialization;
    try {
      materialization = materializeScoreIr(check.ir!);
    } on Object catch (error) {
      debugPrint('UkeFlow: 识谱源试物化失败 $error');
      return const ScoreSourceFailed('谱面物化失败——请把源文件与现象一并反馈');
    }
    return ScoreSourceReady(
      sourceJson: sourceJson,
      ir: check.ir!,
      materialization: materialization,
      suggestedTitle: suggestTitle(result.name),
    );
  }

  /// 文件名去扩展名作建议名;空名/纯扩展名不给建议,命名回退源内曲名。
  static String? suggestTitle(String? name) {
    if (name == null) return null;
    final stem = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    final trimmed = stem.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Future<String?> _noDuplicate(String sha) async => null;
}

/// 生产选文件:系统文件选择器,不限类型(坏内容由校验层拦,不赌各
/// 厂商文件管理器对 .json 的 MIME 标注;先例 backup_flow)。
/// null = 用户取消。
Future<({Uint8List bytes, String? name})?>
pickScoreSourceFileFromDevice() async {
  final file = await openFile(confirmButtonText: '导入');
  if (file == null) return null;
  return (bytes: await file.readAsBytes(), name: file.name);
}
