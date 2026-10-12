import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// 代码合成节拍音:内存生成 WAV(PCM16 mono),不经任何资源文件。
/// 纯函数——同参数输出逐字节一致,测试无需引擎(ADR-0004:音源与引擎解耦)。
///
/// 波形 = 正弦 × 指数衰减包络 exp(-t·35),参数为 spike B 真机验证的听感:
/// 90ms 长度、强拍 1kHz。强弱拍靠音高与增益双重区分,4/4 一耳朵分明。
abstract final class TickSynth {
  static const _ms = 90;
  static const _decay = 35.0;

  /// 4/4 强拍(每小节第 1 拍):1kHz、增益 0.85。
  static Uint8List strong({int sampleRate = 44100}) =>
      build(sampleRate: sampleRate, ms: _ms, freq: 1000, gain: 0.85);

  /// 4/4 弱拍:600Hz、增益 0.55。
  static Uint8List weak({int sampleRate = 44100}) =>
      build(sampleRate: sampleRate, ms: _ms, freq: 600, gain: 0.55);

  /// 合成一段节拍 WAV:正弦 [freq]Hz、增益 [gain]、时长 [ms] 毫秒、
  /// 指数衰减包络([_decay],数值越大尾音越短)。
  static Uint8List build({
    required int sampleRate,
    required int ms,
    required double freq,
    required double gain,
  }) {
    final sampleCount = sampleRate * ms ~/ 1000;
    final pcm = Uint8List(sampleCount * 2);
    final view = ByteData.view(pcm.buffer);
    for (var i = 0; i < sampleCount; i++) {
      final t = i / sampleRate;
      final envelope = math.exp(-t * _decay);
      final v = (math.sin(2 * math.pi * freq * t) * envelope * gain * 32767)
          .round();
      view.setInt16(i * 2, v.clamp(-32768, 32767), Endian.little);
    }
    return _wrapWav(sampleRate: sampleRate, pcm16: pcm);
  }

  /// 给 PCM16 mono 数据包上规范 WAV 头。
  static Uint8List _wrapWav({required int sampleRate, required Uint8List pcm16}) {
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
}
