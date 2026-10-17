import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/tuner/tuner_filter.dart';

/// 调音器读数滤波:静音闸 + 阻尼(工单 19 验收:静音/说话不误报、
/// 读数有阻尼不狂跳)。纯函数缝,时序用显式 at 驱动。
void main() {
  test('概率低于阈值不报(静音/环境噪声)', () {
    final filter = TunerFilter();
    final reading = filter.push(
      freq: 440.0,
      probability: TunerFilter.minProbability - 0.01,
      at: Duration.zero,
    );
    expect(reading, isNull, reason: '低置信度=没在响琴,不得出读数');
  });

  test('YIN 判非音高(pitched=false)不报', () {
    final filter = TunerFilter();
    expect(
      filter.push(freq: null, probability: 0, at: Duration.zero),
      isNull,
    );
  });

  test('频窗外不采:话音基频与高频哨音', () {
    final filter = TunerFilter();
    expect(
      filter.push(
        freq: 150.0,
        probability: 0.99,
        at: Duration.zero,
      ),
      isNull,
      reason: '220Hz 以下(男声基频区)不采',
    );
    expect(
      filter.push(
        freq: 1200.0,
        probability: 0.99,
        at: const Duration(milliseconds: 60),
      ),
      isNull,
      reason: '880Hz 以上不采',
    );
  });

  test('阻尼:抖动输入下读数向内收,不动如输入', () {
    final filter = TunerFilter();
    // 绕 A4=440 交替 ±3Hz(约 ±12 音分)的抖动。
    final up = filter.push(
      freq: 443.0,
      probability: 0.95,
      at: Duration.zero,
    )!;
    expect(up.freq, closeTo(443.0, 0.01), reason: '首帧即样本值(无历史)');
    final down = filter.push(
      freq: 437.0,
      probability: 0.95,
      at: const Duration(milliseconds: 60),
    )!;
    expect(
      down.freq,
      inInclusiveRange(437.0, 443.0),
      reason: '平滑值必在两样本之间',
    );
    expect(down.freq, lessThan(up.freq), reason: '读数朝输入方向移动但不跃变');
  });

  test('阻尼收敛:稳定拨弦段数帧后读数贴住真实频率', () {
    final filter = TunerFilter();
    filter.push(freq: 443.0, probability: 0.95, at: Duration.zero);
    TunerReading reading = filter.push(
      freq: 441.0,
      probability: 0.95,
      at: const Duration(milliseconds: 60),
    )!;
    for (var i = 2; i < 8; i++) {
      reading = filter.push(
        freq: 441.0,
        probability: 0.95,
        at: Duration(milliseconds: 60 * i),
      )!;
    }
    expect(reading.freq, closeTo(441.0, 0.5), reason: '稳定段 ~0.4s 收敛到 ±0.5Hz');
  });

  test('失效重置:长静默后的新拨弦不被旧读数拖拽', () {
    final filter = TunerFilter();
    filter.push(freq: 262.0, probability: 0.95, at: Duration.zero); // C4 附近
    // 600ms 无有效帧(> holdDuration),换拨 A4。
    final reading = filter.push(
      freq: 440.0,
      probability: 0.95,
      at: const Duration(milliseconds: 600),
    )!;
    expect(
      reading.freq,
      closeTo(440.0, 0.01),
      reason: '历史已过期,新样本即读数,不从 262 滑向 440',
    );
  });

  test('hold 窗内的短暂丢帧不打断平滑', () {
    final filter = TunerFilter();
    filter.push(freq: 440.0, probability: 0.95, at: Duration.zero);
    // 丢一帧(仅推进时间,无有效样本),随后 200ms 处样本继续平滑。
    final reading = filter.push(
      freq: 444.0,
      probability: 0.95,
      at: const Duration(milliseconds: 200),
    )!;
    expect(
      reading.freq,
      inInclusiveRange(440.0, 444.0),
      reason: '仍在 hold 窗内,读数是平滑值而非样本值',
    );
    expect(reading.freq, lessThan(444.0));
  });

  test('reset 后从新样本起算', () {
    final filter = TunerFilter();
    filter.push(freq: 440.0, probability: 0.95, at: Duration.zero);
    filter.reset();
    final reading = filter.push(
      freq: 392.0,
      probability: 0.95,
      at: const Duration(milliseconds: 60),
    )!;
    expect(reading.freq, closeTo(392.0, 0.01));
    expect(reading.noteName, 'G4');
  });
}
