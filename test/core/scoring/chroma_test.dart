import 'dart:io';
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

  test('scoresFor:降序全模板分,首位与 bestMatch 同判(工单 54 审计缝)', () {
    final m = matcher();
    final c = chromaOf(chordSignal(voicings['C']!), 0, 0.3);
    final scores = m.scoresFor(c);
    expect(scores.first.label, 'C'); // C 信号对 C 模板最高
    for (var i = 1; i < scores.length; i++) {
      expect(scores[i].score, lessThanOrEqualTo(scores[i - 1].score));
    }
    final best = m.bestMatch(c)!;
    expect(scores.first.label, best.label);
    expect(scores.first.score, closeTo(best.score, 1e-12));
    // 逐项与余弦定义对账(模板已归一,分数即点积)。
    for (final entry in voicings.entries) {
      final expected = cosineSimilarity(c, chordTemplate(entry.value));
      expect(
        scores.firstWhere((s) => s.label == entry.key).score,
        closeTo(expected, 1e-12),
      );
    }
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

  test('真机黄金样张(工单54 回灌):真实 C 扫弦窗在封闭集里 C 大幅胜出', () {
    // 2026-11-01 真机会话(两只老虎 50%,OPPO PCAM00)slot 37 的色度窗
    // (onset+56.155s 起 320ms,滤前 PCM16):top 类 C:670 E:598 G:318,
    // 教科书级 C 大三。真实信号的全部物理(琴弦泛音/麦 HAL/房间/嘀声
    // 残余)都锁在这 28KB 里——色度参数漂移,这里红。
    final wav = File('test/fixtures/scoring/real_uke_c_window.wav').readAsBytesSync();
    final samples = _pcm16MonoFromWav(wav);
    expect(samples.length, 14112, reason: '320ms @44.1kHz');
    final c = chromaFromSamples(samples, sampleRate: sr);

    const closed = <String, List<int>>{
      'C': [67, 60, 64, 72],
      'G': [55, 62, 67, 71],
      'G7': [55, 62, 65, 71],
    };
    final m = ChromaMatcher(midiByChord: closed);
    final best = m.bestMatch(c)!;
    final scores = m.scoresFor(c);
    expect(best.label, 'C', reason: '真 C 窗必须命中 C');
    expect(best.score, greaterThan(0.85), reason: '封闭集下余弦分真机实测 0.9x');
    expect(
      best.score - scores[1].score,
      greaterThan(0.25),
      reason: '对 G/G7 的余量;分数若贴近,阈值/归一漂移先行报警',
    );
  });
}

/// 最小 RIFF 解析:取 data 块的 PCM16 mono 样本(测试专用,只认自产
/// wrapPcm16MonoWav 的规范形态)。
Float64List _pcm16MonoFromWav(Uint8List wav) {
  final bd = ByteData.sublistView(wav);
  expect(wav.lengthInBytes, greaterThanOrEqualTo(44));
  expect(wav[0], 0x52); // 'R'
  expect(wav[8], 0x57); // 'W'
  var pos = 12;
  var dataStart = -1, dataLen = 0;
  while (pos + 8 <= wav.lengthInBytes) {
    final id = String.fromCharCodes(wav.sublist(pos, pos + 4));
    final size = bd.getUint32(pos + 4, Endian.little);
    if (id == 'data') {
      dataStart = pos + 8;
      dataLen = size;
      break;
    }
    pos += 8 + size + (size.isOdd ? 1 : 0);
  }
  expect(dataStart, greaterThanOrEqualTo(44), reason: '无 data 块');
  final n = dataLen ~/ 2;
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = bd.getInt16(dataStart + i * 2, Endian.little) / 32767.0;
  }
  return out;
}
