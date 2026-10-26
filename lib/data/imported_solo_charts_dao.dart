import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'database.dart';

part 'imported_solo_charts_dao.g.dart';

/// 导入独奏谱数据访问(工单 43,GLOSSARY「识谱源」)。
/// 解析/校验/物化等域规则在 core/import/imported_solo_charts.dart,
/// DAO 只管存取。
@DriftAccessor(tables: [ImportedSoloCharts])
class ImportedSoloChartsDao extends DatabaseAccessor<AppDatabase>
    with _$ImportedSoloChartsDaoMixin {
  ImportedSoloChartsDao(super.db);

  /// 入库(导入 UI 工单 44 的落库口;校验在解析层,此处不设防)。
  /// [schemaVersion] 是源的识谱源格式版本(照录,陈年源识别用),
  /// [reviewedAt] 是源 review.reviewedAt 原样照录(无则 null)。
  /// contentSha 由源 JSON 现算(内容指纹,重导入去重/改源检测的判定面),
  /// createdAt/updatedAt = 落库时刻。返回自增 id。
  Future<int> add({
    required String title,
    required String sourceJson,
    required int schemaVersion,
    String? reviewedAt,
  }) {
    final now = DateTime.now();
    return into(importedSoloCharts).insert(
      ImportedSoloChartsCompanion.insert(
        title: title,
        schemaVersion: schemaVersion,
        sourceJson: sourceJson,
        contentSha: _shaOf(sourceJson),
        createdAt: now,
        updatedAt: now,
        reviewedAt: Value(reviewedAt),
      ),
    );
  }

  /// 全部导入独奏谱,按入库序(id 升序)。
  Future<List<ImportedSoloChart>> getAll() {
    return (select(
      importedSoloCharts,
    )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
  }

  /// 响应式导入独奏谱流:曲库独奏谱类目订阅,导入写入即自动入列。
  Stream<List<ImportedSoloChart>> watchAll() {
    return (select(
      importedSoloCharts,
    )..orderBy([(row) => OrderingTerm.asc(row.id)])).watch();
  }

  /// 源内容指纹:sha256 十六进制串(源 JSON 的 UTF-8 字节)。
  static String _shaOf(String sourceJson) =>
      sha256.convert(Uint8List.fromList(utf8.encode(sourceJson))).toString();
}
