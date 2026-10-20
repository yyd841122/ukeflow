/// Chroma 封闭验证(GLOSSARY「跟练评分」的「错」判定):对时机窗内响了的
/// 扫弦,取该 onset 后的音频窗算 12 维色度向量,与会话谱面各和弦的模板
/// 比相似度——目标和弦是否为最佳匹配且分数过阈值。二值判定:不识别
/// 「弹成了什么」,不归因单弦。
///
/// 纯 Dart(dart:typed_data + dart:math),标准 flutter test 无头覆盖。
/// 参数出处:阈值 0.6 = ukulele-glm chord_recognizer 调用侧先例
/// (bestMatch==target 且 score>0.6);glm 仓库无和弦识别准确率记录,
/// **本模块是全票唯一无真机验证的环节**——真琴调参从 [chromaMatchThreshold]
/// 与 [_fftSize] 起步,票内 spike。
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 匹配阈值:目标为最佳匹配且余弦相似度超过它才算「对」。
const double chromaMatchThreshold = 0.6;

/// 色度分析下/上界(Hz):盖住尤克里里基频(G3≈196 起按品上行)与
/// 前 2-3 个谐波,截掉环境低鸣与高频嘶声。
const double _minFreq = 70;
const double _maxFreq = 2500;

/// FFT 帧长(样本):4096 @44.1kHz ≈ 93ms,频率分辨率 ~10.8Hz——
/// G3(196Hz)与 G#3 尚可分,低音区和弦内半音不再细分(色度本就按类归篮)。
const int _fftSize = 4096;

/// 12 维色度向量(L2 归一;下标 0 = C 类,1 = C# …与 midi %12 同序)。
class ChromaVector {
  const ChromaVector(this.bins);

  final Float64List bins;
}

/// 一次封闭验证查询的结果:[label] 最佳匹配和弦名,[score] 余弦相似度。
typedef ChromaBestMatch = ({String label, double score});

/// 和弦音高类 → 模板:每根发声弦的 midi 音高类计权 +1(四弦同类的
/// 按法该类权重 2),L2 归一。模板是「按法和弦」的音高类骨架,与演奏
/// 力度/音色无关。
ChromaVector chordTemplate(List<int> midiNotes) {
  final bins = Float64List(12);
  for (final note in midiNotes) {
    bins[note % 12] += 1;
  }
  return ChromaVector(_normalize(bins));
}

/// 余弦相似度(两向量都已 L2 归一时即点积)。
double cosineSimilarity(ChromaVector a, ChromaVector b) {
  var dot = 0.0;
  for (var i = 0; i < 12; i++) {
    dot += a.bins[i] * b.bins[i];
  }
  return dot;
}

/// 封闭集验证器:按会话谱面和弦集建模板,查询信号色度的最佳匹配。
class ChromaMatcher {
  /// [midiByChord]:和弦名 → 该和弦(主指法)的发声 midi 列表。
  ChromaMatcher({required Map<String, List<int>> midiByChord})
    : _labels = midiByChord.keys.toList(growable: false),
      _templates = [
        for (final notes in midiByChord.values) chordTemplate(notes),
      ];

  final List<String> _labels;
  final List<ChromaVector> _templates;

  /// 最佳匹配;全零色度(静音/无信号)返回 null。
  ChromaBestMatch? bestMatch(ChromaVector chroma) {
    var sum = 0.0;
    for (final v in chroma.bins) {
      sum += v;
    }
    if (sum <= 0) return null;
    var best = -1;
    var bestScore = -1.0;
    for (var i = 0; i < _templates.length; i++) {
      final score = cosineSimilarity(chroma, _templates[i]);
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return (label: _labels[best], score: bestScore);
  }
}

/// 音频窗 → 色度向量:分帧(Hann 窗,[_fftSize],帧不重叠,谱幅度平均)
/// → 频线按音高类归篮累加 → L2 归一。样本不足一帧尾部零填充。
ChromaVector chromaFromSamples(Float64List samples, {int sampleRate = 44100}) {
  final power = Float64List(_fftSize); // 平均谱幅度(跨帧累加)
  var frames = 0;
  final window = _hann(_fftSize);
  for (var start = 0; start < samples.length; start += _fftSize) {
    final frame = Float64List(_fftSize);
    final end = math.min(start + _fftSize, samples.length);
    for (var i = 0; i < end - start; i++) {
      frame[i] = samples[start + i] * window[i];
    }
    final spectrum = _magnitude(
      _fft([for (var i = 0; i < _fftSize; i++) (frame[i], 0.0)]),
    );
    for (var i = 0; i < spectrum.length; i++) {
      power[i] += spectrum[i];
    }
    frames++;
  }
  if (frames == 0) return ChromaVector(Float64List(12));

  final bins = Float64List(12);
  for (var k = 1; k < _fftSize ~/ 2; k++) {
    final freq = k * sampleRate / _fftSize;
    if (freq < _minFreq || freq > _maxFreq) continue;
    final noteNum = 69 + 12 * math.log(freq / 440) / math.ln2;
    final pc = ((noteNum.round() % 12) + 12) % 12;
    bins[pc] += power[k];
  }
  return ChromaVector(_normalize(bins));
}

Float64List _normalize(Float64List bins) {
  var norm = 0.0;
  for (final v in bins) {
    norm += v * v;
  }
  if (norm <= 0) return bins;
  final root = math.sqrt(norm);
  for (var i = 0; i < bins.length; i++) {
    bins[i] /= root;
  }
  return bins;
}

Float64List _hann(int n) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = 0.5 * (1 - math.cos(2 * math.pi * i / (n - 1)));
  }
  return out;
}

/// 迭代基-2 FFT(输入长度 2 的幂);返回复谱的幅度谱(0..N/2)。
Float64List _magnitude(List<(double, double)> spectrum) {
  final out = Float64List(spectrum.length ~/ 2 + 1);
  for (var k = 0; k < out.length; k++) {
    out[k] = math.sqrt(
      spectrum[k].$1 * spectrum[k].$1 + spectrum[k].$2 * spectrum[k].$2,
    );
  }
  return out;
}

/// Cooley-Tukey 基-2 时域抽取,迭代实现(位反转置换 + 蝶形)。
List<(double, double)> _fft(List<(double, double)> input) {
  final n = input.length;
  final re = Float64List(n);
  final im = Float64List(n);
  for (var i = 0; i < n; i++) {
    final j = _bitReverse(i, n);
    re[j] = input[i].$1;
    im[j] = input[i].$2;
  }
  for (var size = 2; size <= n; size <<= 1) {
    final step = size >> 1;
    final angle = -2 * math.pi / size;
    for (var start = 0; start < n; start += size) {
      for (var j = 0; j < step; j++) {
        final wr = math.cos(angle * j);
        final wi = math.sin(angle * j);
        final i0 = start + j;
        final i1 = i0 + step;
        final tr = re[i1] * wr - im[i1] * wi;
        final ti = re[i1] * wi + im[i1] * wr;
        re[i1] = re[i0] - tr;
        im[i1] = im[i0] - ti;
        re[i0] += tr;
        im[i0] += ti;
      }
    }
  }
  return [for (var i = 0; i < n; i++) (re[i], im[i])];
}

int _bitReverse(int i, int n) {
  var bits = 0;
  for (var shift = n >> 1; shift > 0; shift >>= 1) {
    bits = (bits << 1) | (i & 1);
    i >>= 1;
  }
  return bits;
}
