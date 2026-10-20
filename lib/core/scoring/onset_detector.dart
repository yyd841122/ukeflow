/// 扫弦起始检测(工单 33 跟练评分):给一段麦克风样本,检出其中的扫弦
/// onset 时刻。纯 Dart(只依赖 dart:typed_data + dart:math),标准
/// flutter test 无头覆盖(ukulele-demo OnsetDetector 移植,配方真机验证过)。
///
/// =滤波链(承重墙)=
/// 评分时 app 自打评分嘀声(880/1320Hz,见 ScoringTickSynth),麦会收进
/// 来;不滤掉则每拍误判成扫弦、分数虚高。链:高通 150Hz(去环境隆隆/
/// 人声/碰琴)→ 陷波 880 → 陷波 1320(嘀声双基频)。扫弦是宽带瞬态,
/// 窄缝几乎不伤它;嘀声是窄带纯音 + 4ms 软化淡入,正好被深吃(≥40dB,
/// 回归锁在 onset_detector_test)。
///
/// =onset 算法(能量通量法)=
/// 滤波后 ~10ms 一帧算功率 → 相邻帧功率正向差(flux,半波整流)→
/// flux 超 自适应阈值(3×近 0.5s flux 均值,取地板前)+ 功率过安静门 +
/// 距上次 onset 超不应期(120ms)→ 记候选;候选要后续 2 帧能量仍撑在
/// floor 上(持续性门)才确认——挡陷波后残余的短嘀尖峰。
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 二阶 IIR 滤波器(双二阶),转置直接 II 型(数值稳,2 个状态 z1/z2)。
/// 系数按 Audio EQ Cookbook 算,归一化到 a0=1。状态跨 chunk 连续:
/// 实例持续喂样本 = 连续滤波。公开可构造:承重墙测试直接拼链断言衰减。
class Biquad {
  final double b0, b1, b2, a1, a2;
  double _z1 = 0, _z2 = 0;

  Biquad._(this.b0, this.b1, this.b2, this.a1, this.a2);

