import 'dart:convert';

import 'score_ir.dart';
import 'score_ir_materializer.dart';
import 'score_ir_validator.dart';

/// 导入独奏谱(GLOSSARY「识谱源」落地,ADR-0009)源 JSON → 弹练三源。
/// 存储里存的是识谱源 JSON(唯一真源,自建弹唱谱存源文本同型),读出
/// 必过与导入时同一的管线——解码 → ScoreIr.fromJson → 物化(内含校验)。
/// 这是**不信任存储的最后一道闸**:JSON 坏损/schemaVersion 不符/校验
/// 阻塞三类坏源当场抛([ScoreIrFormatException] /
/// [ScoreIrMaterializationException],统一归入识谱源的异常域),
/// 工单 43 的 Ready/Broken 兜底捕获降级为「已损坏」条目——坏谱可见、
/// 源保留可重试,不崩溃也不静默消失。
///
/// [title] 是入库名(与自建谱同一命名纪律):展示名一律以它为准,覆盖
/// 源内曲名——组合定义与两层谱题同源覆盖,曲库卡片与谱面页标题不出现
/// 两个名字。def.id 仍照录源(组合绑定证据);曲库卡 key 用数据库行 id,
/// 与内置谱目录 id 不共用命名空间。
ScoreIrMaterialization materializeImportedSoloChart({
  required String sourceJson,
  required String title,
}) {
  final ir = ScoreIr.fromJson(_decode(sourceJson));
  final m = materializeScoreIr(ir);
  return ScoreIrMaterialization(
    accompaniment: m.accompaniment.withTitle(title),
    melody: m.melody.withTitle(title),
    def: m.def.withTitle(title),
  );
}

/// 解码并验形:非 JSON 文本与根非对象都归入 [ScoreIrFormatException]
/// (识谱源的数据故障域,不漏 TypeError 出去)。
Map<String, dynamic> _decode(String sourceJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(sourceJson);
  } on FormatException catch (e) {
    throw ScoreIrFormatException('源 JSON 解析失败:${e.message}');
  }
  if (decoded is Map<String, dynamic>) return decoded;
  throw ScoreIrFormatException('源 JSON 根应为对象,实际 ${decoded?.runtimeType}');
}

/// 识谱源预检结果:合法([errors] 空)则 [ir] 在手,非法为 null。
class ScoreIrSourceCheck {
  const ScoreIrSourceCheck({required this.ir, required this.errors});

  /// 解析出的识谱源;解码/验形失败时为 null。
  final ScoreIr? ir;

  /// 全部阻塞错误,逐条人话;空表 = 合法。
  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

/// 导入页预检(工单 44):源 JSON → 全部阻塞错误逐条人话;合法 = 空表
/// 且 IR 在手(一次解析两用:列错清单 / 出预览试物化)。解码/验形失败
/// 单条报;校验阻塞全量报——校验器本就不首错即停,与读出管线
/// [materializeImportedSoloChart] 的「首异常即抛」不同:入口要一次把
/// 所有问题亮给用户回工作台修。
ScoreIrSourceCheck checkScoreIrSource(String sourceJson) {
  final ScoreIr ir;
  try {
    ir = ScoreIr.fromJson(_decode(sourceJson));
  } on ScoreIrFormatException catch (error) {
    return ScoreIrSourceCheck(ir: null, errors: [error.message]);
  }
  return ScoreIrSourceCheck(ir: ir, errors: validateScoreIr(ir));
}
