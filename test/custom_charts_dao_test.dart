import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/custom_charts_dao.dart';
import 'package:ukeflow/data/database.dart';

/// 工单 15 曲库数据源:自建谱 DAO 内存库测试(入库、响应式流)。
/// 「导入即自动入列」的数据面在这验证;UI 呈现在 library_page_test。
void main() {
  late AppDatabase db;
  late CustomChartsDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.customChartsDao;
  });
  tearDown(() async => db.close());

  test('入库:曲名与源文本原样落库,id 自增', () async {
    final id = await dao.add(title: '我的歌', source: '{title: 我的歌}\n[C]词\n');
    expect(id, 1);
    final rows = await dao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.title, '我的歌');
    expect(rows.single.source, '{title: 我的歌}\n[C]词\n');
  });

  test('watchAll 响应式:入库即推送,按入库序(id 升序)', () async {
    // 首笔先写后订(checkins_dao_test 同款确定形态):订阅首帧拿当下库态,
    // 不与写入竞速;写入序 ≠ 展示序,流按 id 升序排。
    await dao.add(title: '第二首', source: '[C]词\n');
    final expectation = expectLater(
      dao.watchAll(),
      emitsInOrder([
        predicate<List<CustomChart>>(
          (rows) => rows.single.title == '第二首',
          '初态:仅第二首',
        ),
        predicate<List<CustomChart>>(
          (rows) =>
              rows.length == 2 &&
              rows[0].title == '第二首' &&
              rows[1].title == '第一首',
          '再入库第一首,仍按 id 升序(与内置谱区的阅读序一致)',
        ),
      ]),
    );
    await dao.add(title: '第一首', source: '[Am]词\n');
    await expectation;
  });
}
