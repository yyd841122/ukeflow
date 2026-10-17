import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:ukeflow/data/database.dart';
import 'package:ukeflow/data/image_charts_dao.dart';
import 'package:ukeflow/features/library/image_pick_flow.dart';

import 'helpers/image_fixtures.dart';

/// 工单 18 相册选图流程控制器:picker 注入(测试不碰平台通道),
/// 三路可测——取消(静默)、坏图(可读失败、不落库)、好图(出建议名)。
/// 真解码走测试引擎(普通 test,真异步),与生产同一条 validateImageBytes;
/// 命名→落库的 UI 链在 library_page_test 全链路测试覆盖。
void main() {
  late AppDatabase db;
  late ImageChartsDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.imageChartsDao;
  });
  tearDown(() async => db.close());

  test('用户取消:静默返回,库里无新增', () async {
    final flow = ImagePickFlow(pick: () async => null);
    final outcome = await flow.pickAndValidate();
    expect(outcome, isA<ImagePickCancelled>());
    expect(await dao.getAll(), isEmpty);
  });

  test('坏图(文本冒充):可读失败,库里无新增', () async {
    final flow = ImagePickFlow(
      pick: () async => (bytes: notImageBytes, name: 'fake.png'),
    );
    final outcome = await flow.pickAndValidate();
    expect(outcome, isA<ImagePickFailed>());
    final failed = outcome as ImagePickFailed;
    expect(failed.message, isNotEmpty);
    expect(await dao.getAll(), isEmpty);
  });

  test('好图:出建议名(文件名去扩展名)', () async {
    final flow = ImagePickFlow(
      pick: () async => (bytes: tinyPngBytes, name: 'my-chart.png'),
    );
    final outcome = await flow.pickAndValidate();
    expect(outcome, isA<ImagePicked>());
    expect((outcome as ImagePicked).suggestedTitle, 'my-chart');
  });

  test('好图无文件名:建议名为空,命名交给对话框', () async {
    final flow = ImagePickFlow(
      pick: () async => (bytes: tinyPngBytes, name: null),
    );
    final outcome = await flow.pickAndValidate();
    expect((outcome as ImagePicked).suggestedTitle, isNull);
  });

  test('选图平台异常:可读失败(重试指引,不提不可能的权限操作)', () async {
    final flow = ImagePickFlow(
      pick: () async => throw StateError('选择器打不开'),
    );
    final outcome = await flow.pickAndValidate();
    expect(outcome, isA<ImagePickFailed>());
    expect((outcome as ImagePickFailed).message, contains('请再试一次'));
    expect(await dao.getAll(), isEmpty);
  });
}
