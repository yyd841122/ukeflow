import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/import/imported_solo_charts.dart';
import '../../core/import/score_ir.dart';
import '../../core/import/score_ir_editor.dart';
import '../../core/import/score_ir_validator.dart';
import '../../data/imported_solo_charts_dao.dart';

/// 轻改会话(工单 45,spec 故事 64):一条导入独奏谱的单音微调编排——
/// 改 IR(纯函数编辑器)→ 校验全检 → 改源 JSON 存回 → 重物化刷新。
/// 物化始终纯函数:本类只写源,弹练三源由既有读出管线
/// (importedSoloChartsProvider 流)重物化推送,页面监听换源。
///
/// 校验是落库的总闸:任何编辑结果不过 [validateScoreIr] 就不写行,
/// 阻塞错误逐条人话回面板(同弦同刻冲突/拍长闭合/滑音端点等)——
/// 轻改不该把谱改坏成 Broken,坏编辑在门前拦下,行保持原样可重试。
/// 落库时自动记 reviewedAt(源内 review.reviewedAt 与行列同步盖章:
/// 行列是源字段的照录,工单 43 纪律)。
class ScoreIrEditSession {
  ScoreIrEditSession(this._dao, {required this.rowId});

  final ImportedSoloChartsDao _dao;

  /// 导入独奏谱数据库行 id(会话绑定的那条源)。
  final int rowId;

  /// 读出当前源 IR(每次现读:面板打开与 apply 各读一次,行间外部
  /// 改动不陈旧)。行已不存在/源坏损抛异常,由面板呈现。
  Future<ScoreIr> load() async {
    final row = await _dao.getById(rowId);
    if (row == null) {
      throw StateError('导入谱 #$rowId 已不存在');
    }
    final check = checkScoreIrSource(row.sourceJson);
    if (!check.isValid) {
      throw ScoreIrFormatException(check.errors.join('\n'));
    }
    return check.ir!;
  }

  /// 应用一次编辑:合法即存回并自动记 reviewedAt,返回保存后的 IR;
  /// 非法(校验阻塞/编辑违约)原行不动,阻塞错误逐条人话返回。
  Future<ScoreIrEditOutcome> apply(ScoreIrNoteEdit edit) async {
    final ScoreIr loaded;
    try {
      loaded = await load();
    } on StateError catch (error) {
      return ScoreIrEditBlocked([error.message]);
    }
    final String loadedJson = (await _dao.getById(rowId))!.sourceJson;
    final ScoreIr edited;
    try {
      edited = applyScoreIrNoteEdit(loaded, edit);
    } on ArgumentError catch (error) {
      return ScoreIrEditBlocked([error.message ?? '$error']);
    }
    final errors = validateScoreIr(edited);
    if (errors.isNotEmpty) {
      return ScoreIrEditBlocked(errors);
    }
    final reviewedAt = DateTime.now().toIso8601String();
    final stamped = edited.copyWith(review: ScoreIrReview(reviewedAt: reviewedAt));
    final sourceJson = jsonEncode(stamped.toJson());
    // 乐观并发(评审51 #97):按载入时的源内容条件写,0 行 = 打开面板后
    // 源已被别处改写/删除——不覆盖别人,报给面板刷新重来。
    final affected = await _dao.updateSource(
      id: rowId,
      sourceJson: sourceJson,
      reviewedAt: reviewedAt,
      expectedSourceJson: loadedJson,
    );
    if (affected != 1) {
      return ScoreIrEditBlocked(
          ['源已在别处更新,面板刷新后重试(本次编辑未落库)']);
    }
    debugPrint('UkeFlow: 导入谱 #$rowId 轻改落库 $edit');
    return ScoreIrEditSaved(stamped);
  }
}

/// 编辑结果:存回([ScoreIrEditSaved])或被拦([ScoreIrEditBlocked])。
sealed class ScoreIrEditOutcome {
  const ScoreIrEditOutcome();
}

/// 已存回:源 JSON 落库、reviewedAt 已盖章,[ir] 为存后的源。
class ScoreIrEditSaved extends ScoreIrEditOutcome {
  const ScoreIrEditSaved(this.ir);

  final ScoreIr ir;
}

/// 被拦:阻塞错误逐条人话;库无变动,可改了再存。
class ScoreIrEditBlocked extends ScoreIrEditOutcome {
  const ScoreIrEditBlocked(this.errors);

  final List<String> errors;
}
