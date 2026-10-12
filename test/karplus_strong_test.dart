import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/karplus_strong.dart';
import 'helpers/wav_samples.dart';

/// KarplusStrong:代码合成拨弦 WAV(纯函数,测试不启动引擎——工单 04 验收)。
/// 期望值全部独立来源:WAV 规范手工真值、等律音分理论频率、声学量
/// (DFT 峰值测基频/分段 RMS 包络),不引用合成器自身的任何常量。
void main() {
  test('WAV 头为 PCM16 mono 规范结构,长度 = sampleRate × ms / 1000', () {
    final wav = KarplusStrong.pluck(freq: 440, ms: 1000);
    final dataBytes = ByteData.sublistView(wav).getUint32(40, Endian.little);
    expect(dataBytes, 44100 * 2, reason: '1000ms@44100 = 44100 样本 = 88200 字节');
    expect(wav.length, 44 + 88200);

    // 头部字段逐项核对(与 TickSynth 同一规范):
    String ascii4(int i) => String.fromCharCodes(wav.sublist(i, i + 4));
    int le16(int i) => ByteData.sublistView(wav).getUint16(i, Endian.little);
    int le32(int i) => ByteData.sublistView(wav).getUint32(i, Endian.little);
    expect(ascii4(0), 'RIFF');
    expect(le32(4), 36 + 88200);
    expect(ascii4(8), 'WAVE');
    expect(ascii4(12), 'fmt ');
    expect(le32(16), 16);
    expect(le16(20), 1, reason: 'PCM 格式码');
    expect(le16(22), 1, reason: 'mono');
    expect(le32(24), 44100);
    expect(le32(28), 44100 * 2);
    expect(le16(32), 2);
    expect(le16(34), 16);
    expect(ascii4(36), 'data');
  });

  test('发声非静音、不削波', () {
    final wav = KarplusStrong.pluck(freq: 440, ms: 1000);
    final total = wav.length - 44 >> 1;
    final peak = wavPeakOf(wav, 0, total).abs();
    expect(peak, greaterThan(32767 ~/ 4), reason: '应可听见');
    expect(peak, lessThanOrEqualTo(32767), reason: '不得削波');
  });

  test('同参数合成逐字节一致(纯函数,可缓存)', () {
    final a = KarplusStrong.pluck(freq: 440, ms: 1000);
    final b = KarplusStrong.pluck(freq: 440, ms: 1000);
    expect(a, orderedEquals(b));
  });

  test('gain 参数缩放响度', () {
    final total = (KarplusStrong.pluck(freq: 440, ms: 300).length - 44) ~/ 2;
    final loud = wavPeakOf(
      KarplusStrong.pluck(freq: 440, ms: 300, gain: 0.8),
      0,
      total,
    );
    final soft = wavPeakOf(
      KarplusStrong.pluck(freq: 440, ms: 300, gain: 0.4),
      0,
      total,
    );
    expect(soft.abs(), lessThan(loud.abs() * 0.7));
  });

  group('四根空弦基频误差 <1%(DFT 独立实测峰值)', () {
    /// Hann 窗信号在 [freq]Hz 处的幅值平方(直接 DFT,任意频点)。
    double powerAt(Uint8List wav, int start, int len, double freq, int rate) {
      var re = 0.0, im = 0.0;
      for (var i = 0; i < len; i++) {
        // Hann:w = 0.5(1 - cos(2πi/(len-1))),常数因子不影响峰位。
        final w = 0.5 * (1 - math.cos(2 * math.pi * i / (len - 1)));
        final phase = 2 * math.pi * freq * (start + i) / rate;
        final x = wavSampleAt(wav, start + i) * w;
        re += x * math.cos(phase);
        im -= x * math.sin(phase);
      }
      return re * re + im * im;
    }

    /// 稳态段(跳过激励突发)内的频谱峰位:扫频 ±8% + 对数功率二次插值。
    double measuredPeakHz(Uint8List wav, double expectHz, int rate) {
      const start = 8192, len = 4096;
      final lo = expectHz * 0.92, hi = expectHz * 1.08;
      const steps = 220;
      final grid = List.generate(steps + 1, (i) => lo + (hi - lo) * i / steps);
      final p = grid
          .map((f) => math.log(powerAt(wav, start, len, f, rate)))
          .toList();
      var best = 0;
      for (var i = 1; i < p.length; i++) {
        if (p[i] > p[best]) best = i;
      }
      // 峰值不在网格边缘时,抛物线顶点细化:
      if (best > 0 && best < p.length - 1) {
        final (yl, y0, yr) = (p[best - 1], p[best], p[best + 1]);
        final denom = yl - 2 * y0 + yr;
        final shift = denom == 0 ? 0.0 : 0.5 * (yl - yr) / denom;
        final stepHz = (hi - lo) / steps;
        return grid[best] + shift * stepHz;
      }
      return grid[best];
    }

    /// 等律音分理论值(A4=440),独立真值,不引自合成器。
    const cases = [
      (name: '1 弦 A4', freq: 440.0),
      (name: '2 弦 E4', freq: 329.62755691246664),
      (name: '3 弦 C4', freq: 261.6255653005986),
      (name: '4 弦 G4', freq: 391.99543598174927),
    ];

    for (final (:name, :freq) in cases) {
      test('$name 实测基频偏差 <1%($freq Hz)', () {
        final wav = KarplusStrong.pluck(freq: freq, ms: 1500);
        final measured = measuredPeakHz(wav, freq, 44100);
        final errPercent = (measured - freq).abs() / freq * 100;
        expect(errPercent, lessThan(1.0), reason: '实测 $measured Hz');
      });
    }

    /// 等分 [parts] 段的各段 RMS(0..32767 刻度)。
    List<double> segmentRms(Uint8List wav, int parts) {
      final total = (wav.length - 44) ~/ 2;
      return List.generate(parts, (k) {
        final from = total * k ~/ parts, to = total * (k + 1) ~/ parts;
        var sum = 0.0;
        for (var i = from; i < to; i++) {
          sum += wavSampleAt(wav, i) * wavSampleAt(wav, i);
        }
        return math.sqrt(sum / (to - from));
      });
    }

    test('自然衰减:分段 RMS 逐段下降,尾段比头段低 >30dB', () {
      final rms = segmentRms(KarplusStrong.pluck(freq: 261.63, ms: 1500), 8);
      for (var k = 0; k < 7; k++) {
        expect(rms[k + 1], lessThan(rms[k]), reason: '段 $k 应比段 ${k + 1} 响');
      }
      expect(rms.last, lessThan(rms.first * 0.0316), reason: '−30dB 以上');
    });

    test('时长参数化:ms 翻倍衰减放慢(同一段位置明显更响)', () {
      double rmsIn(int fromMs, int toMs, Uint8List wav) {
        final rate = ByteData.sublistView(wav).getUint32(24, Endian.little);
        final from = rate * fromMs ~/ 1000, to = rate * toMs ~/ 1000;
        var sum = 0.0;
        for (var i = from; i < to; i++) {
          sum += wavSampleAt(wav, i) * wavSampleAt(wav, i);
        }
        return math.sqrt(sum / (to - from));
      }

      final short = KarplusStrong.pluck(freq: 261.63, ms: 800);
      final long = KarplusStrong.pluck(freq: 261.63, ms: 1600);
      // t60 语义:700ms 处短音已近衰减完,长音才过半程,应差 20dB 上下。
      expect(rmsIn(600, 700, long), greaterThan(rmsIn(600, 700, short) * 4));
    });

    test('尾部无爆音:最后 2ms 峰值 < 全局峰 10%', () {
      final wav = KarplusStrong.pluck(freq: 261.63, ms: 1500);
      final total = (wav.length - 44) ~/ 2;
      expect(
        wavPeakOf(wav, total - 88, total).abs(),
        lessThan(wavPeakOf(wav, 0, total).abs() * 0.1),
      );
    });
  });
}
