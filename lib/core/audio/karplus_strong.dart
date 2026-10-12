import 'dart:math' as math;
import 'dart:typed_data';

import 'wav_pcm16.dart';

/// Karplus-Strong 拨弦合成(ADR-0004:合成兜底音源,音源与引擎解耦)。
/// 纯函数——同参数输出逐字节一致,测试与引擎完全无关。
///
/// 算法:长度 N = fs/freq 的延迟线装一段白噪声(拨弦激励),循环输出
/// 并以「相邻平均 × 损耗因子」回填——延迟线定音高,平均滤波给自然衰减。
///
/// 时长语义:整个 [ms] 即目标衰减时间(t60,幅度降 60dB),损耗因子
/// 由此反解——不同持续参数得到成比例的衰减速度;末段再线性淡出,
/// 兜住短时长下损耗被钳制时的截断爆音。
abstract final class KarplusStrong {
  /// 合成一段拨弦 WAV:目标基频 [freq]Hz、时长 [ms] 毫秒。
  static Uint8List pluck({
    required double freq,
    required int ms,
    int sampleRate = 44100,
    double gain = 0.8,
  }) {
    final sampleCount = sampleRate * ms ~/ 1000;
    final n = (sampleRate / freq).round();

    // 激励:固定种子伪随机噪声,保证纯函数确定性。
    final noise = math.Random(0x5eed);
    final buffer = Float64List(n);
    for (var i = 0; i < n; i++) {
      buffer[i] = (noise.nextDouble() * 2 - 1) * gain;
    }

    // 损耗因子:每圈(一个周期)幅度 × ρ·cos(π/N),令 ms 毫秒后恰降 60dB。
    // 极短时长下反解值会 ≥1(不衰减),钳到 1 以下保稳定,尾部靠淡出收口。
    final passes = sampleCount / n;
    final lossPerPass = math.pow(0.001, 1 / passes).toDouble();
    final loss = math.min(0.999999, lossPerPass / math.cos(math.pi / n));

    // KS 循环:输出读出端,回填相邻平均 × 损耗。
    final pcm64 = Float64List(sampleCount);
    var idx = 0;
    for (var i = 0; i < sampleCount; i++) {
      final current = buffer[idx];
      final next = buffer[(idx + 1) % n];
      pcm64[i] = current;
      buffer[idx] = loss * 0.5 * (current + next);
      idx = (idx + 1) % n;
    }

    // 末段 4ms 线性淡出(不足 4ms 取一半),截断处不炸一下。
    final fade = math.min(sampleRate * 4 ~/ 1000, sampleCount ~/ 2);
    for (var i = 0; i < fade; i++) {
      pcm64[sampleCount - 1 - i] *= i / fade;
    }

    return wrapPcm16MonoWav(sampleRate: sampleRate, pcm16: _toPcm16(pcm64));
  }

  static Uint8List _toPcm16(Float64List samples) {
    final pcm = Uint8List(samples.length * 2);
    final view = ByteData.view(pcm.buffer);
    for (var i = 0; i < samples.length; i++) {
      view.setInt16(
        i * 2,
        (samples[i] * 32767).round().clamp(-32768, 32767),
        Endian.little,
      );
    }
    return pcm;
  }
}
