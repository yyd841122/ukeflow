import 'package:drift/drift.dart';

import 'database.dart';

part 'image_charts_dao.g.dart';

/// 图片谱数据访问(工单 18,GLOSSARY「图片谱」)。
/// 入库前的解码验真在 core/chart/image_ingest.dart,DAO 只管存取。
@DriftAccessor(tables: [ImageCharts])
class ImageChartsDao extends DatabaseAccessor<AppDatabase>
    with _$ImageChartsDaoMixin {
  ImageChartsDao(super.db);

  /// 入库(相册选图流程的落库口;字节已在流程层验过,此处不设防)。
  /// 返回自增 id。
  Future<int> add({required String title, required Uint8List image}) {
    return into(
      imageCharts,
    ).insert(ImageChartsCompanion.insert(title: title, image: image));
  }

  /// 按 id 硬删(工单 32 删除入口;流订阅端卡片即时退场)。
  Future<void> deleteById(int id) {
    return (delete(imageCharts)..where((row) => row.id.equals(id))).go();
  }

  /// 改名只更新标题(工单 32 改名入口;原图与记录 id 不动)。
  Future<void> renameTitle(int id, String title) {
    return (update(imageCharts)..where((row) => row.id.equals(id))).write(
      ImageChartsCompanion(title: Value(title)),
    );
  }

  /// 全部图片谱,按入库序(id 升序)。
  Future<List<ImageChart>> getAll() {
    return (select(
      imageCharts,
    )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
  }

  /// 响应式图片谱流:曲库页订阅,选图入库即自动入列。
  Stream<List<ImageChart>> watchAll() {
    return (select(
      imageCharts,
    )..orderBy([(row) => OrderingTerm.asc(row.id)])).watch();
  }
}
