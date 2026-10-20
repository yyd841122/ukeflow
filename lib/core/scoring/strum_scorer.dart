/// 扫弦评分判定(GLOSSARY「跟练评分」):给定时间轴上的期望扫弦点(拍域)
/// 与麦检出的 onset(拍域),对每个扫弦点判定 ✓/早/晚/漏/错。
///
/// 纯函数、零依赖(dart:typed_data 都不用),标准 flutter test 覆盖;
/// 检测质量是 OnsetDetector 的事,这里只管两组时刻算得对(ukulele-demo
/// strum_scorer 的拍域移植,配对算法原样保留)。
///
/// =拍域(工单 33)=
/// 期望与 onset 都以**拍**为单位(自调度 t0 起,预备 4 拍即 0..3,正曲
/// 扫弦 = 4 + 槽位/2)。变速/暂停重锚只动秒域映射,拍位是守恒量——
/// 判定误差按**各 onset 检出时刻的拍周期**折回秒(变速段扫的,按当时的
/// 拍速算你早了几毫秒),容差/准窗是物理秒:
///   errorSec = (onset拍 − 期望拍) × 该onset检出周期 − 链路延迟秒
library;

/// 待判定的扫弦点:拍位 + 目标和弦。
///
/// [beat] 自调度 t0 起的拍序号(含预备段;预备四拍是 0..3,校准专用)。
/// [chord] 为 null(谱首尚无和弦记号)时不判「错」。
class ScoringTarget {
  const ScoringTarget(this.beat, {this.chord});

  final double beat;
  final String? chord;
}

/// 麦检出的一个 onset:拍位 + 检出时刻的拍周期(毫秒)。
///
/// [periodMs] 是该 onset 检出那一刻的时间轴拍周期:变速后各 onset 尺度
/// 各异,误差折秒、容差比较都按各自尺度(见库注释)。
class ScoredOnset {
  const ScoredOnset(this.beat, this.periodMs);

  final double beat;
  final double periodMs;
}

/// 一个扫弦点的判定(GLOSSARY 五判定)。
enum StrumJudgment {
  /// 漏:容差窗内没听到扫弦。
  missed,

  /// 早:听到了,但偏早出准窗。
  early,

  /// 准:时机误差在准窗内。
  onTime,

  /// 晚:听到了,但偏晚出准窗。
  late,

  /// 错:时机窗内响了,但 Chroma 封闭验证不过(和弦不对)。
  wrong,
}

/// 单个扫弦点的判定 + 时机误差。[errorSec] = onset − expected(秒):
/// 正 = 偏晚、负 = 偏早;missed 时无意义(恒 0)。wrong 也带时机误差
/// (响了,时机另算)。
class StrumVerdict {
  const StrumVerdict(this.judgment, this.errorSec);

  final StrumJudgment judgment;
  final double errorSec;
}

/// 一次评分的汇总。[verdicts] 与传入 targets **同序**(= 谱序,报告
/// 扫弦点轨道按此铺格)。
class ScoreResult {
  const ScoreResult({
    required this.total,
    required this.matched,
    required this.missed,
    required this.early,
    required this.onTime,
    required this.late,
    required this.wrong,
    required this.accuracy,
    required this.meanAbsErrorSec,
    required this.meanSignedErrorSec,
    required this.verdicts,
  });

  /// 期望扫弦点数。
  final int total;

  /// 容差窗内听到 onset 的点数(准+早+晚+错;「错」也算听到)。
  final int matched;
  final int missed;
  final int early;
  final int onTime;
  final int late;
  final int wrong;

  /// matched / total(0..1);total=0 → 0。
  final double accuracy;

  /// matched 点的 |误差| 均值 / 带符号误差均值(正=整体偏晚、负=整体
  /// 偏早——延迟校准的方向指南针)。
  final double meanAbsErrorSec;
  final double meanSignedErrorSec;
  final List<StrumVerdict> verdicts;
}

/// 判定容差(秒):|onset−期望| 超过它判漏(demo 前史值,票面共识)。
const double strumToleranceSec = 0.18;

/// 「准」窗(秒):命中后 |误差| ≤ 它算准,否则分早/晚。
const double strumOnTimeWindowSec = 0.05;

/// 「错」验证回调:onset 下标 + 该点目标和弦 → 是否对。实现在调用侧
/// (Chroma 封闭验证,纯函数不掺频谱)。
typedef ChordVerifier = bool Function(int onsetIndex, String chord);

