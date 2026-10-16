import 'dart:math' as math;
import 'dart:typed_data';

import 'wav_pcm16.dart';

/// Karplus-Strong 拨弦合成(ADR-0004:合成兜底音源,音源与引擎解耦)。
/// 纯函数——同参数输出逐字节一致,测试与引擎完全无关。
///
/// 算法:延迟线装一段白噪声(拨弦激励),循环输出并以「相邻平均 ×
/// 损耗因子」回填——延迟线定音高,平均滤波给自然衰减。平均滤波使整环
/// 延迟 = N − 0.5,实际音高偏 sharp(880Hz 处实测 ≈890.9Hz,+21 音分,
/// 审计 2026-10-16 #5);以一阶全相滤波器补足分数样本:环内实测标定
/// 延迟 = N − 0.5 + a/2(a 为全相系数对应的标称群延迟,经验律在
/// 261–1397Hz 全域误差 <0.02 样本),取 N = round(D)、a = 2(D−N)+1
/// (钳到 2 以下保稳定)即整环延迟恰为 D = fs/freq,跨音域音准。
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
    final d = sampleRate / freq;
    final n = math.max(1, d.round());
    final a = (2 * (d - n) + 1).clamp(0.0, 1.999);
    final c = (1.0 - a) / (1.0 + a);

    // 激励:固定种子伪随机噪声,保证纯函数确定性。
    final noise = math.Random(0x5eed);
    final buffer = Float64List(n);
    for (var i = 0; i < n; i++) {
      buffer[i] = (noise.nextDouble() * 2 - 1) * gain;
    }

    // 损耗因子:每圈(整环延迟 D,含滤波群延迟)幅度 × ρ·cos(π/D),
    // 令 ms 毫秒后恰降 60dB(cos 项补偿平均滤波在振荡频率处的衰减)。
    // 极短时长下反解值会 ≥1(不衰减),钳到 1 以下保稳定,尾部靠淡出收口。
    final passes = sampleCount / d;
    final lossPerPass = math.pow(0.001, 1 / passes).toDouble();
    final loss = math.min(0.999999, lossPerPass / math.cos(math.pi / d));

    // KS 循环:输出读出端经全相分数延迟,回填相邻平均 × 损耗。
    final pcm64 = Float64List(sampleCount);
    var idx = 0;
    var apX1 = 0.0;
    var apY1 = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final current = buffer[idx];
      // 一阶全相分数延迟:y[i] = c·x[i] + x[i−1] − c·y[i−1]。
      final delayed = c * current + apX1 - c * apY1;
      apX1 = current;
      apY1 = delayed;
      final next = buffer[(idx + 1) % n];
      pcm64[i] = delayed;
      buffer[idx] = loss * 0.5 * (delayed + next);
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
