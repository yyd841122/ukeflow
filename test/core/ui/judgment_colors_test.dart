import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/scoring/strum_scorer.dart';
import 'package:ukeflow/core/ui/judgment_colors.dart';

/// 判定四色单源(工单 36):准绿/错红/晚黄/早蓝/漏灰,固定语义色不随
/// 主题变换,跟练页箭头条与报告页全部着色共用(一色一义,红归「错」)。
void main() {
  test('五判定 → 固定语义色(深浅主题同一套)', () {
    expect(judgmentColor(StrumJudgment.onTime), judgmentOnTimeColor);
    expect(judgmentColor(StrumJudgment.wrong), judgmentWrongColor);
    expect(judgmentColor(StrumJudgment.late), judgmentLateColor);
    expect(judgmentColor(StrumJudgment.early), judgmentEarlyColor);
    expect(judgmentColor(StrumJudgment.missed), judgmentMissedColor);
  });

  test('色相各归其位:绿/红/黄/蓝/灰,五色互不重复', () {
    final colors = [
      judgmentOnTimeColor,
      judgmentWrongColor,
      judgmentLateColor,
      judgmentEarlyColor,
      judgmentMissedColor,
    ];
    expect(colors.toSet(), hasLength(5), reason: '一色一义,不得撞色');
    // 色相语义(票面:准绿/错红/晚黄/早蓝/漏灰)——hue 兜底,防误改成近似色。
    expect(
      HSLColor.fromColor(judgmentOnTimeColor).hue,
      inInclusiveRange(90, 160),
      reason: '准 = 绿',
    );
    final wrongHue = HSLColor.fromColor(judgmentWrongColor).hue;
    expect(
      wrongHue <= 15 || wrongHue >= 330,
      isTrue,
      reason: '错 = 红(hue 环绕 0°)',
    );
    expect(
      HSLColor.fromColor(judgmentLateColor).hue,
      inInclusiveRange(30, 60),
      reason: '晚 = 黄',
    );
    expect(
      HSLColor.fromColor(judgmentEarlyColor).hue,
      inInclusiveRange(190, 230),
      reason: '早 = 蓝',
    );
    expect(
      HSLColor.fromColor(judgmentMissedColor).saturation,
      lessThan(0.1),
      reason: '漏 = 灰(无色相)',
    );
  });
}
