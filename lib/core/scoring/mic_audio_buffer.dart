/// 会话音频缓冲(GLOSSARY「跟练评分」):评分会话期间麦 chunk 到达即存,
/// 供报告的点格重听与「错」判定的 Chroma 取窗。仅内存、看完即弃——
/// 退页即丢,不落库(GLOSSARY:报告不落库,音频同理)。
///
/// 存储为 Int16(PCM16 原生量化):Float64 全量留存 4 分钟 ≈ 85MB 不可
/// 接受,Int16 减半到 ~21MB,且与重听的 WAV 打包零转换。时间轴是引擎钟
/// 秒(chunk 到达即打戳,ADR-0005;链路常量差由延迟校准吸收,不在这里管)。
library;

import 'dart:typed_data';

import '../audio/wav_pcm16.dart';

const int micSampleRate = 44100;

/// 一段麦样本:量化后的样本 + 其末样本的引擎秒时刻。
final class _Chunk {
  _Chunk(this.samples, this.endSec);

  final Int16List samples;
  final double endSec;

  double startAt(int sampleRate) => endSec - samples.length / sampleRate;
}

class MicAudioBuffer {
  final _chunks = <_Chunk>[];

  final int sampleRate;

  MicAudioBuffer({this.sampleRate = micSampleRate});

  static const double _scale = 32767.0;

  /// 追加一段 Float64 样本(-1..1),[endSec] = 该段末样本的引擎秒。
  /// 到达即量化存储(Float64 → Int16),调用方缓冲后续可复用。
  void append(Float64List chunk, double endSec) {
    if (chunk.isEmpty) return;
    final samples = Int16List(chunk.length);
    for (var i = 0; i < chunk.length; i++) {
      samples[i] = (chunk[i] * _scale).round().clamp(-32768, 32767);
    }
    _chunks.add(_Chunk(samples, endSec));
  }

  /// 首样本引擎秒;空缓冲 null。
  double? get startSec =>
      _chunks.isEmpty ? null : _chunks.first.startAt(sampleRate);

  /// 末样本引擎秒;空缓冲 null。
  double? get endSec => _chunks.isEmpty ? null : _chunks.last.endSec;

  /// 取 [startSec, endSec) 的样本(引擎秒定位,跨 chunk 拼接),越界钳制;
  /// 空缓冲/无重叠返回空。值经 Int16 量化往返(±1/32767)。
  Float64List window(double startSec, double endSec) {
    final out = <int>[];
    _forEachSampleInRange(startSec, endSec, out.add);
    final samples = Float64List(out.length);
    for (var i = 0; i < out.length; i++) {
      samples[i] = out[i] / _scale;
    }
    return samples;
  }

  /// 取 [startSec, endSec) 打包为 WAV(PCM16 mono)字节——重听 loadMem
  /// 直接可用。窗外(无实有样本)返回 null。
  Uint8List? wavSnippet({required double startSec, required double endSec}) {
    final samples = <int>[];
    _forEachSampleInRange(startSec, endSec, samples.add);
    if (samples.isEmpty) return null;
    final pcm = Uint8List(samples.length * 2);
    final bd = ByteData.view(pcm.buffer);
    for (var i = 0; i < samples.length; i++) {
      bd.setInt16(i * 2, samples[i], Endian.little);
    }
    return wrapPcm16MonoWav(sampleRate: sampleRate, pcm16: pcm);
  }

  /// 遍历 [startSec, endSec) 内的样本(PCM16 量化值),跨 chunk 按序。
  /// 半开区间语义:样本 i 占用 [chunkStart+i/rate, 下一拍) —— 起点落在
  /// 窗尾的样本不算;窗端点覆盖整段 chunk 时全取。取整差 1e-6(样本域,
  /// ≈23ps)吸收浮点尘埃,恰在边界的端点按半开处理。
  void _forEachSampleInRange(
    double startSec,
    double endSec,
    void Function(int sample) sink,
  ) {
    if (endSec <= startSec) return;
    const eps = 1e-6;
    for (final chunk in _chunks) {
      final chunkStart = chunk.startAt(sampleRate);
      final lo = startSec > chunkStart ? startSec : chunkStart;
      final hi = endSec < chunk.endSec ? endSec : chunk.endSec;
      if (hi <= lo) continue;
      var from = lo <= chunkStart
          ? 0
          : ((lo - chunkStart) * sampleRate - eps).ceil();
      var to = hi >= chunk.endSec
          ? chunk.samples.length
          : ((hi - chunkStart) * sampleRate - eps).ceil();
      if (from < 0) from = 0;
      if (to > chunk.samples.length) to = chunk.samples.length;
      if (to <= from) continue;
      for (var i = from; i < to; i++) {
        sink(chunk.samples[i]);
      }
    }
  }
}