/// 一对候选配对(target 下标, onset 下标, 时机误差秒)。配对产出供
/// 评分与预备数拍延迟校准共用(校准取 matched 对的误差取中位数)。
typedef ScoredPair = (int targetIndex, int onsetIndex, double errorSec);

/// 贪心全局最近配对(ukulele-demo 原算法):所有距离 ≤ 容差的
/// (target, onset) 候选对按 |误差| 升序排,从最近的开始配,配过的
/// target/onset 不再配。高拍密度(容差窗重叠)时朴素逐拍最近会把 onset
/// 抢给前一拍、后拍误判漏——全局贪心是踩过坑的修正(demo 前史)。
///
/// 误差按各 onset 检出周期折秒,再减 [latencySec](校准调用传 0,
/// 误差即原始链路偏移)。
List<ScoredPair> matchPairs({
  required List<ScoringTarget> targets,
  required List<ScoredOnset> onsets,
  required double toleranceSec,
  double latencySec = 0,
}) {
  final pairs = <(int, int, double, double)>[]; // (ti, oi, |err|, err)
  for (var oi = 0; oi < onsets.length; oi++) {
    final onset = onsets[oi];
    final secPerBeat = onset.periodMs / 1000;
    for (var ti = 0; ti < targets.length; ti++) {
      // 拍差按该 onset 尺度折秒;粗筛用拍距 × 尺度上界避免逐对折算?
      // targets ≤ 数百、onsets ≤ 数百,直接逐对折算,量级无虞。
      final err = (onset.beat - targets[ti].beat) * secPerBeat - latencySec;
      final dist = err.abs();
      if (dist <= toleranceSec) pairs.add((ti, oi, dist, err));
    }
  }
  pairs.sort((a, b) => a.$3.compareTo(b.$3));
  final targetTaken = List<bool>.filled(targets.length, false);
  final onsetTaken = List<bool>.filled(onsets.length, false);
  final out = <ScoredPair>[];
  for (final (ti, oi, _, err) in pairs) {
    if (targetTaken[ti] || onsetTaken[oi]) continue;
    targetTaken[ti] = true;
    onsetTaken[oi] = true;
    out.add((ti, oi, err));
  }
  return out;
}

/// 评分主函数。verdicts 与 [targets] 同序。
ScoreResult scoreStrums({
  required List<ScoringTarget> targets,
  required List<ScoredOnset> onsets,
  double latencySec = 0,
  double toleranceSec = strumToleranceSec,
  double onTimeWindowSec = strumOnTimeWindowSec,
  ChordVerifier? verifyChord,
}) {
  final matchedError = List<double?>.filled(targets.length, null);
  final matchedOnset = List<int?>.filled(targets.length, null);
  for (final (ti, oi, err) in matchPairs(
    targets: targets,
    onsets: onsets,
    toleranceSec: toleranceSec,
    latencySec: latencySec,
  )) {
    matchedError[ti] = err;
    matchedOnset[ti] = oi;
  }

  var matched = 0, missed = 0, early = 0, onTime = 0, late = 0, wrong = 0;
  var sumAbs = 0.0, sumSigned = 0.0;
  final verdicts = <StrumVerdict>[];
  for (var ti = 0; ti < targets.length; ti++) {
    final err = matchedError[ti];
    if (err == null) {
      missed++;
      verdicts.add(const StrumVerdict(StrumJudgment.missed, 0));
      continue;
    }
    matched++;
    sumAbs += err.abs();
    sumSigned += err;
    final chord = targets[ti].chord;
    final chordMismatch =
        chord != null &&
        verifyChord != null &&
        !verifyChord(matchedOnset[ti]!, chord);
    final StrumJudgment judgment;
    if (chordMismatch) {
      judgment = StrumJudgment.wrong;
      wrong++;
    } else if (err.abs() <= onTimeWindowSec) {
      judgment = StrumJudgment.onTime;
      onTime++;
    } else if (err < 0) {
      judgment = StrumJudgment.early;
      early++;
    } else {
      judgment = StrumJudgment.late;
      late++;
    }
    verdicts.add(StrumVerdict(judgment, err));
  }

  final total = targets.length;
  return ScoreResult(
    total: total,
    matched: matched,
    missed: missed,
    early: early,
    onTime: onTime,
    late: late,
    wrong: wrong,
    accuracy: total == 0 ? 0 : matched / total,
    meanAbsErrorSec: matched == 0 ? 0 : sumAbs / matched,
    meanSignedErrorSec: matched == 0 ? 0 : sumSigned / matched,
    verdicts: verdicts,
  );
}
