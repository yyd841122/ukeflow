import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/wav_pcm16.dart';
import 'helpers/wav_samples.dart';

/// wavPeakOf 语义(审计 2026-10-16 #51):返回**最大绝对幅值**——旧实现
/// 保存带符号样本,负峰([-100,50]→-100)迫使调用方自行 abs 补偿。
void main() {
  Uint8List wavOf(List<int> samples) => wrapPcm16MonoWav(
        sampleRate: 44100,
        pcm16: Uint8List(samples.length * 2),
      );

  test('负峰返回正的绝对幅值:[-100, 50] → 100', () {
    // 手工写样本:wrapPcm16MonoWav 只负责头,数据用 ByteData 直填。
    final wav = wavOf(const [-100, 50]);
    final view = ByteData.sublistView(wav);
    view.setInt16(44, -100, Endian.little);
    view.setInt16(46, 50, Endian.little);

    expect(wavSampleAt(wav, 0), -100, reason: 'wavSampleAt 保持带符号读出');
    expect(wavPeakOf(wav, 0, 2), 100, reason: '负峰取绝对值');
    expect(wavPeakOf(wav, 1, 2), 50, reason: '区间收窄只看窗内');
  });
}
