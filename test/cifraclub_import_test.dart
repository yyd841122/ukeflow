// 工单 27:导入编排从 CifraClubPage 提出(CifraClubImporter)后,离开
// 真机锁住时序语义——ukulele 优先/回退告知、导航令牌、落点核对、就绪
// 重试。全部走 fake driver 的真 async(无 fakeAsync,延时零值/1ms)。

import 'package:flutter_test/flutter_test.dart';
import 'helpers/cifraclub_fake_driver.dart';
import 'package:ukeflow/features/library/cifraclub_import.dart';

/// 合法提取产物(行是片段数组,和弦段 {c,s}、歌词段裸字符串)。
const songPayload = '{"title":"Beat It","artist":"Michael Jackson",'
    '"lines":[[{"c":"C","s":"C "}],["E lavou tudo"]]}';

const songUrl = 'https://www.cifraclub.com.br/michael-jackson/beat-it';
const songUkeUrl = '$songUrl/ukulele/';

/// 全部零等待(除 pageTimeout 给 1ms 让超时兜底即刻走完)。
const fast = CifraClubTimings(
  pageTimeout: Duration(milliseconds: 1),
  retryInterval: Duration.zero,
);

void main() {
  test('ukulele 优先:两段标准页先载 /ukulele/ 变体,提取成功不回退', () async {
    final driver = FakeCifraDriver()
      ..urls = [songUkeUrl]
      ..jsResults = [songPayload];
    final importer = CifraClubImporter(driver, timings: fast);

    final outcome = await importer.importSong(
      Uri.parse(songUrl),
      allowedChords: {'C'},
    );

    expect(driver.loaded, [Uri.parse(songUkeUrl)]);
    final ok = outcome as CifraImportOk;
    expect(ok.notice, isNull); // 提取到了,无需回退告知
    expect(ok.source, contains('{title: Beat It}'));
    expect(ok.source, contains('[C]'));
  });

  test('没有 ukulele 版:变体页提取落空 → 回退原版导入并中文告知', () async {
    final driver = FakeCifraDriver()
      // 变体页 404 壳:落点 URL 正确(不触发 wrong-page),但页里没谱。
      ..urls = [songUkeUrl, songUrl]
      ..jsResults = [
        // 变体页就绪重试 6 次全落空(每次消耗一条),回退原版一次就绪。
        '{"error":"no-chords"}',
        '{"error":"no-chords"}',
        '{"error":"no-chords"}',
        '{"error":"no-chords"}',
        '{"error":"no-chords"}',
        '{"error":"no-chords"}',
        songPayload,
      ];
    final importer = CifraClubImporter(driver, timings: fast);

    final outcome = await importer.importSong(
      Uri.parse(songUrl),
      allowedChords: {'C'},
    );

    expect(driver.loaded[1], Uri.parse(songUrl));
    final ok = outcome as CifraImportOk;
    expect(ok.notice, contains('已按原版导入'));
    expect(ok.source, contains('[C]'));
  });

  test('已是 ukulele 页:不猜变体也不导航,就地提取(评审落实:恢复 17 原语义)', () async {
    final driver = FakeCifraDriver()
      ..jsResults = [songPayload];
    final importer = CifraClubImporter(driver, timings: fast);

    final outcome = await importer.importSong(
      Uri.parse(songUkeUrl),
      allowedChords: {'C'},
    );

    expect(driver.loaded, isEmpty); // 就地提取,零导航
    expect(driver.scripts, isNotEmpty); // 但提取脚本跑了
    expect(outcome, isA<CifraImportOk>());
  });

  test('落点与请求不符(重定向去别页)→ wrong-page 可读失败,不提取', () async {
    final driver = FakeCifraDriver()
      ..urls = ['https://www.cifraclub.com.br/other-artist/other-song/'];
    final importer = CifraClubImporter(
      driver,
      timings: const CifraClubTimings(pageTimeout: Duration(milliseconds: 1)),
    );

    final outcome = await importer.importSong(
      Uri.parse('https://www.cifraclub.com.br/a/b/'),
      allowedChords: {'C'},
    );

    // 绝不拿旧页内容当目标谱:提取脚本一次都不跑。
    expect(driver.scripts, isEmpty);
    expect((outcome as CifraImportFail).message, contains('重定向'));
  });

  test('导航被新操作取代:uke 尝试作废走回退,回退提取拿的是原版页新内容', () async {
    final driver = FakeCifraDriver()
      ..urls = [
        // 出队序 = 核对序:第二个导入先核对落点,第一个的回退后核对。
        'https://www.cifraclub.com.br/c/d/ukulele/',
        songUrl,
      ];
    final importer = CifraClubImporter(driver, timings: fast);
    // 第一次导入的 uke 页刚载入,第二个导入启动(令牌+1,等待点被换)。
    late Object second;
    var secondStarted = false;
    driver.onLoaded = (_) async {
      if (secondStarted) return;
      secondStarted = true;
      second = await importer.importSong(
        Uri.parse('https://www.cifraclub.com.br/c/d/'),
        allowedChords: {'C'},
      );
    };
    // 消费序:第二个导入的提取 → 第一个导入回退原版的提取。两个载荷
    // 标题不同,证「结果不跨请求串线」。
    driver.jsResults = [
      '{"title":"Second Song","artist":"X","lines":[[{"c":"C","s":"C "}]]}',
      '{"title":"Original Song","artist":"Y","lines":[[{"c":"C","s":"C "}]]}',
    ];

    final first = await importer.importSong(
      Uri.parse(songUrl),
      allowedChords: {'C'},
    );

    expect(second, isA<CifraImportOk>());
    final ok = first as CifraImportOk;
    // uke 尝试 superseded ≠ 成功:按无 ukulele 版回退原版并告知;
    // 回退提取拿到的必须是原版页的新载荷,不是第二个导入的内容。
    expect(ok.notice, contains('已按原版导入'));
    expect(ok.source, contains('{title: Original Song}'));
    expect(ok.source, isNot(contains('Second Song')));
  });

  test('onPageFinished 不达:超时兜底后落点一致照常提取', () async {
    final driver = FakeCifraDriver()
      ..urls = [songUkeUrl]
      ..jsResults = [songPayload];
    // notePageFinished 永不被调(模拟回调早于监听挂上/丢失)。
    final importer = CifraClubImporter(
      driver,
      timings: const CifraClubTimings(pageTimeout: Duration(milliseconds: 1)),
    );

    final outcome = await importer.importSong(
      Uri.parse(songUrl),
      allowedChords: {'C'},
    );

    expect(outcome, isA<CifraImportOk>());
  });

  test('就绪重试:onPageFinished 早于 DOM 可用,提取失败按序重取到成功', () async {
    final driver = FakeCifraDriver()
      ..urls = [songUkeUrl]
      ..jsResults = [
        '{"error":"no-content"}',
        '{"error":"no-content"}',
        songPayload,
      ];
    final importer = CifraClubImporter(driver, timings: fast);

    final outcome = await importer.importSong(
      Uri.parse(songUrl),
      allowedChords: {'C'},
    );

    expect(driver.scripts.length, 3);
    expect(outcome, isA<CifraImportOk>());
  });

  test('驱动抛异常(WebView 桥错误)→ 可读失败不外抛', () async {
    final importer = CifraClubImporter(
      ThrowingCifraDriver(),
      timings: const CifraClubTimings(pageTimeout: Duration(milliseconds: 1)),
    );

    final outcome = await importer.importSong(
      Uri.parse(songUrl),
      allowedChords: {'C'},
    );

    final fail = outcome as CifraImportFail;
    expect(fail.message, contains('文本导入'));
    expect(fail.message, contains('Exception'));
  });
}

