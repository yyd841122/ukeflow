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
