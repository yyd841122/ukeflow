import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/features/play/faithful_score_view.dart';

import '../helpers/fake_webview_platform.dart' show containsStripContent;

/// 票05:原谱 HTML 结构自检(入 WebView 前的防御面)——三要素缺失给
/// 可读错误,不进 WebView 白屏。
///
/// 票08 追加:横带几何/染色列网格/包装页纯函数测试(曲头左余量、
/// 幂等染色指令、列桶边界)。
void main() {
  const good = '<!DOCTYPE html><html><body>'
      '<style>@font-face { font-family: alphaTab; }</style>'
      '<div class="at-surface"><svg></svg></div></body></html>';

  test('完好包装:无问题', () {
    expect(faithfulHtmlProblem(good), isNull);
  });

  test('缺渲染面:可读错误', () {
    expect(faithfulHtmlProblem('<style>@font-face{}</style>'), isNotNull);
  });

  test('缺字体声明:可读错误', () {
    expect(
      faithfulHtmlProblem('<div class="at-surface"><svg/></div>'),
      isNotNull,
    );
  });

  // ── 票08:横带几何(2 小节 × 200px,每小节 4 拍)──────────────────

  const data = FaithfulStripData(
    css: '<style>@font-face{}</style>',
    stripSvg: '<svg xmlns="http://www.w3.org/2000/svg" width="400" '
        'height="148" viewBox="0 0 400 148"></svg>',
    metaJson: '{"width":400,"height":148,'
        '"bars":[{"bar":1,"x":0.0,"w":200.0},{"bar":2,"x":200.0,"w":200.0}]}',
    width: 400,
    height: 148,
    bars: [FaithfulStripBar(0, 200), FaithfulStripBar(200, 200)],
  );

  group('票08 横带拍位几何 faithfulStripBeatX', () {
    test('拍 → 内容 x:小节线性 + 小节内线性', () {
      expect(faithfulStripBeatX(data, 0), 0);
      expect(faithfulStripBeatX(data, 1), 50); // 每拍 50px
      expect(faithfulStripBeatX(data, 4), 200); // 第 2 小节头
      expect(faithfulStripBeatX(data, 4.5), 225);
    });

    test('负拍(预备期)钳 0;超出末小节钳末缘', () {
      expect(faithfulStripBeatX(data, -3), 0);
      expect(faithfulStripBeatX(data, 100), 400);
    });
  });

  group('票08 染色列网格', () {
    test('八分网格:每小节 8 列,边界与滚动同插值', () {
      final bounds = faithfulStripColumnBounds(data);
      expect(bounds.length, 2 * 8 + 1); // 2 小节 × 8 列,含末缘
      expect(bounds.first, 0);
      expect(bounds[4], 100); // 第 4 列 = 第 2 拍
      expect(bounds[8], 200); // 第 8 列 = 第 2 小节头
      expect(bounds.last, 400);
      for (var i = 1; i < bounds.length; i++) {
        expect(bounds[i], greaterThanOrEqualTo(bounds[i - 1]),
            reason: '列边界须单调($i)');
      }
    });

    test('列号:负拍 -1;半拍一列;越界钳两端', () {
      expect(stripColorColumn(-2, 16), -1);
      expect(stripColorColumn(0, 16), 0);
      expect(stripColorColumn(0.4, 16), 0);
      expect(stripColorColumn(0.5, 16), 1);
      expect(stripColorColumn(1.9, 16), 3);
      expect(stripColorColumn(999, 16), 15);
    });
  });

  group('票08 染色驱动 StripColorDriver(幂等重发自愈)', () {
    test('列不变不下发;列推进/倒退(回到开头)照发', () {
      final driver = StripColorDriver();
      expect(driver.update(0.2, 16), 0); // 首发第 0 列
      expect(driver.update(0.3, 16), isNull); // 同列去重
      expect(driver.update(0.6, 16), 1); // 推进
      expect(driver.update(99, 16), 15); // 越界钳末列
      expect(driver.update(0.1, 16), 0); // 倒退照发(回到开头)
      expect(driver.last, 0);
    });

    test('预备期 -1 全还原;空列网格不驱动;reset 清态', () {
      final driver = StripColorDriver();
      expect(driver.update(-3, 16), -1);
      expect(driver.update(-1, 16), isNull); // 预备期内去重
      expect(driver.update(0, 16), 0);
      driver.reset();
      expect(driver.last, isNull);
      expect(driver.update(1, 0), isNull, reason: '空横带(坏 meta)不驱动');
    });
  });

  group('票08 横带页包装 faithfulStripWrapper', () {
    test('曲头左余量/曲尾右余量按 Dart 视口宽烘死,禁 innerWidth', () {
      final html = faithfulStripWrapper(data, 360);
      expect(html, contains('padding-left:120.0px'), reason: '视口宽/3');
      expect(html, contains('padding-right:240.0px'), reason: '视口宽×2/3');
      expect(html.contains('innerWidth'), isFalse,
          reason: 'OEM innerWidth 报值不可信,页面几何一律 Dart 注入');
      expect(html, contains(data.stripSvg));
    });

    test('列边界随包装下发,染色指令绝对状态幂等', () {
      final html = faithfulStripWrapper(data, 360);
      expect(html, contains('var M={cols:['));
      expect(html, contains('0.0,25.0,50.0,75.0,100.0'), reason: '八分网格');
      // paint(n) 全量重刷(幂等),丢发由下一列重发自愈。
      expect(html, contains('UF.paint'));
      expect(html, contains("setAttribute('fill'"));
      expect(html, contains('#c8616d'), reason: '原站高亮红(视频帧取样)');
      expect(html, contains('document.fonts'), reason: '索引建在字体就绪后');
      expect(containsStripContent(html), isTrue, reason: '既有断言兼容');
    });
  });

  test('高亮红常量 = 原站线色/当弹字形色(视频 15 帧众数)', () {
    expect(faithfulHighlightRed, const Color(0xFFC8616D)); // RGB(200,97,109)
  });
}
