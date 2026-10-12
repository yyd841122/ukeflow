import 'dart:typed_data';

/// WAV(PCM16 mono,44 字节头)样本级读取:音频合成测试共用。
/// 头部结构断言各测试自持(WAV 规范手工真值),这里只提供样本访问。

/// 第 [index] 个样本的幅值(-32768..32767)。
int wavSampleAt(Uint8List wav, int index) =>
    ByteData.sublistView(wav).getInt16(44 + index * 2, Endian.little);

/// [fromSample]..[toSample) 内的最大绝对幅值。
int wavPeakOf(Uint8List wav, int fromSample, int toSample) {
  var peak = 0;
  for (var i = fromSample; i < toSample; i++) {
    peak = peak.abs() > wavSampleAt(wav, i).abs() ? peak : wavSampleAt(wav, i);
  }
  return peak;
}
