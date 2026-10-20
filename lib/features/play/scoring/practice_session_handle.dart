import '../../../core/practice/play_timeline.dart';
import '../../../../data/chord_library.dart' show Chord;

/// 评分会话对跟练会话的窄依赖(工单 33 测试缝):拍域换算与期望点的
/// 来源。生产实现是 [PlayPracticeController](时间轴/调度锚点/拍周期的
/// 唯一属主);测试注入假柄,不经过真调度器。
///
/// 拍域契约(ADR-0005):[scheduleAnchor] 是调度网格原点(预备第 0 拍)
/// 的引擎时刻;onset 的拍位 = (引擎秒 − anchor 秒) × 1000 / [periodMs]。
/// 暂停重锚与变速换周期都由属主就地更新,评分侧每个 chunk 现读现换算。
abstract interface class PracticeSessionHandle {
  /// 运行中的动作事件时间轴;未运行 null。
  PlayTimeline? get timeline;

  /// 调度网格原点;[timeline] 为 null 时同样 null。
  Duration? get scheduleAnchor;

  /// 当前拍周期(毫秒;变速即时反映)。
  double get periodMs;

  /// 会话和弦表(「错」判定的封闭集模板来源)。
  Map<String, Chord> get chords;

  /// 评分会话接线开关:开 = 节拍声换评分嘀声对(可滤);关 = 回常规
  /// tick。评分侧在会话起止时调用;循环重启等控制器内部重启不复位。
  void setScoringTicks(bool value);
}
