import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/scoring/calibration.dart';
import 'package:ukeflow/core/scoring/strum_scorer.dart';

/// 预备数拍延迟校准核(GLOSSARY「延迟校准」):matched 对的误差取中位数。
void main() {
  ScoredPair pair(double errSec) => (0, 0, errSec);

  test('奇数个:取正中', () {
    expect(calibrateLatencySec([pair(0.12), pair(0.08), pair(0.20)]), 0.12);
  });

  test('偶数个:取中间两数均值', () {
    expect(
      calibrateLatencySec([pair(0.10), pair(0.14), pair(0.06), pair(0.30)]),
      closeTo(0.12, 1e-12),
    );
  });

  test('单个:即取该值(用户只扫了一下也校准)', () {
    expect(calibrateLatencySec([pair(-0.05)]), -0.05);
  });

  test('空:返回 null(采不到 → 调用方退回持久化值)', () {
    expect(calibrateLatencySec(const []), isNull);
  });

  test('负偏移(用户抢拍/短链路)原样返回,不钳符号', () {
    expect(calibrateLatencySec([pair(-0.02), pair(-0.04), pair(-0.03)]), -0.03);
  });
}
