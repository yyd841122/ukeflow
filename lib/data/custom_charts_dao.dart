import 'package:drift/drift.dart';

import 'database.dart';

part 'custom_charts_dao.g.dart';

/// 自建谱数据访问(工单 15,GLOSSARY「自建谱」)。
/// 校验等域规则在 core/chart/custom_charts.dart,DAO 只管存取。
@DriftAccessor(tables: [CustomCharts])
class CustomChartsDao extends DatabaseAccessor<AppDatabase>
    with _$CustomChartsDaoMixin {
  CustomChartsDao(super.db);

  /// 入库(工单 16 导入管线的落库口;校验在解析层,此处不设防)。
  /// 返回自增 id。
  Future<int> add({required String title, required String source}) {
    return into(
      customCharts,
    ).insert(CustomChartsCompanion.insert(title: title, source: source));
  }

  /// 按曲名查单行(工单 16 同名重复导入的判定面;曲名精确匹配)。
  /// 无则 null;同名多行(「两个都保留」的产物)取最早入库行——
  /// 「覆盖原谱」覆盖的就是最早那份。
  Future<CustomChart?> getByTitle(String title) {
    return (select(customCharts)
          ..where((row) => row.title.equals(title))
          ..orderBy([(row) => OrderingTerm.asc(row.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 覆盖写(工单 16 同名重复导入的「覆盖原谱」处置):按 id 整行替换
  /// 曲名与源文本。读出侧照过校验闸,此处不设防。
  Future<void> overwrite({
    required int id,
    required String title,
    required String source,
  }) {
    return (update(customCharts)..where((row) => row.id.equals(id))).write(
      CustomChartsCompanion.insert(title: title, source: source),
    );
  }

  /// 按 id 硬删(工单 32 删除入口;流订阅端卡片即时退场)。
  Future<void> deleteById(int id) {
    return (delete(customCharts)..where((row) => row.id.equals(id))).go();
  }

  /// 全部自建谱,按入库序(id 升序)。
  Future<List<CustomChart>> getAll() {
    return (select(customCharts)..orderBy([(row) => OrderingTerm.asc(row.id)]))
        .get();
  }

  /// 响应式自建谱流:曲库页订阅,导入/录入写入即自动入列。
  Stream<List<CustomChart>> watchAll() {
    return (select(customCharts)..orderBy([(row) => OrderingTerm.asc(row.id)]))
        .watch();
  }
}
