import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/custom_charts_dao.dart';
import 'package:ukeflow/data/database.dart';

/// 工单 15 曲库数据源:自建谱 DAO 内存库测试(入库、响应式流)。
/// 「导入即自动入列」的数据面在这验证;UI 呈现在 library_page_test。
/// 工单 16 追加:重名查询(同名重复导入的判定面)与覆盖写(重复导入的
/// 「覆盖原谱」处置)。
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

  test('getByTitle:命中返回该行,未命中返回 null(重名判定面)', () async {
    await dao.add(title: '已有的歌', source: '[C]词\n');

    final hit = await dao.getByTitle('已有的歌');
    expect(hit, isNotNull);
    expect(hit!.source, '[C]词\n');

    expect(await dao.getByTitle('别的歌'), isNull);
  });

  test('getByTitle:同名多行(两个都保留的产物)不抛,返回最早入库行', () async {
    await dao.add(title: '重名歌', source: '[C]第一份\n');
    await dao.add(title: '重名歌', source: '[Am]第二份\n');

    final hit = await dao.getByTitle('重名歌');
    expect(hit, isNotNull);
    expect(hit!.source, '[C]第一份\n', reason: '覆盖原谱覆盖的是最早那份');
  });

  test('overwrite:按 id 覆盖曲名与源文本,其余行不动', () async {
    final keepId = await dao.add(title: '保留的歌', source: '[C]旧词\n');
    final replacedId = await dao.add(title: '被覆盖的歌', source: '[C]旧词\n');

    await dao.overwrite(
      id: replacedId,
      title: '被覆盖的歌',
      source: '[Am]新词\n',
    );

    final rows = await dao.getAll();
    expect(rows, hasLength(2));
    expect(
      rows.firstWhere((row) => row.id == replacedId).source,
      '[Am]新词\n',
    );
    expect(
      rows.firstWhere((row) => row.id == keepId).source,
      '[C]旧词\n',
      reason: '覆盖只动目标行',
    );
  });


  // ── 工单 32:删除(曲库页删除钮的落库口)──

  test('deleteById:按 id 硬删,其余行不动,流同步少一行', () async {
    final a = await dao.add(title: '留下的', source: '[C]词\n');
    final b = await dao.add(title: '删掉的', source: '[Am]词\n');
    await dao.deleteById(b);
    final rows = await dao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.id, a);
    expect(rows.single.title, '留下的');
    await expectLater(
      dao.watchAll(),
      emits(
        predicate<List<CustomChart>>(
          (rows) => rows.single.title == '留下的',
          '流推送删除后的库态',
        ),
      ),
    );
  });
}
