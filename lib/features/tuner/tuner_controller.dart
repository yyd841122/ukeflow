import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';

import '../../core/tuner/tuner_filter.dart';
import '../../core/tuner/tuner_recorder.dart';

/// 调音器页状态。
class TunerState {
  const TunerState({
    required this.listening,
    required this.permissionDenied,
    this.reading,
    this.error,
  });

  const TunerState.initial()
    : listening = false,
      permissionDenied = false,
      reading = null,
      error = null;

  /// 正在拾音。
  final bool listening;

  /// 权限被拒后的引导态(页面上指去系统设置);再开始成功即清。
  final bool permissionDenied;

  /// 当前阻尼读数;静音/噪声段 null(不显示音高)。
  final TunerReading? reading;

  /// 麦克风启动失败等错误文案;null = 正常。
  final String? error;

  TunerState copyWith({
    bool? listening,
    bool? permissionDenied,
    Object? reading = _sentinel,
    Object? error = _sentinel,
  }) => TunerState(
    listening: listening ?? this.listening,
    permissionDenied: permissionDenied ?? this.permissionDenied,
    reading: identical(reading, _sentinel) ? this.reading : reading as TunerReading?,
    error: identical(error, _sentinel) ? this.error : error as String?,
  );

  static const _sentinel = Object();
}

final tunerProvider = NotifierProvider<TunerController, TunerState>(
  TunerController.new,
);

/// 调音控制器(工单 19,spike A 迁入):麦克风采集 → YIN 检测 → 静音闸
/// +阻尼滤波 → 读数。
///
/// 检测参数与 spike 真琴验证一致:2048 样本窗、60ms 检测节流;采集参数
/// (PCM16/44.1kHz/单声道)定死在 [TunerRecorder] 实现。滤波语义见
/// [TunerFilter](静音不乱报、读数阻尼)。
class TunerController extends Notifier<TunerState> {
  static const _bufSamples = 2048;
  static const _detectInterval = Duration(milliseconds: 60);

  final TunerFilter _filter = TunerFilter();
  final PitchDetector _detector = PitchDetector(
    audioSampleRate: 44100,
    bufferSize: _bufSamples,
  );

  StreamSubscription<Uint8List>? _sub;

  /// 最近 [_bufSamples] 个样本的 PCM16LE 字节(攒窗)。
  final List<int> _pcm = [];
  DateTime _lastDetect = DateTime.fromMillisecondsSinceEpoch(0);

  /// 本次拾音会话起点(滤波时序基准,与 _lastDetect 同帧初始化)。
  DateTime _sessionStart = DateTime.now();
  bool _detecting = false;

  @override
  TunerState build() {
    final recorder = ref.watch(tunerRecorderProvider);
    ref.onDispose(() {
      _sub?.cancel();
      recorder.stop();
    });
    return const TunerState.initial();
  }

  /// 开始/停止切换(页面按钮同一入口;与节拍器/训练器控制器同惯用法)。
  Future<void> toggle() => state.listening ? stop() : start();

  /// 开始拾音:两段式权限(先查状态,拒则请求弹窗,再拒进引导态),
  /// 通过后开采集。已在监听则空操作。
  Future<void> start() async {
    if (state.listening) return;
    final recorder = ref.read(tunerRecorderProvider);
    var granted = await recorder.hasPermission(request: false);
    if (!granted) granted = await recorder.hasPermission(); // 系统弹窗
    if (!ref.mounted) return;
    if (!granted) {
      state = state.copyWith(listening: false, permissionDenied: true);
      return;
    }
    try {
      final stream = await recorder.startStream();
      if (!ref.mounted) return;
      _sub?.cancel();
      _pcm.clear();
      _filter.reset();
      _lastDetect = DateTime.fromMillisecondsSinceEpoch(0);
      _sessionStart = DateTime.now();
      _sub = stream.listen(_onChunk);
      state = state.copyWith(
        listening: true,
        permissionDenied: false,
        reading: null,
        error: null,
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(error: '麦克风启动失败:$error');
    }
  }

  /// 停止拾音:退流、停麦、清读数与滤波历史。
  ///
  /// 状态先翻转、订阅即废不等 cancel——cancel 的完成在 widget 测试的
  /// fake 时钟下不被任何 pump 驱动(实测),await 它会让整条链停摆到
  /// 测试收尾;真实事件循环里它至多再投递一帧在途数据,下一帧被
  /// listening=false 闸拦下,无害。
  Future<void> stop() async {
    _sub?.cancel();
    _sub = null;
    _filter.reset();
    if (!ref.mounted) return;
    state = state.copyWith(listening: false, reading: null);
    // 停麦失败不回滚状态:采集侧已断,重试由再「开始」覆盖。
    await ref.read(tunerRecorderProvider).stop();
  }

  Future<void> _onChunk(Uint8List bytes) async {
    // 攒窗:追加新样本,只留最近 2048 个(字节按 2 对齐)。
    _pcm.addAll(bytes);
    final keepBytes = _bufSamples * 2;
    if (_pcm.length > keepBytes) {
      _pcm.removeRange(0, _pcm.length - keepBytes);
    }
    if (_pcm.length < keepBytes || _detecting) return;
    final now = DateTime.now();
    if (now.difference(_lastDetect) < _detectInterval) return;
    _lastDetect = now;
    _detecting = true;
    try {
      final result = await _detector.getPitchFromIntBuffer(
        Uint8List.fromList(_pcm),
      );
      if (!ref.mounted || !state.listening) return;
      state = state.copyWith(
        reading: _filter.push(
          freq: result.pitched ? result.pitch : null,
          probability: result.probability,
          at: now.difference(_sessionStart),
        ),
      );
    } finally {
      _detecting = false;
    }
  }
}
