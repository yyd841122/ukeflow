import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/scoring/strum_scorer.dart';

/// 扫弦评分纯函数(GLOSSARY「跟练评分」判定侧):拍域输入,秒域判定。
/// 判定语义:✓(时机准)/早/晚/漏(没听到)/错(响了但和弦不对)。
void main() {
  // 80BPM(拍周期 750ms)下的便捷构造:拍位即秒数(1 拍 = 0.75s),
  // 误差换算心算直读:0.06 拍 = 45ms。
  ScoredOnset onsetAtBeat(double beat) => ScoredOnset(beat, 750);

  group('时机判定', () {
    test('全准:四拍扫弦逐拍命中,准确率 1', () {
      final r = scoreStrums(
        targets: [
          ScoringTarget(4),
          ScoringTarget(4.5),
          ScoringTarget(5),
          ScoringTarget(5.5),
        ],
        onsets: [
          for (final b in const [4.0, 4.5, 5.0, 5.5]) onsetAtBeat(b),
        ],
      );
      expect(r.total, 4);
      expect(r.matched, 4);
      expect(r.missed, 0);
      expect(r.onTime, 4);
      expect(r.early, 0);
      expect(r.late, 0);
      expect(r.wrong, 0);
      expect(r.accuracy, 1.0);
      expect(
        r.verdicts.map((v) => v.judgment),
        everyElement(StrumJudgment.onTime),
      );
    });

    test('晚:超出准窗但容差内判晚;早对称', () {
      // 0.06 拍 = 45ms…要超出 50ms 准窗得 ≥0.0667 拍,取 0.1 拍 = 75ms。
      final late = scoreStrums(
        targets: [ScoringTarget(4)],
        onsets: [onsetAtBeat(4.1)],
      );
      expect(late.verdicts.single.judgment, StrumJudgment.late);
      expect(late.verdicts.single.errorSec, closeTo(0.075, 1e-9));

      final early = scoreStrums(
        targets: [ScoringTarget(4)],
        onsets: [onsetAtBeat(3.9)],
      );
      expect(early.verdicts.single.judgment, StrumJudgment.early);
      expect(early.verdicts.single.errorSec, closeTo(-0.075, 1e-9));
    });

    test('准窗边界:恰 ±50ms 算准(闭),±51ms 出窗', () {
      final at = scoreStrums(
        targets: [ScoringTarget(4)],
        onsets: [ScoredOnset(4 + 0.05 / 0.75, 750)],
      );
      expect(at.verdicts.single.judgment, StrumJudgment.onTime);

      final out = scoreStrums(
        targets: [ScoringTarget(4)],
        onsets: [ScoredOnset(4 + 0.051 / 0.75, 750)],
      );
      expect(out.verdicts.single.judgment, StrumJudgment.late);
    });

    test('漏:无 onset 判漏,准确率 0;误差对漏点无意义', () {
      final r = scoreStrums(
        targets: [ScoringTarget(4), ScoringTarget(4.5)],
        onsets: [],
      );
      expect(r.missed, 2);
      expect(r.matched, 0);
      expect(r.accuracy, 0.0);
      expect(
        r.verdicts.map((v) => v.judgment),
        everyElement(StrumJudgment.missed),
      );
    });

    test('容差边界:恰 180ms 配上(闭),180.1ms 判漏', () {
      // 拍周期取 1000ms:拍差 0.18 折秒恰为字面量 0.18,无折算浮点尾。
      final atEdge = scoreStrums(
        targets: [ScoringTarget(4)],
        onsets: [const ScoredOnset(4.18, 1000)],
      );
      expect(atEdge.matched, 1);

      final pastEdge = scoreStrums(
        targets: [ScoringTarget(4)],
        onsets: [const ScoredOnset(4.1801, 1000)],
      );
      expect(pastEdge.missed, 1);
    });
  });

  group('贪心全局最近配对', () {
    test('高拍密度窗重叠:最近的候选对先配,后拍不被先拍抢走', () {
      // 目标 0 / 0.15s(拍周期 150ms);onset 0 与 0.14s。
      // 朴素逐拍最近会把 0.14s 抢给目标 0(距 140ms)再让目标 1 落空;
      // 全局贪心先配 (0.14s↔目标1,差 10ms),onset 0 归目标 0。
      final r = scoreStrums(
        targets: [ScoringTarget(0), ScoringTarget(1)],
        onsets: [
          const ScoredOnset(0, 150),
          const ScoredOnset(0.14 / 0.15, 150),
        ],
      );
      expect(r.verdicts[0].judgment, StrumJudgment.onTime);
      expect(r.verdicts[1].judgment, StrumJudgment.onTime);
      expect(
        r.verdicts[1].errorSec,
        closeTo(-0.01, 1e-9),
        reason: 'onset 在 0.14s、目标在 0.15s → 偏早 10ms',
      );
    });

    test('一个 onset 夹两拍中间:只配更近的那拍,另一拍判漏(不双计)', () {
      // 目标 0 / 0.15s;onset 0.12s:距目标 1 仅 30ms,距目标 0 120ms(容差内)。
      // 全局贪心:30ms 先配目标 1;该 onset 已被占用,目标 0 不再配 → 漏。
      final r = scoreStrums(
        targets: [ScoringTarget(0), ScoringTarget(1)],
        onsets: [ScoredOnset(0.12 / 0.15, 150)],
      );
      expect(r.verdicts[0].judgment, StrumJudgment.missed);
      expect(
        r.verdicts[1].judgment,
        StrumJudgment.onTime,
        reason: '−30ms 在 ±50ms 准窗内',
      );
      expect(r.verdicts[1].errorSec, closeTo(-0.03, 1e-9));
    });

    test('一个 onset 只配一个目标:扫两下记三拍的谱不虚配', () {
      final r = scoreStrums(
        targets: [ScoringTarget(0), ScoringTarget(1), ScoringTarget(2)],
        onsets: [ScoredOnset(0, 150), ScoredOnset(1, 150)],
      );
      expect(r.matched, 2);
      expect(r.missed, 1);
      expect(r.verdicts[2].judgment, StrumJudgment.missed);
    });
  });

  group('「错」判定(Chroma 封闭验证回调)', () {
    test('时机命中但回调判否 → 错;计入 matched 与 wrong', () {
      final r = scoreStrums(
        targets: [
          ScoringTarget(4, chord: 'C'),
          ScoringTarget(4.5, chord: 'G'),
        ],
        onsets: [onsetAtBeat(4), onsetAtBeat(4.5)],
        verifyChord: (onsetIndex, chord) => chord != 'C', // C 判否
      );
      expect(r.verdicts[0].judgment, StrumJudgment.wrong);
      expect(r.verdicts[1].judgment, StrumJudgment.onTime);
      expect(r.wrong, 1);
      expect(r.matched, 2, reason: '错也算听到(响了),漏不计入');
      expect(r.accuracy, 1.0, reason: '准确率=听到的比例,错弦单独成列');
      expect(r.verdicts[0].errorSec, closeTo(0, 1e-9), reason: '错仍带时机误差');
    });

    test('无目标和弦(chord null)不调用回调,判时机', () {
      var calls = 0;
      final r = scoreStrums(
        targets: [ScoringTarget(4)],
        onsets: [onsetAtBeat(4)],
        verifyChord: (_, _) {
          calls++;
          return false;
        },
      );
      expect(calls, 0);
      expect(r.verdicts.single.judgment, StrumJudgment.onTime);
    });

    test('无回调:永不判错', () {
      final r = scoreStrums(
        targets: [ScoringTarget(4, chord: 'C')],
        onsets: [onsetAtBeat(4)],
      );
      expect(r.verdicts.single.judgment, StrumJudgment.onTime);
    });
  });

  group('延迟校准移位', () {
    test('onset 系统性偏晚一个链路延迟:减去后判准', () {
      // 物理延迟 0.1s:onset 全部晚 0.1s。
      final r = scoreStrums(
        targets: [ScoringTarget(4)],
        onsets: [ScoredOnset(4 + 0.1 / 0.75, 750)],
        latencySec: 0.1,
      );
      expect(r.verdicts.single.judgment, StrumJudgment.onTime);
      expect(r.verdicts.single.errorSec, closeTo(0, 1e-9));
    });

    test('过补:延迟减多了整体偏早', () {
      final r = scoreStrums(
        targets: [ScoringTarget(4)],
        onsets: [ScoredOnset(4 + 0.1 / 0.75, 750)],
        latencySec: 0.16, // −60ms,出 ±50ms 准窗
      );
      expect(r.verdicts.single.judgment, StrumJudgment.early);
      expect(r.verdicts.single.errorSec, closeTo(-0.06, 1e-9));
    });

    test('平均带符号误差:整体偏晚为正(校准方向指南针)', () {
      final r = scoreStrums(
        targets: [ScoringTarget(4), ScoringTarget(4.5)],
        onsets: [
          ScoredOnset(4 + 0.1 / 0.75, 750),
          ScoredOnset(4.5 + 0.02 / 0.75, 750),
        ],
        latencySec: 0.06,
      );
      // 误差 +0.04 与 −0.04,均值 0。
      expect(r.meanSignedErrorSec, closeTo(0, 1e-9));
      expect(r.meanAbsErrorSec, closeTo(0.04, 1e-9));
    });
  });

  group('变速后的拍域尺度', () {
    test('各 onset 按各自检出周期折秒:半速段周期翻倍照样判准', () {
      // 目标在第 4/4.5 拍;onset 检出于半速段(period 1500ms),
      // 物理时刻恰在拍点(beat 换算:0.05s 物理误差 = 0.05/1.5 拍)。
      final r = scoreStrums(
        targets: [ScoringTarget(4), ScoringTarget(4.5)],
        onsets: [
          ScoredOnset(4 + 0.02 / 1.5, 1500),
          ScoredOnset(4.5 - 0.03 / 1.5, 1500),
        ],
      );
      expect(r.verdicts[0].judgment, StrumJudgment.onTime);
      expect(r.verdicts[1].judgment, StrumJudgment.onTime);
      expect(r.verdicts[1].errorSec, closeTo(-0.03, 1e-9));
    });

    test('半速段同样的拍偏移 = 双倍物理误差,超窗判早晚', () {
      final r = scoreStrums(
        targets: [ScoringTarget(4)],
        onsets: [ScoredOnset(4 + 0.06 / 1.5, 1500)], // 物理偏晚 60ms
      );
      expect(r.verdicts.single.judgment, StrumJudgment.late);
      expect(r.verdicts.single.errorSec, closeTo(0.06, 1e-9));
    });
  });

  test('verdicts 与 targets 同序(报告轨道按谱序铺格的前提)', () {
    final r = scoreStrums(
      targets: [
        ScoringTarget(4),
        ScoringTarget(4.5),
        ScoringTarget(5),
        ScoringTarget(5.5),
      ],
      onsets: [onsetAtBeat(4), onsetAtBeat(5)],
    );
    expect(r.verdicts, hasLength(4));
    expect(r.verdicts[0].judgment, StrumJudgment.onTime);
    expect(r.verdicts[1].judgment, StrumJudgment.missed);
    expect(r.verdicts[2].judgment, StrumJudgment.onTime);
    expect(r.verdicts[3].judgment, StrumJudgment.missed);
  });

  test('空输入:total 0,准确率 0,不炸', () {
    final r = scoreStrums(targets: [], onsets: []);
    expect(r.total, 0);
    expect(r.accuracy, 0.0);
    expect(r.verdicts, isEmpty);
  });
}
