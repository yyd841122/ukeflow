import 'dart:convert';
import 'dart:typed_data';

/// PCM16 mono 样本打包为规范 WAV 字节(RIFF/WAVE,44 字节头)。
/// TickSynth 与 KarplusStrong 共用;头布局由各自单测按规范逐字段锁定。
Uint8List wrapPcm16MonoWav({
  required int sampleRate,
  required Uint8List pcm16,
}) {
  final out = BytesBuilder();
  void u32le(int v) {
    final b = ByteData(4)..setInt32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  void u16le(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  out.add(ascii.encode('RIFF'));
  u32le(36 + pcm16.length);
  out.add(ascii.encode('WAVE'));
  out.add(ascii.encode('fmt '));
  u32le(16);
  u16le(1); // PCM
  u16le(1); // mono
  u32le(sampleRate);
  u32le(sampleRate * 2); // byteRate
  u16le(2); // blockAlign
  u16le(16); // bits
  out.add(ascii.encode('data'));
  u32le(pcm16.length);
  out.add(pcm16);
  return out.takeBytes();
}
