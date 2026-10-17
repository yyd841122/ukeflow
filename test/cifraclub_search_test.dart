// 工单 27:搜索编排(CifraClubSearcher)与结果解码的单测。
// 搜索不导航(真机实证 2026-10-17:页内 fetch solr 端点,CORS 全开):
// start 脚本 kick 页内 fetch(带页内 seq 防过期覆盖),poll 脚本读
// window 变量。JS 输出契约:{"status":"ok","hits":[{t,a,u,k}]} /
// {"status":"zero"} / {"status":"pending"}(还没回来/被导航清掉)。
// 全部 fake driver 真 async,延时注入零值。
import 'package:flutter_test/flutter_test.dart';
import 'helpers/cifraclub_fake_driver.dart';
import 'package:ukeflow/features/library/cifraclub_search.dart';
import 'package:ukeflow/features/library/cifraclub_search_js.dart';

const instant = CifraSearchTimings(
  firstPollDelay: Duration.zero,
  pollInterval: Duration.zero,
  window: Duration(seconds: 30),
  maxPolls: 8,
);

void main() {
  group('decodeCifraSearchPayload', () {
    test('ok 形状:命中条目映射(艺人可缺)', () {
      final read = decodeCifraSearchPayload(
        '{"status":"ok","hits":['
        '{"t":"Beat It","a":"Michael Jackson","u":"/mj/beat-it/"},'
        '{"t":"No Artist","u":"/x/y/"}]}',
      );
      final ok = read as CifraSearchOkRead;
      expect(ok.hits.length, 2);
      expect(ok.hits[0].title, 'Beat It');
      expect(ok.hits[0].artist, 'Michael Jackson');
      expect(ok.hits[0].path, '/mj/beat-it/');
      expect(ok.hits[1].artist, isNull);
    });

    test('zero / pending 各自成读', () {
      expect(decodeCifraSearchPayload('{"status":"zero"}'),
          isA<CifraSearchZeroRead>());
      expect(decodeCifraSearchPayload('{"status":"pending"}'),
          isA<CifraSearchPendingRead>());
    });

    test('Android 桥对字符串再包一层 JSON 引号也剥得开', () {
      final inner = '{"status":"zero"}';
      final wrapped = '"${inner.replaceAll('"', r'\"')}"';
      expect(decodeCifraSearchPayload(wrapped), isA<CifraSearchZeroRead>());
    });

    test('坏条目跳过;全坏/形状不对 → null(fail-closed,不假装零结果)', () {
      // 一坏一好:好的留下
      final mixed = decodeCifraSearchPayload(
        '{"status":"ok","hits":['
        '{"a":"没歌名","u":"/a/b/"},'
        '{"t":"Ok","u":"/ok/song/"}]}',
      ) as CifraSearchOkRead;
      expect(mixed.hits.map((h) => h.title), ['Ok']);

      // 全坏 / 非法 u / hits 不是列表 / status 未知 → null
      expect(
        decodeCifraSearchPayload('{"status":"ok","hits":[{"a":"x","u":"/a/"}]}'),
        isNull,
      );
      expect(
        decodeCifraSearchPayload(
            '{"status":"ok","hits":[{"t":"外链","u":"https://evil/x/y"}]}'),
        isNull,
      );
      expect(decodeCifraSearchPayload('{"status":"ok","hits":"x"}'), isNull);
      expect(decodeCifraSearchPayload('{"status":"wat"}'), isNull);
      expect(decodeCifraSearchPayload('garbage'), isNull);
    });

    test('同 u 重复条目按链接去重', () {
      final read = decodeCifraSearchPayload(
        '{"status":"ok","hits":['
        '{"t":"A","u":"/a/b/"},{"t":"A 重复","u":"/a/b/"}]}',
      ) as CifraSearchOkRead;
      expect(read.hits.length, 1);
      expect(read.hits[0].title, 'A');
    });
  });

  group('CifraClubSearcher', () {
    test('搜索不导航;start kick 一次,pending→ok 轮询到结果', () async {
      final driver = FakeCifraDriver()
        ..jsResults = [
          '{"status":"started"}', // start 脚本返回值,忽略
          '{"status":"pending"}',
          '{"status":"ok","hits":[{"t":"Let It Be","a":"The Beatles","u":"/the-beatles/let-it-be/"}]}',
        ];
      final searcher = CifraClubSearcher(driver, timings: instant);

      final outcome = await searcher.search('let it be');

      expect(driver.loaded, isEmpty); // 不导航
      expect(driver.scripts.first, contains('__ukeSeq')); // 第一发是 start
      final success = outcome as CifraSearchSuccess;
      expect(success.hits.single.title, 'Let It Be');
    });

    test('首次搜索撞上页面还在载入(window 变量被清):连续 pending 后 re-kick', () async {
      final driver = FakeCifraDriver()
        ..jsResults = [
          '{"status":"started"}',
          '{"status":"pending"}', // 导航把 window 变量清了,fetch 永不落
          '{"status":"pending"}',
          '{"status":"pending"}',
          '{"status":"started"}', // re-kick 后这一次拿到了
          '{"status":"ok","hits":[{"t":"X","u":"/a/b/"}]}',
        ];
      final searcher = CifraClubSearcher(
        driver,
        timings: const CifraSearchTimings(
          firstPollDelay: Duration.zero,
          pollInterval: Duration.zero,
          window: Duration(seconds: 30),
          maxPolls: 8,
        ),
      );

      final outcome = await searcher.search('x');

      expect(outcome, isA<CifraSearchSuccess>());
      final kicks = driver.scripts.where((s) => s.contains('__ukeSeq')).length;
      expect(kicks, 2); // 初次 + 连续 pending 后的重 kick
    });

    test('窗口内一直 pending → timeout 失败', () async {
      final driver = FakeCifraDriver()..jsResults = [
        '{"status":"started"}',
        for (var i = 0; i < 20; i++) '{"status":"pending"}',
      ];
      final searcher = CifraClubSearcher(
        driver,
        timings: const CifraSearchTimings(
          firstPollDelay: Duration.zero,
          pollInterval: Duration.zero,
          window: Duration(seconds: 30),
          maxPolls: 8,
        ),
      );

      final outcome = await searcher.search('zzz');

      expect((outcome as CifraSearchFailure).code, 'timeout');
      // 全 pending 时长轮询有界(maxPolls),消费数 == 1(start)+8(poll)+re-kick 数
    });

    test('站点明示零结果 → Empty(与 timeout 失败区分)', () async {
      final driver = FakeCifraDriver()
        ..jsResults = ['{"status":"started"}', '{"status":"zero"}'];
      final searcher = CifraClubSearcher(driver, timings: instant);

      final outcome = await searcher.search('zzzqqqxx');

      expect(outcome, isA<CifraSearchEmpty>());
    });

    test('页面不对(error 形状)≠ pending:按不可读轮询,窗口尽头 timeout', () async {
      final driver = FakeCifraDriver()..jsResults = [
        '{"status":"started"}',
        '{"error":"no-content"}',
      ];
      final searcher = CifraClubSearcher(
        driver,
        timings: const CifraSearchTimings(
          firstPollDelay: Duration.zero,
          pollInterval: Duration.zero,
          window: Duration(seconds: 30),
          maxPolls: 3,
        ),
      );

      final outcome = await searcher.search('q');

      expect((outcome as CifraSearchFailure).code, 'timeout');
    });

    test('新搜索取代旧搜索:旧的以 superseded 终止,不再读页面', () async {
      final driver = FakeCifraDriver();
      final searcher = CifraClubSearcher(driver, timings: instant);
      // 第一个搜索刚 kick 完,第二个搜索启动(令牌+1,旧令牌作废)。
      late Object second;
      var secondStarted = false;
      driver.onScript = (script) async {
        if (secondStarted || !script.contains('__ukeSeq')) return;
        secondStarted = true;
        driver.jsResults = [
          '{"status":"started"}', // 第二个搜索自己的 kick 消费
          '{"status":"ok","hits":[{"t":"B","u":"/b/c/"}]}',
        ];
        second = await searcher.search('second');
      };
      driver.jsResults = ['{"status":"pending"}'];

      final first = await searcher.search('first');

      expect(second, isA<CifraSearchSuccess>());
      expect((first as CifraSearchFailure).code, 'superseded');
    });

    test('驱动抛异常(页面还在导航)按不可读处理,窗口尽头 timeout', () async {
      final driver = ThrowingCifraDriver();
      final searcher = CifraClubSearcher(
        driver,
        timings: const CifraSearchTimings(
          firstPollDelay: Duration.zero,
          pollInterval: Duration.zero,
          window: Duration(seconds: 30),
          maxPolls: 3,
        ),
      );

      final outcome = await searcher.search('q');

      expect((outcome as CifraSearchFailure).code, 'timeout');
    });
  });

  test('两个脚本都含契约关键字(status/seq 句柄)', () {
    expect(cifraSearchStartScript("beat it"), contains('__ukeSeq'));
    expect(cifraSearchStartScript("beat it"), contains('solr.sscdn.co'));
    expect(cifraSearchPollScript, contains('__ukeSearch'));
  });
}

