import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/scoring_tick_synth.dart';
import 'package:ukeflow/core/scoring/onset_detector.dart';

import '../../helpers/scoring_fixtures.dart';

/// OnsetDetector + 评分嘀声的承重墙回归(工单 33):
/// 「嘀声压 ≥40dB 且不误伤宽带扫弦」——评分时 app 自打节拍嘀声,滤波链
/// 压不掉它则每拍误判扫弦、分数虚高(ukulele-demo 最大坑)。
void main() {
  const sr = 44100;

  /// 一段样本逐 100ms 喂检测器(arrivalSec = 每段末样本的秒时刻)。
  List<double> detectAll(Float64List signal) {
    final detector = OnsetDetector(sampleRate: sr);
    final onsets = <double>[];
    const hop = 4410; // 100ms
    for (var pos = 0; pos < signal.length; pos += hop) {
      final end = math.min(pos + hop, signal.length);
      onsets.addAll(
        detector.process(Float64List.sublistView(signal, pos, end), end / sr),
      );
    }
    return onsets;
  }

  /// 复合信号:信号里某个秒时刻叠加一段源样本。
  void mix(Float64List base, Float64List src, double atSec) {
    final start = (atSec * sr).round();
    for (var i = 0; i < src.length && start + i < base.length; i++) {
      base[start + i] += src[i];
    }
  }

  /// 嘀声节拍序列(评分时的扬声器输出):普通 880 / 重音 1320 交替,每 0.5s 一声。
  Float64List beepTrack({required int totalSamples, required int count}) {
    final out = Float64List(totalSamples);
    final normal = ScoringTickSynth.beep(sampleRate: sr);
    final accent = ScoringTickSynth.accent(sampleRate: sr);
    for (var k = 0; k < count; k++) {
      mix(out, k.isEven ? samplesOf(normal) : samplesOf(accent), 0.2 + k * 0.5);
    }
    return out;
  }

  group('Biquad 滤波链', () {
    test('稳态 880/1320 纯音过链:中心频率衰减 ≥40dB(承重墙·压嘀声)', () {
      // 口径对齐 demo 注释「对 880/1320Hz 衰减 ≥40dB」:稳态衰减率。
      // 短促嘀声的瞬态残留不可能 40dB 压掉(窄缝挖不走衰减包络的边带),
      // 那部分由持续性门兜住——见下方「只有嘀声轨」行为断言,两者合起来
      // 才是完整承重墙。测量窗取中段,避开起停边沿与滤波器建立段。
      double steadyDb(int freq) {
        const n = sr; // 1s
        const ramp = (0.05 * sr) ~/ 1; // 50ms 升余弦淡入淡出
        final input = Float64List(n);
        for (var i = 0; i < n; i++) {
          final t = i / sr;
          final fade = i < ramp
              ? 0.5 * (1 - math.cos(math.pi * i / ramp))
              : (i >= n - ramp
                    ? 0.5 * (1 - math.cos(math.pi * (n - i) / ramp))
                    : 1.0);
          input[i] = math.sin(2 * math.pi * freq * t) * 0.5 * fade;
        }
        final chain = Float64List.fromList(input);
        Biquad.highpass(150, sr).processInPlace(chain);
        Biquad.notch(880, sr).processInPlace(chain);
        Biquad.notch(1320, sr).processInPlace(chain);
        double energy(Float64List s, int from, int to) {
          var e = 0.0;
          for (var i = from; i < to; i++) {
            e += s[i] * s[i];
          }
          return e;
        }

        const mid = ramp * 2; // 中段稳态窗
        final inputE = energy(input, mid, n - mid);
        final chainE = energy(chain, mid, n - mid);
        return 10 * math.log(inputE / chainE) / math.ln10;
      }

      expect(steadyDb(880), greaterThanOrEqualTo(40), reason: '嘀声普通音基频');
      expect(steadyDb(1320), greaterThanOrEqualTo(40), reason: '嘀声重音基频');
    });

    test('宽带扫弦拟声过链:能量基本保留(陷波不误伤)', () {
      const n = sr ~/ 4;
      final random = math.Random(7);
      final input = Float64List(n);
      for (var i = 0; i < n; i++) {
        input[i] =
            (random.nextDouble() * 2 - 1) * 0.4 * math.exp(-i / sr / 0.05);
      }
      final chain = Float64List.fromList(input);
      Biquad.highpass(150, sr).processInPlace(chain);
      Biquad.notch(880, sr).processInPlace(chain);
      Biquad.notch(1320, sr).processInPlace(chain);
      double energy(Float64List s) {
        var e = 0.0;
        for (final v in s) {
          e += v * v;
        }
        return e;
      }

      final lossDb = 10 * math.log(energy(input) / energy(chain)) / math.ln10;
      expect(lossDb, lessThan(3), reason: '两个窄缝挖不走宽带瞬态(实测 <1dB)');
    });
  });

  group('OnsetDetector', () {
    test('单独一声扫弦:位置检对(±40ms),只报一次', () {
      final signal = strumBurst(totalSamples: sr * 2, atSec: 1.0);
      final onsets = detectAll(signal);
      expect(onsets, hasLength(1));
      expect(onsets.single, closeTo(1.0, 0.04));
    });

    test('只有嘀声轨(评分节拍):零误报(承重墙)', () {
      final signal = beepTrack(totalSamples: sr * 6, count: 11);
      expect(detectAll(signal), isEmpty, reason: '嘀声每 0.5s 一声,滤波压不掉就每拍虚报扫弦');
    });

    test('嘀声轨 + 扫弦混弹:只报扫弦,嘀声不抢报不吞报(承重墙)', () {
      final signal = beepTrack(totalSamples: sr * 6, count: 11);
      final strumTimes = [0.7, 1.7, 2.7, 3.7];
      for (var i = 0; i < strumTimes.length; i++) {
        mix(
          signal,
          strumBurst(totalSamples: sr, atSec: 0, seed: i + 2),
          strumTimes[i],
        );
      }
      final onsets = detectAll(signal);
      expect(
        onsets,
        hasLength(strumTimes.length),
        reason:
            '检出 ${onsets.length} 个:${onsets.map((t) => t.toStringAsFixed(3)).toList()}',
      );
      for (var i = 0; i < strumTimes.length; i++) {
        expect(onsets[i], closeTo(strumTimes[i], 0.04));
      }
    });

    test('不应期:60ms 间隔的双能量峰不拆成两报', () {
      // 两个 50ms 簇(各自撑得过持续性门),间隔 60ms < 不应期 120ms。
      final signal = Float64List(sr * 2);
      mix(signal, strumBurst(totalSamples: sr, atSec: 0, lengthSec: 0.05), 1.0);
      mix(
        signal,
        strumBurst(totalSamples: sr, atSec: 0, lengthSec: 0.05, seed: 9),
        1.06,
      );
      expect(detectAll(signal), hasLength(1));
    });

    test('持续性门:不撑过 2 帧的短促纯音尖峰不成报', () {
      // 500Hz(不在陷波缝上)10ms 短促嘀:能量塌得快,候选撑不住后续帧。
      final signal = Float64List(sr * 2);
      const start = sr; // 1.0s
      const blipLen = 0.010 * sr ~/ 1;
      for (var i = 0; i < blipLen; i++) {
        signal[start + i] = math.sin(2 * math.pi * 500 * i / sr) * 0.6;
      }
      expect(detectAll(signal), isEmpty);
    });

    test('reset:复用检测器不串上一会话的滤波尾与状态', () {
      final detector = OnsetDetector(sampleRate: sr);
      detector.process(strumBurst(totalSamples: sr, atSec: 0.2), 1.0);
      detector.reset();
      final onsets = <double>[];
      const hop = 4410;
      for (var pos = 0; pos < sr * 2; pos += hop) {
        final end = math.min(pos + hop, sr * 2);
        onsets.addAll(
          detector.process(
            Float64List.sublistView(
              strumBurst(totalSamples: sr * 2, atSec: 1.0),
              pos,
              end,
            ),
            end / sr,
          ),
        );
      }
      expect(onsets, hasLength(1));
      expect(onsets.single, closeTo(1.0, 0.04));
    });
  });
}

/// WAV 字节(44 字节头)→ Float64 样本。
Float64List samplesOf(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  final n = (wav.lengthInBytes - 44) ~/ 2;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = data.getInt16(44 + i * 2, Endian.little) / 32768;
  }
  return out;
}
