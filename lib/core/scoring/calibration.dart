/// 预备数拍延迟校准(GLOSSARY「延迟校准」)的估计核。
///
/// 预备数拍期间用户照常扫四下:麦检出的 onset 与四下预备拍位经
/// `matchPairs` 配对后,每对误差 = 该下的链路偏移(麦输入+扬声器输出
/// 的固定延迟,含用户的时机抖动);取**中位数**抗单下抖动,即得偏移
/// 估计。采不到(预备期没有可配 onset)返回 null——调用方退回持久化值。
/// 纯函数;配对本身在 strum_scorer.dart(同一贪心算法,校准与评分不分叉)。
library;

import 'strum_scorer.dart';

/// 无校准数据时的缺省链路延迟(秒)。真机常见量级 ~0.1(demo 前史)。
const double defaultLatencySec = 0.10;

/// matched 对误差的中位数;空返回 null。
double? calibrateLatencySec(List<ScoredPair> matchedPairs) {
  if (matchedPairs.isEmpty) return null;
  final errors = [for (final (_, _, err) in matchedPairs) err]..sort();
  final mid = errors.length ~/ 2;
  return errors.length.isOdd
      ? errors[mid]
      : (errors[mid - 1] + errors[mid]) / 2;
}