  /// 高通(Butterworth,Q≈0.707)。
  factory Biquad.highpass(double freq, int sampleRate, [double q = 0.707]) {
    final w = 2 * math.pi * freq / sampleRate;
    final cw = math.cos(w), sw = math.sin(w);
    final alpha = sw / (2 * q);
    final b0 = (1 + cw) / 2, b1 = -(1 + cw), b2 = (1 + cw) / 2;
    final a0 = 1 + alpha, a1 = -2 * cw, a2 = 1 - alpha;
    return Biquad._(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  /// 陷波:在 [freq] 挖窄缝,Q 越大缝越窄越深。
  factory Biquad.notch(double freq, int sampleRate, [double q = 7]) {
    final w = 2 * math.pi * freq / sampleRate;
    final cw = math.cos(w), sw = math.sin(w);
    final alpha = sw / (2 * q);
    final b0 = 1.0, b1 = -2 * cw, b2 = 1.0;
    final a0 = 1 + alpha, a1 = -2 * cw, a2 = 1 - alpha;
    return Biquad._(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);
  }

  /// 原地滤波(边读边写回);局部变量缓存系数+状态(热路径)。
  void processInPlace(Float64List s) {
    var z1 = _z1, z2 = _z2;
    final b0 = this.b0, b1 = this.b1, b2 = this.b2, a1 = this.a1, a2 = this.a2;
    for (var i = 0; i < s.length; i++) {
      final x = s[i];
      final y = b0 * x + z1;
      z1 = b1 * x - a1 * y + z2;
      z2 = b2 * x - a2 * y;
      s[i] = y;
    }
    _z1 = z1;
    _z2 = z2;
  }

  /// 复位状态(新评分会话前调,滤波尾不串场)。
  void reset() {
    _z1 = 0;
    _z2 = 0;
  }
}

/// 扫弦起始检测器。流式:每来一段麦样本 [process] 一次,带上这段
/// **末样本的到达时刻**(秒,调用方统一时钟——UkeFlow 语境即引擎钟,
/// ADR-0005;demo 单开 Stopwatch 的做法不照抄),返回新检出 onset 的
/// 同钟时刻。延迟补偿(链路固定延迟)不在这里——调用方匹配时减。
class OnsetDetector {
  final int sampleRate;
  final int hop;
  final double refractorySec;
  final double adaptiveK;
  final double fluxFloor;
  final double minEnergy;
  final int minSustainFrames;

  final Biquad _hp;
  final Biquad _notch1;
  final Biquad _notch2;

  // 上次没凑满一帧的【已滤波】尾部,拼帧用(只存已滤波的,免得重复滤)。
  Float64List _carry = Float64List(0);
  double _prevEnergy = 0;

  // flux 滑窗(环缓冲)算自适应阈值。
  final List<double> _fluxHist;
  int _fluxIdx = 0;
  int _fluxFilled = 0;
  double _fluxSum = 0;

  double _lastOnsetSec = -1e9;

  // 持续性门:上升沿先记候选,后续 minSustainFrames 帧仍撑在 floor 上才确认。
  double? _candidateTime;
  int _confirmFramesLeft = 0;

  OnsetDetector({
    this.sampleRate = 44100,
    int? hop,
    this.refractorySec = 0.12,
    this.adaptiveK = 3.0,
    this.fluxFloor = 2e-4,
    this.minEnergy = 3e-4,
    this.minSustainFrames = 2,
    int historyLen = 50, // ~0.5s 的帧数(10ms 一帧)
    double hpFreq = 150,
    double notchFreq1 = 880,
    double notchFreq2 = 1320,
    double notchQ = 7,
  }) : hop = hop ?? (0.010 * sampleRate).round(),
       _hp = Biquad.highpass(hpFreq, sampleRate),
       _notch1 = Biquad.notch(notchFreq1, sampleRate, notchQ),
       _notch2 = Biquad.notch(notchFreq2, sampleRate, notchQ),
       _fluxHist = List<double>.filled(historyLen, 0.0);

  /// 处理一段新样本 [chunk](单声道,-1..1),[arrivalSec] = 这段末样本
  /// 的时刻(秒,调用方时钟)。返回这段里新检出的 onset 时刻(同钟)。
  List<double> process(Float64List chunk, double arrivalSec) {
    if (chunk.isEmpty) return const [];
    // 1) 只滤这次的新样本(滤波器状态跨调用连续,不重复滤 carry)。
    //    拷一份,不改调用方的缓冲。
    final filt = Float64List.fromList(chunk);
    _hp.processInPlace(filt);
    _notch1.processInPlace(filt);
    _notch2.processInPlace(filt);

    // 2) 拼连续流(carry + filt)逐帧算功率、判 onset。
    final carry = _carry;
    final carryLen = carry.length;
    final total = carryLen + filt.length;
    final onsets = <double>[];
    var pos = 0;
    while (pos + hop <= total) {
      var energy = 0.0;
      for (var j = 0; j < hop; j++) {
        final gp = pos + j;
        final v = gp < carryLen ? carry[gp] : filt[gp - carryLen];
        energy += v * v;
      }
      energy /= hop;
      // 帧中心 → 秒(arrivalSec 是合流末样本的时刻)。
      final centerSample = pos + hop / 2.0;
      final t = arrivalSec - (total - centerSample) / sampleRate;
      _detect(energy, t, onsets);
      pos += hop;
    }

    // 3) 尾部留到下次拼帧。
    final tailLen = total - pos;
    final tail = Float64List(tailLen);
    for (var j = 0; j < tailLen; j++) {
      final gp = pos + j;
      tail[j] = gp < carryLen ? carry[gp] : filt[gp - carryLen];
    }
    _carry = tail;
    return onsets;
  }

  /// 一帧功率 → flux → 阈值 + 地板 + 安静门 + 不应期 + 持续性综合判定。
  /// 两处顺序坑(demo 前史):(1) 阈值用【加入当前 flux 之前】的滑窗均值
  /// ——否则当前大 flux 顶高自己的阈值,反而检不出;(2) 滑窗无论本帧
  /// 是否触发都要更新——否则基准停滞。
  void _detect(double energy, double t, List<double> onsets) {
    final flux = energy > _prevEnergy ? energy - _prevEnergy : 0.0;
    _prevEnergy = energy;

    final meanFlux = _fluxFilled > 0 ? _fluxSum / _fluxFilled : 0.0;
    final threshold = math.max(adaptiveK * meanFlux, fluxFloor);

    _fluxSum -= _fluxHist[_fluxIdx];
    _fluxHist[_fluxIdx] = flux;
    _fluxSum += flux;
    _fluxIdx = (_fluxIdx + 1) % _fluxHist.length;
    if (_fluxFilled < _fluxHist.length) _fluxFilled++;

    // 1) 候选确认中:本帧仍撑在 floor 上?撑住倒计满 → 确认;塌了 → 弃。
    if (_candidateTime != null) {
      if (energy > minEnergy) {
        _confirmFramesLeft--;
        if (_confirmFramesLeft <= 0) {
          onsets.add(_candidateTime!);
          _lastOnsetSec = _candidateTime!;
          _candidateTime = null;
        }
      } else {
        _candidateTime = null;
      }
      return; // 确认窗内不另起候选(不应期也会挡,直接 return 更省)。
    }

    // 2) 检测新上升沿 → 记候选,等后续帧确认。
    if (flux > threshold &&
        energy > minEnergy &&
        (t - _lastOnsetSec) >= refractorySec) {
      _candidateTime = t;
      _confirmFramesLeft = minSustainFrames;
    }
  }

  /// 复位:新一次评分会话前全部清零,不串上一会话。
  void reset() {
    _hp.reset();
    _notch1.reset();
    _notch2.reset();
    _carry = Float64List(0);
    _prevEnergy = 0;
    for (var i = 0; i < _fluxHist.length; i++) {
      _fluxHist[i] = 0;
    }
    _fluxIdx = 0;
    _fluxFilled = 0;
    _fluxSum = 0;
    _lastOnsetSec = -1e9;
    _candidateTime = null;
    _confirmFramesLeft = 0;
  }
}
