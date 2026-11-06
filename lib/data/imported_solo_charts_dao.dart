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
  /// [reviewedAt] 是源 review.reviewedAt 原样照录(无则 null),
  /// [sourceHtml] 是原样渲染 HTML(票05,可空)。
  /// contentSha 现算自[指纹](fingerprintOf,内容指纹,重导入去重/改源
  /// 检测的判定面):含 sourceHtml——同一 IR 带不带原谱是不同文件
  /// (票05 教训:剥离后同指纹会让带原谱的重导入命中旧行,原谱丢失)。
  /// createdAt/updatedAt = 落库时刻。返回自增 id。
  Future<int> add({
    required String title,
    required String sourceJson,
    required int schemaVersion,
    String? reviewedAt,
    String? sourceHtml,
  }) {
    final now = DateTime.now();
    return into(importedSoloCharts).insert(
      ImportedSoloChartsCompanion.insert(
        title: title,
        schemaVersion: schemaVersion,
        sourceJson: sourceJson,
        contentSha: shaOf(fingerprintOf(sourceJson, sourceHtml)),
        createdAt: now,
        updatedAt: now,
        reviewedAt: Value(reviewedAt),
        sourceHtml: Value(sourceHtml),
      ),
    );
  }

  /// 内容指纹文本(票05):源 JSON + 原谱 HTML 一起参与——去重/改源
  /// 检测的判定单位是「导入的文件」,不是剥离后的语义 IR。
  static String fingerprintOf(String sourceJson, String? sourceHtml) =>
      sourceHtml == null ? sourceJson : '$sourceJson\u0000$sourceHtml';

  /// 彻底删除一行(票06:设置页隐藏区的真删除;与「隐藏=移出曲库可
  /// 恢复」不同,此口不可恢复)。调用方负责同步清隐藏集,防陈年 id。
  /// 返回实际删除行数。
  Future<int> removeAt(int id) {
    return (delete(importedSoloCharts)..where((row) => row.id.equals(id))).go();
  }

  /// 轻改存回(工单 45):源 JSON 改后整行落回——contentSha 随新源
  /// 现算,updatedAt/reviewedAt 随写随 bump(轻改自动记复核时刻,
  /// 与源内 review.reviewedAt 同步由会话层盖章),title/createdAt/
  /// schemaVersion 不动。[expectedSourceJson] 给出时按内容条件写
  /// (乐观并发,评审51:载入与更新之间被别处改过就 0 行不写);返回
  /// 实际写入行数,0 = 行不存在或源已被并发改写。
  Future<int> updateSource({
    required int id,
    required String sourceJson,
    String? reviewedAt,
    String? expectedSourceJson,
  }) {
    final now = DateTime.now();
    return (update(importedSoloCharts)
          ..where((row) => row.id.equals(id))
          ..where((row) => expectedSourceJson == null
              ? const Constant(true)
              : row.sourceJson.equals(expectedSourceJson)))
        .write(
      ImportedSoloChartsCompanion(
        sourceJson: Value(sourceJson),
        contentSha: Value(shaOf(sourceJson)),
        updatedAt: Value(now),
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

  /// 按内容指纹查行(工单 44 重导入去重:同内容已入库则提示已有,
  /// 不重复落行)。未入库返回 null。contentSha 无唯一约束(并发导入
  /// 理论可造重复),单行语义按标准纪律 limit(1)+id 定序,不赌
  /// getSingleOrNull 的「恰好一行」(评审51;重复时取最早一条)。
  Future<ImportedSoloChart?> getByContentSha(String sha) {
    return (select(importedSoloCharts)
          ..where((row) => row.contentSha.equals(sha))
          ..orderBy([(row) => OrderingTerm.asc(row.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 查重+插入同一事务(评审51 #30:先查后插分离有竞态窗,并发导入
  /// 造重复)。重复时**不插入**,返回既有行(id = 既有行 id)。
  Future<({int id, bool existed})> addUnique({
    required String title,
    required String sourceJson,
    required int schemaVersion,
    String? reviewedAt,
    String? sourceHtml,
  }) {
    final sha = shaOf(fingerprintOf(sourceJson, sourceHtml));
    return transaction(() async {
      final existing = await getByContentSha(sha);
      if (existing != null) {
        return (id: existing.id, existed: true);
      }
      final id = await add(
        title: title,
        sourceJson: sourceJson,
        schemaVersion: schemaVersion,
        reviewedAt: reviewedAt,
        sourceHtml: sourceHtml,
      );
      return (id: id, existed: false);
    });
  }

  /// 按行 id 取单行(工单 45 轻改会话读源用)。未入库返回 null。
  Future<ImportedSoloChart?> getById(int id) {
    return (select(
      importedSoloCharts,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  /// 响应式导入独奏谱流:曲库独奏谱类目订阅,导入写入即自动入列。
  Stream<List<ImportedSoloChart>> watchAll() {
    return (select(
      importedSoloCharts,
    )..orderBy([(row) => OrderingTerm.asc(row.id)])).watch();
  }

  /// 源内容指纹:sha256 十六进制串(源 JSON 的 UTF-8 字节)。静态公开:
  /// 导入页查重(工单 44)与入库算同一函数,指纹口径不许漂移。
  static String shaOf(String sourceJson) =>
      sha256.convert(Uint8List.fromList(utf8.encode(sourceJson))).toString();
}
