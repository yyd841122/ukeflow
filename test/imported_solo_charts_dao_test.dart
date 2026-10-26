import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/imported_solo_charts_dao.dart';

/// 工单 43 曲库数据源:导入独奏谱 DAO 内存库测试(入库、内容指纹、
/// 响应式流)。读出侧解析/物化在 core/import 与 provider 测试验。
void main() {
  late AppDatabase db;
  late ImportedSoloChartsDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.importedSoloChartsDao;
  });
  tearDown(() async => db.close());

  test('入库:全字段原样落库,contentSha 现算,id 自增', () async {
    final source = '{"schemaVersion":1,"id":"x"}';
    final before = DateTime.now();
    final id = await dao.add(
      title: '我的独奏',
      sourceJson: source,
      schemaVersion: 1,
      reviewedAt: '2026-10-26T10:00:00.000',
    );
    final after = DateTime.now();

    expect(id, 1);
    final row = (await dao.getAll()).single;
    expect(row.title, '我的独奏');
    expect(row.sourceJson, source);
    expect(row.schemaVersion, 1);
    expect(row.reviewedAt, '2026-10-26T10:00:00.000');
    expect(
      row.contentSha,
      sha256.convert(utf8.encode(source)).toString(),
      reason: '内容指纹 = 源 JSON 的 sha256',
    );
    // drift 的 dateTime 列按秒精度存 UTC:亚秒截断后落库时刻可能落在
    // before 之前,容差放宽到 1 秒。
    expect(
      row.createdAt.isBefore(before.add(const Duration(seconds: 1))),
      isTrue,
      reason: 'createdAt = 落库时刻',
    );
    expect(
      row.updatedAt.isBefore(after.add(const Duration(seconds: 1))),
      isTrue,
      reason: 'updatedAt = 落库时刻',
    );
  });

  test('入库:reviewedAt 缺省 = null(源未带复核状态)', () async {
    await dao.add(title: 'x', sourceJson: '{}', schemaVersion: 1);
    expect((await dao.getAll()).single.reviewedAt, isNull);
  });

  test('getAll/watchAll 按入库序(id 升序),写入即推送', () async {
    await dao.add(title: '第二首', sourceJson: '{}', schemaVersion: 1);
    final expectation = expectLater(
      dao.watchAll(),
      emitsInOrder([
        predicate<List<ImportedSoloChart>>(
          (rows) => rows.single.title == '第二首',
          '初态:仅第二首',
        ),
        predicate<List<ImportedSoloChart>>(
          (rows) =>
              rows.length == 2 &&
              rows[0].title == '第二首' &&
              rows[1].title == '第一首',
          '再入库第一首,仍按 id 升序(内置谱区的阅读序同款)',
        ),
      ]),
    );
    await dao.add(title: '第一首', sourceJson: '{}', schemaVersion: 1);
    await expectation;
  });

  group('轻改存回(工单 45)', () {
    test('updateSource:源 JSON/contentSha/updatedAt/reviewedAt 随写随 bump,'
        '其余字段不动,watchAll 推送', () async {
      final source = '{"schemaVersion":1,"id":"x"}';
      final id = await dao.add(
        title: '我的独奏',
        sourceJson: source,
        schemaVersion: 1,
        reviewedAt: '2026-10-26T10:00:00.000',
      );
      final created = (await dao.getAll()).single.createdAt;

      final updated = '$source,"edited":true';
      await dao.updateSource(
        id: id,
        sourceJson: updated,
        reviewedAt: '2026-10-26T11:00:00.000',
      );

      final row = (await dao.getAll()).single;
      expect(row.sourceJson, updated);
      expect(
        row.contentSha,
        sha256.convert(utf8.encode(updated)).toString(),
        reason: 'contentSha 随新源现算(改源漂移检测面)',
      );
      expect(
        row.reviewedAt,
        '2026-10-26T11:00:00.000',
        reason: '轻改自动记 reviewedAt',
      );
      expect(row.title, '我的独奏', reason: '入库名不随轻改变');
      expect(row.schemaVersion, 1);
      expect(row.createdAt, created, reason: 'createdAt 不动');
      expect(
        row.updatedAt.isBefore(row.createdAt),
        isFalse,
        reason: 'updatedAt bump 到落库时刻(秒精度下 ≥ createdAt)',
      );
    });
  });

  group('重导入查重(工单 44)', () {
    test('shaOf:静态指纹与入库 contentSha 同源', () async {
      const source = '{"schemaVersion":1,"id":"x"}';
      await dao.add(title: 'a', sourceJson: source, schemaVersion: 1);
      expect(
        (await dao.getAll()).single.contentSha,
        ImportedSoloChartsDao.shaOf(source),
        reason: '查重与入库必须用同一指纹函数(重导入去重的判定面)',
      );
    });

    test('getByContentSha:命中返回行,未命中 null', () async {
      const source = '{"schemaVersion":1,"id":"x"}';
      await dao.add(title: '已有谱', sourceJson: source, schemaVersion: 1);

      final hit = await dao.getByContentSha(
        ImportedSoloChartsDao.shaOf(source),
      );
      expect(hit, isNotNull);
      expect(hit!.title, '已有谱');

      expect(await dao.getByContentSha('no-such-sha'), isNull);
    });
  });
}
