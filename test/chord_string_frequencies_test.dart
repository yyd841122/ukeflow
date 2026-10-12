import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/chord.dart';
import 'package:ukeflow/core/model/uke_string.dart';

/// 工单 05 seam 1:指法 → 各弦发声基频(和弦示范音的音高真源)。
/// 期望值用等律理论字面量(closeTo 0.01Hz),与实现无共谋;
/// 两路音高来源(源数据 midi / 品位换算)已在工单 02 对全量资产验证一致。
ChordFingering f(List<int> frets, {List<int>? midi, int baseFret = 1}) =>
    ChordFingering(
      frets: frets,
      fingers: const [0, 0, 0, 0],
      baseFret: baseFret,
      barres: const [],
      midi: midi,
    );

void main() {
  group('stringFrequencies', () {
    test('midi 优先:各弦按源数据音高(C 和弦 0003 → G4 C4 E4 C5)', () {
      final freqs = f([0, 0, 0, 3], midi: [67, 60, 64, 72]).stringFrequencies;
      expect(freqs[0], closeTo(391.9954, 0.01)); // G4
      expect(freqs[1], closeTo(261.6256, 0.01)); // C4
      expect(freqs[2], closeTo(329.6276, 0.01)); // E4
      expect(freqs[3], closeTo(523.2511, 0.01)); // C5
    });

    test('空弦 = 空弦标准音(与 UkeString 基频一致)', () {
      final freqs = f([2, 0, 0, 0], midi: [69, 60, 64, 69]).stringFrequencies;
      expect(freqs[1], closeTo(UkeString.c.frequency, 0.001));
      expect(freqs[2], closeTo(UkeString.e.frequency, 0.001));
      expect(freqs[3], closeTo(UkeString.a.frequency, 0.001));
    });

    test('闷音弦为 null,其余照常(闷音判定优先于 midi 值)', () {
      final freqs = f([-1, 0, 2, 0], midi: [0, 60, 66, 69]).stringFrequencies;
      expect(freqs[0], isNull, reason: '闷音不发声,即使 midi 有值');
      expect(freqs[1], closeTo(261.6256, 0.01)); // C4 空弦
      expect(freqs[2], closeTo(369.9944, 0.01)); // F#4
      expect(freqs[3], closeTo(440.0, 0.01)); // A4 空弦
    });

    test('midi 缺失时按品位换算(Am 2000 → A4 C4 E4 A4)', () {
      final freqs = f([2, 0, 0, 0]).stringFrequencies;
      expect(freqs[0], closeTo(440.0, 0.01));
      expect(freqs[1], closeTo(261.6256, 0.01));
      expect(freqs[2], closeTo(329.6276, 0.01));
      expect(freqs[3], closeTo(440.0, 0.01));
    });

    test('midi 缺失且 baseFret>1:换算含窗口偏移(绝对品位 = 值 + baseFret - 1)', () {
      // G 大调高把位按法(源数据 midi [74,67,71,79]):绝对 7,7,7,10 品。
      final freqs = f([1, 1, 1, 4], baseFret: 7).stringFrequencies;
      expect(freqs[0], closeTo(587.3295, 0.01)); // D5
      expect(freqs[1], closeTo(391.9954, 0.01)); // G4
      expect(freqs[2], closeTo(493.8833, 0.01)); // B4
      expect(freqs[3], closeTo(783.9909, 0.01)); // G5
    });

    test('两路换算一致:同指法 midi 路与品位路结果相同', () {
      final viaMidi = f(
        [1, 1, 1, 4],
        baseFret: 7,
        midi: [74, 67, 71, 79],
      ).stringFrequencies;
      final viaFrets = f([1, 1, 1, 4], baseFret: 7).stringFrequencies;
      for (var i = 0; i < 4; i++) {
        expect(viaFrets[i]!, closeTo(viaMidi[i]!, 0.01), reason: '第 $i 弦');
      }
    });

    test('空弦不参与窗口偏移:高把位含空弦指法(A13b5b9 真实形状)两路一致', () {
      // 源数据 A13b5b9:frets [0,2,3,1] baseFret 9,midi [67,70,75,78]——
      // 0 号弦 midi 是空弦原音 G4,评审曾抓到兜底路把它抬高 8 品。
      final viaMidi = f(
        [0, 2, 3, 1],
        baseFret: 9,
        midi: [67, 70, 75, 78],
      ).stringFrequencies;
      final viaFrets = f([0, 2, 3, 1], baseFret: 9).stringFrequencies;
      expect(viaFrets[0], closeTo(391.9954, 0.01), reason: '空弦 = G4 原音');
      for (var i = 0; i < 4; i++) {
        expect(viaFrets[i]!, closeTo(viaMidi[i]!, 0.01), reason: '第 $i 弦');
      }
    });
  });
}
