/// 节奏型（GLOSSARY「节奏型」）：右手的固定扫弦组合，4/4 一小节循环。
///
/// v1 按八分音符网格建模：每小节 [eighthsPerBar] 槽，槽位自 0，
/// 空拍（null）不扫。纯模型，零依赖——工单 08 时间轴编译直接消费：
/// 谱 + 节奏型 + BPM → 每小节按槽位铺扫弦事件。
library;

/// 每小节八分音符槽位数（4/4：4 拍 × 每拍 2 槽，与 core/audio 的
/// `beatsPerBar` 领域常量同源，v1 拍号固定 4/4）。
const int eighthsPerBar = 8;

/// 单次扫弦方向：↓ 下扫 / ↑ 上扫。
enum StrumDirection { down, up }

/// 一个节奏型。
class StrumPattern {
  /// [slots] 必须恰好 [eighthsPerBar] 槽（契约，见内置集合的守护测试；
  /// 不用断言检查是为保住 const 构造）。
  const StrumPattern({
    required this.id,
    required this.name,
    required this.slots,
  });

  /// 稳定标识（测试 key、日后引用用），不进 UI。
  final String id;

  /// 数拍记法名（如「下 下上 上下上」），UI 直接显示。
  final String name;

  /// 一小节的逐槽动作；null = 空拍。挥拍物理上偶数槽只能下扫、
  /// 奇数槽只能上扫（手连续摆动不反向），内置集合有测试守护。
  final List<StrumDirection?> slots;

  /// 节奏型内的全部扫弦动作（槽位, 方向），按槽位顺序——
  /// 训练页箭头与工单 08 编译共用这一视图。
  List<(int slot, StrumDirection stroke)> get strokes => [
    for (var slot = 0; slot < slots.length; slot++)
      if (slots[slot] != null) (slot, slots[slot]!),
  ];
}
