import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/tick_synth.dart';
import 'helpers/wav_samples.dart';

/// TickSynth:代码合成节拍 WAV(无资源文件)。
/// 期望值全部独立来源:WAV 规范手工真值、声学量(过零率/包络/量程界)。
void main() {
  int le16(Uint8List b, int i) => b[i] | (b[i + 1] << 8);
  int le32(Uint8List b, int i) =>
      b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);
  String ascii4(Uint8List b, int i) =>
      String.fromCharCodes(b.sublist(i, i + 4));

  /// 前 [ms] 毫秒内的正向过零次数(频率的独立证据)。
  int positiveZeroCrossings(Uint8List wav, int sampleRate, int ms) {
    final n = sampleRate * ms ~/ 1000;
    var count = 0;
    for (var i = 1; i < n; i++) {
      if (wavSampleAt(wav, i - 1) <= 0 && wavSampleAt(wav, i) > 0) count++;
    }
    return count;
  }

  const rate = 44100;
  final strong = TickSynth.strong(sampleRate: rate);
  final weak = TickSynth.weak(sampleRate: rate);

  test('WAV 头为 PCM16 mono 规范结构,RIFF/data 尺寸与样本数一致', () {
    // 90ms @44100 = 3969 样本 = 7938 字节;RIFF 尺寸 = 36 + data。
    expect(ascii4(strong, 0), 'RIFF');
    expect(le32(strong, 4), 36 + 7938);
    expect(ascii4(strong, 8), 'WAVE');
    expect(ascii4(strong, 12), 'fmt ');
    expect(le32(strong, 16), 16, reason: 'fmt 块长');
    expect(le16(strong, 20), 1, reason: 'PCM 格式码');
    expect(le16(strong, 22), 1, reason: 'mono 通道数');
    expect(le32(strong, 24), rate);
    expect(le32(strong, 28), rate * 2, reason: 'byteRate');
    expect(le16(strong, 32), 2, reason: 'blockAlign');
    expect(le16(strong, 34), 16, reason: '位深');
    expect(ascii4(strong, 36), 'data');
    expect(le32(strong, 40), 7938);
    expect(strong.length, 44 + 7938);
  });

  test('样本数 = sampleRate × ms / 1000', () {
    for (final ms in [50, 90, 200]) {
      final wav = TickSynth.build(
        sampleRate: rate,
        ms: ms,
        freq: 1000,
        gain: 0.85,
      );
      final dataBytes = le32(wav, 40);
      expect(dataBytes, rate * ms ~/ 1000 * 2, reason: 'ms=$ms');
    }
  });

  test('发声非静音、不削波,首样本为 0', () {
    for (final wav in [strong, weak]) {
      final peak = wavPeakOf(wav, 0, le32(wav, 40) ~/ 2).abs();
      expect(peak, greaterThan(32767 ~/ 2), reason: '应可听见');
      expect(peak, lessThanOrEqualTo(32767), reason: '不得削波');
      expect(wavSampleAt(wav, 0), 0, reason: 'sin(0)=0,起始无跳变');
    }
  });

  test('指数包络:尾段峰值显著低于头段(自然衰减,无爆音尾巴)', () {
    final total = le32(strong, 40) ~/ 2;
    final headPeak = wavPeakOf(strong, 0, total ~/ 4).abs();
    final tailPeak = wavPeakOf(strong, total * 3 ~/ 4, total).abs();
    expect(tailPeak, lessThan(headPeak ~/ 4));
  });

  test('强弱拍频率分明:strong 过零率约为 weak 的 1000/600', () {
    final strongHz = positiveZeroCrossings(strong, rate, 30) * 1000 / 30;
    final weakHz = positiveZeroCrossings(weak, rate, 30) * 1000 / 30;
    expect(strongHz, inInclusiveRange(950, 1050), reason: '强拍 ≈1kHz');
    expect(weakHz, inInclusiveRange(560, 640), reason: '弱拍 ≈600Hz');
  });

  test('强弱拍响度分明:weak 峰值低于 strong', () {
    final total = le32(strong, 40) ~/ 2;
    expect(
      wavPeakOf(weak, 0, total).abs(),
      lessThan(wavPeakOf(strong, 0, total).abs()),
    );
  });

  test('同参数合成逐字节一致(纯函数,可缓存)', () {
    final a = TickSynth.strong();
    final b = TickSynth.strong();
    expect(a, orderedEquals(b));
  });
}
