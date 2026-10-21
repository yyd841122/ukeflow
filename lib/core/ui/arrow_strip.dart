import 'package:flutter/material.dart';

import '../model/strum_pattern.dart';
import '../scoring/strum_scorer.dart';
import 'judgment_colors.dart';

/// 一小节 8 槽一行均分的扫弦箭头条(工单 09/19 评审提取:节奏型训练页与
/// 弹唱跟练视图的公共件;视觉语言两处一致)。
///
/// 扫弦槽画 ↓/↑,空拍槽画小圆点;当前槽主色填充(当前动作突出),本小节
/// 已扫槽淡出,未到槽描边待命。传入判定列表时(工单 36,跟练评分)按
/// 判定当场染色:准绿/早蓝/晚黄/错红填充,漏灰空心描边——判定色优先于
/// 当前/已扫样式(反馈优先),未定槽位保持原样式。无时钟无动画:状态全
/// 由调用方按引擎时刻算好灌入(ADR-0005 薄渲染),本组件自己不产生任何时间。
class ArrowStrip extends StatelessWidget {
  const ArrowStrip({
    super.key,
    required this.pattern,
    required this.currentSlot,
    this.slotKeyPrefix = 'arrow-slot',
    this.verdicts,
  });

  /// 槽位排布来源(时间轴编译所用的同一节奏型)。
  final StrumPattern pattern;

  /// 当前点亮槽位;null = 跨小节空档,整行回描边待命。
  final int? currentSlot;

  /// 槽位测试 key 前缀(节奏型训练页 'arrow-slot'、跟练视图 'play-slot',
  /// 两页各自带回归测试,key 不共用)。
  final String slotKeyPrefix;

  /// 各槽位实时判定(与 [StrumPattern.slots] 同序;null = 未定/无评分);
  /// 槽级 null 元素 = 该槽还没判,不着色。
  final List<StrumJudgment?>? verdicts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var slot = 0; slot < eighthsPerBar; slot++) ...[
          if (slot > 0) const SizedBox(width: 6),
          Expanded(
            child: _slotCell(slot, scheme),
          ),
        ],
      ],
    );
  }

  Widget _slotCell(int slot, ColorScheme scheme) {
    final current = currentSlot;
    final isCurrent = current == slot;
    final isPlayed = current != null && slot < current;
    final stroke = pattern.slots[slot];
    final verdict = verdicts == null ? null : verdicts![slot];
    final Color fill;
    final Color content;
    final Border? border;
    if (verdict != null) {
      // 判定染色(工单 36):一色一义,漏=灰空心,其余填充语义色
      //(底/内容搭配同源 judgment_colors)。
      final color = judgmentColor(verdict);
      if (verdict == StrumJudgment.missed) {
        fill = Colors.transparent;
        content = color;
        border = Border.all(color: color);
      } else {
        fill = color;
        content = judgmentContentColor(verdict);
        border = null;
      }
    } else if (isCurrent) {
      fill = scheme.primary;
      content = scheme.onPrimary;
      border = null;
    } else if (isPlayed) {
      fill = scheme.surfaceContainerHighest;
      content = scheme.onSurfaceVariant;
      border = null;
    } else {
      fill = Colors.transparent;
      content = scheme.onSurface;
      border = Border.all(color: scheme.outlineVariant);
    }
    return Container(
      key: Key('$slotKeyPrefix-$slot'),
      height: 52,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: border,
      ),
      child: Center(
        child: stroke == null
            ? Text('·', style: TextStyle(color: content, height: 1))
            : Icon(
                stroke == StrumDirection.down
                    ? Icons.arrow_downward
                    : Icons.arrow_upward,
                color: content,
                size: 26,
              ),
      ),
    );
  }
}
