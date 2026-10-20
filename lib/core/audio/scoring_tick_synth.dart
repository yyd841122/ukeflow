import 'dart:math' as math;
import 'dart:typed_data';

import 'wav_pcm16.dart';

/// 评分专用节拍嘀声(工单 33 承重墙):880Hz 正弦 30ms、6ms 指数衰减、
/// 4ms 升余弦淡入,重音 1320Hz(880×1.5)。
///
/// =为什么不是现有 TickSynth=
/// 跟练评分时 app 自己在打节拍声,麦会把它收进去。现有强/弱/预备 tick
/// (1000/600/1400Hz、硬起音)不在麦端滤波链的陷波缝上,且硬起攻击的
/// 宽带溅射陷波再深也压不掉——每拍都会被当成用户扫弦,分数虚高
/// (ukulele-demo 最大坑)。评分嘀声专为可滤而设计:
/// - 基频落在 880/1320(麦端双陷波的缝上,OnsetDetector 同参数);
/// - 4ms 升余弦淡入把起攻击软化成「近乎窄带」,陷波器才能干净剔掉;
/// - 软嘀对人耳仍是清晰的一拍(.demo 真机验证)。
/// 承重墙回归(嘀声过链压 ≥40dB 且不误伤宽带扫弦)锁在
/// test/core/scoring/onset_detector_test.dart。
abstract final class ScoringTickSynth {
  /// 普通拍:880Hz。
  static Uint8List beep({int sampleRate = 44100}) =>
      _synth(880, sampleRate: sampleRate);

  /// 重音(每小节第 1 拍与预备拍):1320Hz。
  static Uint8List accent({int sampleRate = 44100}) =>
      _synth(1320, sampleRate: sampleRate);

  static Uint8List _synth(double hz, {required int sampleRate}) {
    const durSec = 0.030;
    final total = (durSec * sampleRate).round();
    final fadeOutLen = (0.003 * sampleRate).round();
    final fadeInLen = (0.004 * sampleRate).round();
    final pcm = Uint8List(total * 2);
    final view = ByteData.view(pcm.buffer);
    for (var i = 0; i < total; i++) {
      final t = i / sampleRate;
      final env = math.exp(-t / 0.006);
      // 淡入:0→1 升余弦(hann 前半),只在头 fadeInLen 内生效。
      final fadeIn = i < fadeInLen
          ? 0.5 * (1 - math.cos(math.pi * i / fadeInLen))
          : 1.0;
      var v = math.sin(2 * math.pi * hz * t) * env * fadeIn * 0.85;
      // 末尾 3ms 线性淡出防咔。
      final tailFrom = total - fadeOutLen;
      if (i >= tailFrom) {
        v *= (total - i) / fadeOutLen;
      }
      view.setInt16(
        i * 2,
        (v * 32767).round().clamp(-32768, 32767),
        Endian.little,
      );
    }
    return wrapPcm16MonoWav(sampleRate: sampleRate, pcm16: pcm);
  }
}
