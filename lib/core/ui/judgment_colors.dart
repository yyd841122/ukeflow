/// 判定四色单源(工单 36):五判定的着色映射,跟练页箭头条槽位与报告页
/// (轨道/最差三处/图例)共用的唯一来源。票面共识:
/// - **一色一义**:红归「错」,漏让灰(空心描边);早/晚分蓝/黄,
///   不再共色(报告页旧映射 onTime=primary/早晚=tertiary/wrong=
///   secondary/missed=error 由此退役);
/// - **固定语义色**:不随深浅主题变换,两套主题下都按可读挑的定值。
library;

import 'package:flutter/material.dart';

import '../scoring/strum_scorer.dart';

/// 准(时机在准窗内)。
const Color judgmentOnTimeColor = Color(0xFF388E3C);

/// 错(响了但和弦不对)。
const Color judgmentWrongColor = Color(0xFFD32F2F);

/// 晚(听到了,偏晚出准窗)。
const Color judgmentLateColor = Color(0xFFF9A825);

/// 早(听到了,偏早出准窗)。
const Color judgmentEarlyColor = Color(0xFF1976D2);

/// 漏(容差窗内没听到)。
const Color judgmentMissedColor = Color(0xFF757575);

/// 判定 → 语义色(本库四色 + 漏灰的唯一映射)。
Color judgmentColor(StrumJudgment judgment) => switch (judgment) {
  StrumJudgment.onTime => judgmentOnTimeColor,
  StrumJudgment.wrong => judgmentWrongColor,
  StrumJudgment.late => judgmentLateColor,
  StrumJudgment.early => judgmentEarlyColor,
  StrumJudgment.missed => judgmentMissedColor,
};

/// 判定色**填充底**上的内容色(箭头/文字):黄底白字不可读换深色,
/// 其余白。与 [judgmentColor] 成对使用,别处不要自配底/内容搭配。
Color judgmentContentColor(StrumJudgment judgment) =>
    judgment == StrumJudgment.late ? Colors.black87 : Colors.white;
