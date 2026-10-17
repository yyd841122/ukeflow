import 'pitch_math.dart';

/// 调音读数:阻尼后的频率与其音名/音分换算(UI 全部显示数据源)。
class TunerReading {
  const TunerReading({
    required this.freq,
    required this.midi,
    required this.noteName,
    required this.cents,
  });

  /// 阻尼后的检测频率 Hz。
  final double freq;

  /// 最近音 MIDI 编号与音名(如 'A4')。
  final int midi;
  final String noteName;

  /// 相对最近音的偏差音分(±50 内)。
  final double cents;
}

/// 检测读数滤波(工单 19):静音闸 + 频窗 + 频率阻尼,纯函数——时序由
/// 调用方以 [TunerFilter.push] 的 `at` 显式驱动,本类不持时钟。
///
/// - **静音闸**:YIN 判非音高(freq 为 null)或置信度低于
///   [TunerFilter.minProbability] 的帧不产生读数——静音/环境噪声不得
///   误导调弦(工单验收:静音不乱报)。对说话只做到「大多不误报」:
///   频窗滤掉男声基频(85–180 Hz),女/童声(165–255 Hz)与窗下沿仍有
///   重叠,靠置信度闸+阻尼压低显示概率——说话能否稳定骗出读数,归
///   真机验收(工单验收:静音/说话不误报)现场核。
/// - **频窗**:220–880 Hz 之外不采。窗覆盖 GCEA 空弦大幅走音的取域
///   (C4 低 3 半音 = 220 起到 A4 高八度 = 880 止)。
/// - **阻尼**:对频率做指数平滑(α=[TunerFilter.alpha],新样本权重),
///   读数由平滑值统一换算音名/音分——指针不狂跳,拨弦稳定段 ~0.3s
///   收敛(工单验收:读数适度阻尼)。
/// - **失效重置**:超过 [TunerFilter.holdDuration] 无有效帧即丢弃平滑
///   历史,下一次拨弦立即吸附新音,不从陈旧读数缓慢滑过去。
class TunerFilter {
  /// 置信度下限(YIN 概率;真琴拨弦衰减段仍远高于此,噪声远低于此)。
  static const double minProbability = 0.8;

  /// 采样频窗 Hz(见类注释取域论证)。
  static const double minFreq = 220.0;
  static const double maxFreq = 880.0;

  /// 阻尼系数:新样本权重(0.4 → 每帧收敛 ~60% 残差,60ms 帧距)。
  static const double alpha = 0.4;

  /// 平滑历史有效期;超过即重置。
  static const Duration holdDuration = Duration(milliseconds: 500);

  Duration? _lastValidAt;
  double? _smoothed;

  TunerReading? push({
    required double? freq,
    required double probability,
    required Duration at,
    double a4 = referenceA4,
  }) {
    final valid =
        freq != null &&
        probability >= minProbability &&
        freq >= minFreq &&
        freq <= maxFreq;
    if (!valid) return null;

    final f = freq;
    final stale = _lastValidAt == null || at - _lastValidAt! > holdDuration;
    _smoothed = stale ? f : _smoothed! + alpha * (f - _smoothed!);
    _lastValidAt = at;

    final note = nearestNote(_smoothed!, a4: a4);
    return TunerReading(
      freq: _smoothed!,
      midi: note.midi,
      noteName: note.name,
      cents: note.cents,
    );
  }

  /// 停止拾音时清历史(下次开始从新样本起算)。
  void reset() {
    _lastValidAt = null;
    _smoothed = null;
  }
}
