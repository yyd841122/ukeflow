import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/tuner/pitch_math.dart';

/// 音名/音分换算(工单 19 验收:换算逻辑有单元测试)。
/// 期望值为独立来源:十二平均律公式手算 + UkeString 已知标准音。
void main() {
  test('A4 440Hz → A4,偏差 0 音分', () {
    final note = nearestNote(440.0);
    expect(note.midi, 69);
    expect(note.name, 'A4');
    expect(note.cents, closeTo(0, 0.01));
  });

  test('445Hz → A4,偏高约 +19.6 音分(手算:1200·log2(445/440))', () {
    final note = nearestNote(445.0);
    expect(note.name, 'A4');
    expect(note.cents, closeTo(19.57, 0.1));
  });

  test('GCEA 四根空弦标准音各归其名(UkeString 同源频率)', () {
    // G4/C4/E4/A4 标准值与 core/model UkeString 一致,音名不串、偏差≈0。
    expect(nearestNote(391.99543598174927).name, 'G4');
    expect(nearestNote(261.6255653005986).name, 'C4');
    expect(nearestNote(329.62755691246664).name, 'E4');
    expect(nearestNote(440.0).name, 'A4');
  });

  test('音名随八度进位:升号拼写、跨 C 与高八度', () {
    expect(nearestNote(277.1826).name, 'C#4'); // 升号拼法
    expect(nearestNote(880.0).name, 'A5'); // 高八度
    expect(nearestNote(130.8128).name, 'C3'); // 跨 C 向低
  });

  test('centsBetween:G4→A4 恰两半音 = +200 音分,反向为负', () {
    // G4 标准音恰是 A4 下行两半音(440·2^(-2/12)),期望值来自律制本身。
    expect(centsBetween(440.0, 391.99543598174927), closeTo(200, 0.01));
    expect(centsBetween(391.99543598174927, 440.0), closeTo(-200, 0.01));
  });
}
