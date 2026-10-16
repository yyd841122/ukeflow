import 'dart:typed_data';

/// WAV(PCM16 mono,44 字节头)样本级读取:音频合成测试共用。
/// 头部结构断言各测试自持(WAV 规范手工真值),这里只提供样本访问。

/// 第 [index] 个样本的幅值(-32768..32767)。
int wavSampleAt(Uint8List wav, int index) =>
    ByteData.sublistView(wav).getInt16(44 + index * 2, Endian.little);

/// [fromSample]..[toSample) 内的最大绝对幅值(恒非负;审计 2026-10-16
/// #51——旧实现保存的是带符号样本,[-100,50] 会返回 -100,调用方被迫
/// 自行 abs 补偿)。
int wavPeakOf(Uint8List wav, int fromSample, int toSample) {
  var peak = 0;
  for (var i = fromSample; i < toSample; i++) {
    final value = wavSampleAt(wav, i).abs();
    if (value > peak) peak = value;
  }
  return peak;
}
