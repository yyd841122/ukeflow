import '../../../core/score/flowing_engraving.dart';
import '../../../core/score/reference_score.dart';

/// 一记按法提示位(票05):弦号 1..4、品位 ≥0(一手转换守门保证,无
/// 非法值可达此层);[isNaturalHarmonic] 的文本按画面数字样式加尖括号(如 `<12>`)。
class FingeringNote {
  const FingeringNote({
    required this.stringNo,
    required this.fret,
    required this.isNaturalHarmonic,
  });

  final int stringNo;
  final int fret;
  final bool isNaturalHarmonic;

  /// 文本片段(与画面数字同一样式):「N弦 空弦」/「N弦 M 品」/泛音品的 M 带尖括号(画面数字同款,如 `<12>`)。
  String get summary => fret == 0
      ? '$stringNo弦 空弦'
      : '$stringNo弦 ${isNaturalHarmonic ? '<$fret>' : '$fret'} 品';
}

/// 一张按法提示卡(票05):[notes] 空 = 无法提示(休止/整组延音——与
/// 画面数字同源判定 [tieChordIds],显式标示,不猜测)。
class FingeringHint {
  const FingeringHint({required this.notes});

  final List<FingeringNote> notes;

  bool get showable => notes.isNotEmpty;

  /// 位置文本行(「1弦 3品 · 2弦 0弦 空弦」式);不可提示时为空串。
  String get summary => notes.map((n) => n.summary).join(' · ');
}

/// 当前 + 下一步按法提示(票05;codex 同款语义):当前 = 二分「最后一
/// 个已越过事件」——与 [FlowingFrame]/画面同一二分,间隙期也显示刚弹
/// 过的按法(手上还按着);下一步 = 后继事件,曲末或无后继 = null。
/// 整组延音/休止 → 无法提示卡。
({FingeringHint current, FingeringHint? next}) fingeringHintsAt(
  ReferenceScore score,
  double seconds, {
  Set<int>? tieChords,
}) {
  final events = score.events;
  var low = 0;
  var high = events.length - 1;
  var index = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (events[mid].startSeconds <= seconds) {
      index = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  final ties = tieChords ?? tieChordIds(score);
  FingeringHint hintOf(RefEvent e) => FingeringHint(
        notes: ties.contains(e.id)
            ? const []
            : [
                for (final n in e.notes)
                  FingeringNote(
                    stringNo: n.stringNo,
                    fret: n.fret,
                    isNaturalHarmonic: n.isNaturalHarmonic,
                  ),
              ],
      );
  return (
    current: index >= 0 ? hintOf(events[index]) : const FingeringHint(notes: []),
    next: index + 1 < events.length ? hintOf(events[index + 1]) : null,
  );
}
