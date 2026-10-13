import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/model/tab_chart.dart';

/// 工单 12 接缝:指弹谱模型入库校验与逐音频率。
/// 频率期望值取十二平均律独立手算(A4=440,半音比 2^(1/12)),
/// 不由实现的公式复算而来。
void main() {
  TabChart chart(List<TabNote> notes, {int tempo = 80}) =>
      TabChart(title: '测试曲', tempo: tempo, notes: notes);

  group('validateTabChart:坏数据当场抛 TabDataError', () {
    test('弦号越界(0 与 5)', () {
      for (final string in [0, 5]) {
        expect(
          () => validateTabChart(
            chart([TabNote(string: string, fret: 0, beat: 0)]),
          ),
          throwsA(
            isA<TabDataError>().having(
              (e) => e.toString(),
              'message',
              contains('弦号越界'),
            ),
          ),
          reason: 'string=$string',
        );
      }
    });

    test('品位为负', () {
      expect(
        () => validateTabChart(chart([TabNote(string: 1, fret: -1, beat: 0)])),
        throwsA(isA<TabDataError>()),
      );
    });

    test('拍位为负/NaN/无穷', () {
      for (final beat in [-0.5, double.nan, double.infinity]) {
        expect(
          () => validateTabChart(
            chart([TabNote(string: 1, fret: 0, beat: beat)]),
          ),
          throwsA(isA<TabDataError>()),
          reason: 'beat=$beat',
        );
      }
    });

    test('tempo 非正、空谱', () {
      expect(
        () => validateTabChart(chart(const [], tempo: 0)),
        throwsA(isA<TabDataError>()),
      );
      expect(
        () => validateTabChart(chart(const [])),
        throwsA(isA<TabDataError>()),
      );
    });

    test('合法谱原样通过(返回同对象)', () {
      final ok = chart([
        TabNote(string: 4, fret: 0, beat: 0),
        TabNote(string: 1, fret: 3, beat: 0.5),
      ]);
      expect(identical(validateTabChart(ok), ok), isTrue);
    });
  });

  group('TabNote.frequency:空弦基频×2^(品位/12)', () {
    test('空弦即空弦基频', () {
      // 1 弦 A4=440、4 弦 G4≈391.995。
      expect(
        const TabNote(string: 1, fret: 0, beat: 0).frequency,
        closeTo(440.0, 1e-9),
      );
      expect(
        const TabNote(string: 4, fret: 0, beat: 0).frequency,
        closeTo(391.99543598174927, 1e-9),
      );
    });

    test('按品升半音:1 弦 3 品 = C5', () {
      // 440 × 2^(3/12) ≈ 523.251。
      expect(
        const TabNote(string: 1, fret: 3, beat: 0).frequency,
        closeTo(523.2511306011972, 1e-9),
      );
    });

    test('3 弦 2 品 = D4(入门曲旋律域抽查)', () {
      // 261.6255653 × 2^(2/12) ≈ 293.665。
      expect(
        const TabNote(string: 3, fret: 2, beat: 0).frequency,
        closeTo(293.6647679174076, 1e-9),
      );
    });
  });
}
