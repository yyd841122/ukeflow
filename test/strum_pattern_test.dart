import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';
import 'package:ukeflow/core/model/strum_pattern.dart';

/// 节奏型模型与内置集合:数据契约(工单 08 时间轴编译直接消费)。
void main() {
  group('StrumPattern 模型', () {
    test('strokes 按槽位顺序给出非空动作', () {
      const pattern = StrumPattern(
        id: 't',
        name: '测',
        slots: [
          StrumDirection.down,
          null,
          StrumDirection.down,
          StrumDirection.up,
          null,
          null,
          null,
          null,
        ],
      );
      expect(pattern.strokes, [
        (0, StrumDirection.down),
        (2, StrumDirection.down),
        (3, StrumDirection.up),
      ]);
    });
  });

  group('内置节奏型集合', () {
    test('至少 3 种可选(工单验收)', () {
      expect(builtinStrumPatterns.length, greaterThanOrEqualTo(3));
    });

    test('id 唯一、名字非空、槽位数齐整', () {
      final ids = <String>{};
      for (final pattern in builtinStrumPatterns) {
        expect(pattern.id, isNotEmpty);
        expect(ids.add(pattern.id), isTrue, reason: '${pattern.id} 重复');
        expect(pattern.name, isNotEmpty);
        expect(pattern.slots, hasLength(eighthsPerBar));
      }
    });

    test('挥拍物理:偶数槽只会是下扫、奇数槽只会是上扫(连续摆不失序)', () {
      for (final pattern in builtinStrumPatterns) {
        for (var slot = 0; slot < eighthsPerBar; slot++) {
          final stroke = pattern.slots[slot];
          if (stroke == null) continue;
          final expected = slot.isEven
              ? StrumDirection.down
              : StrumDirection.up;
          expect(
            stroke,
            expected,
            reason: '${pattern.name} 槽 $slot 的 $stroke 违反挥拍方向',
          );
        }
      }
    });

    test('「下 下上 上下上」(岛国节奏型)逐槽精确', () {
      final island = builtinStrumPatterns.singleWhere(
        (p) => p.name == '下 下上 上下上',
      );
      expect(island.slots, [
        StrumDirection.down, // 拍 1
        null, // 1 &
        StrumDirection.down, // 拍 2
        StrumDirection.up, // 2 &
        null, // 拍 3(空:手继续摆但不触弦)
        StrumDirection.up, // 3 &
        StrumDirection.down, // 拍 4
        StrumDirection.up, // 4 &
      ]);
      expect(island.strokes, hasLength(6));
    });
  });
}
