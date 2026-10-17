import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/image_charts_dao.dart';

/// 工单 18 图片谱数据源:相册图片谱 DAO 内存库测试(入库、响应式流)。
/// 图片字节整块落库(BLOB):备份(票 21,单 JSON 导出)天然携带,
/// 不散落应用目录文件。UI 呈现在 library_page_test。
void main() {
  late AppDatabase db;
  late ImageChartsDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.imageChartsDao;
  });
  tearDown(() async => db.close());

  test('入库:曲名与图片字节原样落库,id 自增', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final id = await dao.add(title: '相册谱一', image: bytes);
    expect(id, 1);
    final rows = await dao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.title, '相册谱一');
    expect(rows.single.image, bytes);
  });

  test('watchAll 响应式:入库即推送,按入库序(id 升序)', () async {
    // 首笔先写后订(custom_charts_dao_test 同款确定形态)。
    await dao.add(title: '第二张', image: Uint8List.fromList([2]));
    final expectation = expectLater(
      dao.watchAll(),
      emitsInOrder([
        predicate<List<ImageChart>>(
          (rows) => rows.single.title == '第二张',
          '初态:仅第二张',
        ),
        predicate<List<ImageChart>>(
          (rows) =>
              rows.length == 2 &&
              rows[0].title == '第二张' &&
              rows[1].title == '第一张',
          '再入库第一张,仍按 id 升序',
        ),
      ]),
    );
    await dao.add(title: '第一张', image: Uint8List.fromList([1]));
    await expectation;
  });
}
