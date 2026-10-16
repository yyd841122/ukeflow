import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/features/library/cifraclub_urls.dart';

void main() {
  group('CifraClubUrls', () {
    test('站内搜索 URL:q 参数编码', () {
      expect(
        CifraClubUrls.search('beat it').toString(),
        'https://www.cifraclub.com.br/busca/?q=beat+it',
      );
    });

    test('曲谱页判定:艺人/歌曲两段路径', () {
      expect(
        CifraClubUrls.isSongPage(
          Uri.parse('https://www.cifraclub.com.br/embrace/gravity/'),
        ),
        isTrue,
      );
      expect(
        CifraClubUrls.isSongPage(
          Uri.parse('https://www.cifraclub.com.br/michael-jackson/beat-it/'),
        ),
        isTrue,
      );
    });

    test('非曲谱页:首页/艺人页/搜索/站务路径/外站', () {
      bool song(String url) =>
          CifraClubUrls.isSongPage(Uri.parse(url));
      expect(song('https://www.cifraclub.com.br/'), isFalse);
      expect(song('https://www.cifraclub.com.br/embrace/'), isFalse);
      expect(
        song('https://www.cifraclub.com.br/busca/?q=beat+it'),
        isFalse,
      );
      expect(
        song('https://www.cifraclub.com.br/assine/'),
        isFalse,
      );
      expect(
        song('https://www.cifraclub.com.br/mais-acessadas/'),
        isFalse,
      );
      expect(song('https://example.com/embrace/gravity/'), isFalse);
      expect(
        song('https://www.cifraclub.com.br/embrace/gravity.jpg'),
        isFalse,
      );
      // 仿冒域:x-cifraclub.com.br 也是 endsWith 命中——必须整段等值或
      // 点分后缀,否则非 Cifra Club 页面能跑同一提取管线(ADR-0002)。
      expect(song('https://x-cifraclub.com.br/embrace/gravity/'), isFalse);
    });

    test('曲谱页变体:versao 备选版与乐器子路径仍在,未知三段路径不出', () {
      bool song(String url) =>
          CifraClubUrls.isSongPage(Uri.parse(url));
      expect(
        song('https://www.cifraclub.com.br/embrace/gravity/versao/12345/'),
        isTrue,
      );
      expect(
        song('https://www.cifraclub.com.br/embrace/gravity/ukulele/'),
        isTrue,
      );
      expect(
        song('https://www.cifraclub.com.br/embrace/gravity/whatever/'),
        isFalse,
      );
    });

    group('linkOrNull(搜索框输入解析:粘贴链接导入路径)', () {
      test('http(s) 链接原样返回,其余(关键词/危险 scheme)归搜索', () {
        expect(
          CifraClubUrls.linkOrNull(
            'https://www.cifraclub.com.br/michael-jackson/beat-it/ukulele/',
          ).toString(),
          'https://www.cifraclub.com.br/michael-jackson/beat-it/ukulele/',
        );
        expect(
          CifraClubUrls.linkOrNull('http://www.cifraclub.com.br/')!.host,
          'www.cifraclub.com.br',
        );
        expect(CifraClubUrls.linkOrNull('beat it'), isNull);
        expect(CifraClubUrls.linkOrNull('javascript:alert(1)'), isNull,
            reason: '非 http(s) scheme 一律当关键词,防 WebView scheme 注入');
        expect(CifraClubUrls.linkOrNull('file:///etc/hosts'), isNull);
      });
    });

    group('ukuleleVariant(导入优先取 ukulele 版)', () {
      test('标准两段曲谱页 → 拼 /ukulele/ 后缀,查询串不带过去', () {
        expect(
          CifraClubUrls.ukuleleVariant(
            Uri.parse('https://www.cifraclub.com.br/abba/dancing-queen/'),
          ).toString(),
          'https://www.cifraclub.com.br/abba/dancing-queen/ukulele/',
        );
        expect(
          CifraClubUrls.ukuleleVariant(
            Uri.parse(
              'https://www.cifraclub.com.br/abba/dancing-queen?x=1',
            ),
          ).toString(),
          'https://www.cifraclub.com.br/abba/dancing-queen/ukulele/',
        );
      });

      test('已是 ukulele 页 / versao 变体页 / 非两段页 → null(不猜变体)', () {
        Uri? v(String url) =>
            CifraClubUrls.ukuleleVariant(Uri.parse(url));
        expect(
          v('https://www.cifraclub.com.br/abba/dancing-queen/ukulele/'),
          isNull,
        );
        expect(
          v('https://www.cifraclub.com.br/embrace/gravity/versao/123/'),
          isNull,
        );
        expect(v('https://www.cifraclub.com.br/abba/'), isNull);
        expect(v('https://www.cifraclub.com.br/'), isNull);
      });
    });
  });
}
