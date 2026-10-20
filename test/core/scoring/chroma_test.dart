import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/scoring/chroma.dart';

/// Chroma 封闭验证(工单 33「错」判定):信号色度 vs 目标和弦模板,
/// 二值判定(不识别弹成了什么)。票内 spike:阈值 0.6 为 glm 调用侧
/// 先例,真琴调参从这里起步。
void main() {
  const sr = 44100;

  /// 谱面常见和弦的尤克里里实际发声音高(midi,闷音弦不含)。
  const voicings = <String, List<int>>{
    'C': [60, 64, 67, 72], // C4 E4 G4 C5
    'G': [55, 62, 67, 71], // G3 D4 G4 B4
    'Am': [57, 60, 64, 69], // A3 C4 E4 A4
    'F': [53, 57, 60, 65], // F3 A3 C4 F4
  };

  /// 合成一段扫弦拟声:各弦基频正弦 × 各自错峰起振 × 指数衰减 + 微噪声。
  Float64List chordSignal(
    List<int> midiNotes, {
    double startSec = 0,
    double lengthSec = 0.3,
    double amp = 0.4,
    int seed = 3,
  }) {
    final total = (0.5 * sr).round();
    final out = Float64List(total);
    final random = math.Random(seed);
    final start = (startSec * sr).round();
    final len = (lengthSec * sr).round();
    for (var s = 0; s < midiNotes.length; s++) {
      final f = 440.0 * math.pow(2, (midiNotes[s] - 69) / 12);
      final offset = start + s * (0.005 * sr).round(); // 弦间错峰 5ms
      for (var i = 0; offset + i < total && i < len; i++) {
        final t = i / sr;
        out[offset + i] +=
            math.sin(2 * math.pi * f * t) *
            amp /
            midiNotes.length *
            math.exp(-t / 0.08);
      }
    }
    for (var i = 0; i < total; i++) {
      out[i] += (random.nextDouble() * 2 - 1) * 0.003; // 底噪
    }
    return out;
  }

  ChromaMatcher matcher() => ChromaMatcher(midiByChord: voicings);

  /// 从信号里取 [fromSec, toSec) 窗做色度。
  ChromaVector chromaOf(Float64List signal, double fromSec, double toSec) {
    final from = (fromSec * sr).round();
    final to = math.min((toSec * sr).round(), signal.length);
    return chromaFromSamples(
      Float64List.sublistView(signal, from, math.max(to, from + 1)),
      sampleRate: sr,
    );
  }

  test('纯音的色度峰落在正确音高类:440Hz → A 类', () {
    final n = 8192;
    final signal = Float64List(n);
    for (var i = 0; i < n; i++) {
      signal[i] = math.sin(2 * math.pi * 440 * i / sr);
    }
    final c = chromaFromSamples(signal, sampleRate: sr);
    var best = 0;
    for (var i = 1; i < 12; i++) {
      if (c.bins[i] > c.bins[best]) best = i;
    }
    expect(best, 9, reason: 'A = 音高类 9(C=0)');
  });

  test('C 大三和弦信号:最佳匹配 C,score 超阈值', () {
    final c = chromaOf(chordSignal(voicings['C']!), 0, 0.3);
    final best = matcher().bestMatch(c)!;
    expect(best.label, 'C');
    expect(best.score, greaterThan(chromaMatchThreshold));
  });

  test('G 和弦信号:最佳匹配 G;对 C 的封闭验证为否(「错」的来源)', () {
    final g = chromaOf(chordSignal(voicings['G']!), 0, 0.3);
    final best = matcher().bestMatch(g)!;
    expect(best.label, 'G');
    expect(best.score, greaterThan(chromaMatchThreshold));

    final okC = best.label == 'C' && best.score > chromaMatchThreshold;
    expect(okC, isFalse, reason: '弹了 G 判目标 C → 错');
  });

  test('四个和弦各自命中自己的目标(封闭集无串扰)', () {
    for (final entry in voicings.entries) {
      final c = chromaOf(chordSignal(entry.value), 0, 0.3);
      expect(
        matcher().bestMatch(c)!.label,
        entry.key,
        reason: '信号 ${entry.key}',
      );
    }
  });

  test('余音污染:前一和弦以 20% 幅度余音叠加,新扫弦仍判新和弦', () {
    // C 扫响后 300ms 内又扫了 G:C 的余音(20%)混进 G 的分析窗。
    final gWithCRing = Float64List.fromList(chordSignal(voicings['G']!));
    final ring = chordSignal(voicings['C']!, startSec: 0.0, lengthSec: 0.45);
    for (var i = 0; i < gWithCRing.length; i++) {
      gWithCRing[i] += ring[i] * 0.2;
    }
    final c = chromaOf(gWithCRing, 0, 0.3);
    expect(matcher().bestMatch(c)!.label, 'G');
  });

  test('同一和弦的相似度为 1,跨和弦更小', () {
    final cT = chordTemplate(voicings['C']!);
    final gT = chordTemplate(voicings['G']!);
    expect(cosineSimilarity(cT, cT), closeTo(1, 1e-9));
    expect(cosineSimilarity(cT, gT), lessThan(1));
  });

  test('静音窗:零向量,bestMatch 返回 null(不判对也不判错)', () {
    final c = chromaFromSamples(Float64List(8192), sampleRate: sr);
    expect(matcher().bestMatch(c), isNull);
  });

  test('短窗(不足一个 FFT 帧)零填充不炸', () {
    final signal = chordSignal(voicings['C']!);
    final c = chromaOf(signal, 0.1, 0.1 + 0.02); // 20ms << 4096 样本
    expect(matcher().bestMatch(c), isNotNull);
  });
}
