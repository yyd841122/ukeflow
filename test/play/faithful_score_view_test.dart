import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/features/play/faithful_score_view.dart';

/// 票05:原谱 HTML 结构自检(入 WebView 前的防御面)——三要素缺失给
/// 可读错误,不进 WebView 白屏。
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
}
