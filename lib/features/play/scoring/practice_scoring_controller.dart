import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/audio_engine.dart';
import '../../../core/audio/providers.dart';
import '../../../core/practice/play_timeline.dart';
import '../../../core/scoring/calibration.dart';
import '../../../core/scoring/chroma.dart';
import '../../../core/scoring/mic_audio_buffer.dart';
import '../../../core/scoring/onset_detector.dart';
import '../../../core/scoring/report.dart';
import '../../../core/scoring/strum_scorer.dart';
import '../../../core/tuner/tuner_recorder.dart';
import '../../../data/settings_providers.dart';
import '../play_practice_controller.dart'
    show PlayPracticeController, playPracticeProvider;
import 'practice_session_handle.dart';

/// 评分会话状态(GLOSSARY「跟练评分」)。
enum ScoringStatus {
  /// 未在评分(空闲面板可开开关)。
  idle,

  /// 采集中(含暂停挂起,见 [PracticeScoringState.suspended])。
  listening,

  /// 已出报告(看完即弃:[PracticeScoringController.closeReport] 回 idle)。
  finished,
}

class PracticeScoringState {
  const PracticeScoringState({
    this.enabled = false,
    this.status = ScoringStatus.idle,
    this.suspended = false,
    this.report,
    this.reportLatencySec,
    this.error,
  });

  /// 空闲面板的评分开关(会话级,不落库)。
  final bool enabled;
  final ScoringStatus status;

  /// 暂停挂起中:采集照跑(音频照存),onset 不收——恢复后时间轴重锚,
  /// 挂起期的 onset 落在锚点之前,收了也配不上。
  final bool suspended;

  /// 全曲报告([status] == finished 时非空;看完即弃,不落库)。
  final ScoringReport? report;

  /// 报告当前延迟值(秒):finish 时为校准/回退结果,滑块拖动即变——
  /// 报告页滑块的值源(拖动实时重算的闭环)。
  final double? reportLatencySec;

  /// 麦克风/权限错误文案;null = 正常。评分失败不拦跟练(照常练)。
  final String? error;

  PracticeScoringState copyWith({
    bool? enabled,
    ScoringStatus? status,
    bool? suspended,
    Object? report = _sentinel,
    Object? reportLatencySec = _sentinel,
    Object? error = _sentinel,
  }) => PracticeScoringState(
    enabled: enabled ?? this.enabled,
    status: status ?? this.status,
    suspended: suspended ?? this.suspended,
    report: identical(report, _sentinel)
        ? this.report
        : report as ScoringReport?,
    reportLatencySec: identical(reportLatencySec, _sentinel)
        ? this.reportLatencySec
        : reportLatencySec as double?,
    error: identical(error, _sentinel) ? this.error : error as String?,
  );

  static const _sentinel = Object();
}

final practiceScoringProvider =
    NotifierProvider<PracticeScoringController, PracticeScoringState>(
      PracticeScoringController.new,
    );

/// 评分对跟练会话的取用缝(测试 override 隔离,见 [PracticeSessionHandle])。
final practiceScoringHandleProvider = Provider<PracticeSessionHandle>(
  (ref) => ref.watch(playPracticeProvider.notifier),
);

/// 一条 onset 的拍域记录:拍位 + 检出时的拍周期(判定折秒用)+
/// 引擎秒(Chroma 取窗与重听定位用)。
final class _OnsetRec {
  const _OnsetRec(this.beat, this.periodMs, this.engineSec);

  final double beat;
  final double periodMs;
  final double engineSec;
}

/// 跟练评分控制器(工单 33):麦听取实际弹奏 → OnsetDetector 检 onset
/// (到达即打引擎钟戳,ADR-0005)→ 会话结束后对时间轴每个扫弦点判定
/// ✓/早/晚/漏/错,出全曲报告。看完即弃,不落库。
///
/// - **校准**:预备数拍期间用户照常扫四下,匹配上的预备拍误差取中位数
///   即链路偏移;采不到退回持久化值(GLOSSARY「延迟校准」)。
/// - **「错」**:命中点取 onset 后音频窗做 Chroma 封闭验证(目标是否
///   最佳匹配且过阈值);色度按 onset 惰性缓存,报告滑块重算零重付。
/// - **范围语义**:每遍(预备+正曲)独立,[onPassStart] 清零——循环
///   重开清零、报告只反映最后一遍;暂停挂起;退出弃评([abort])。
/// - **拍域**:onset 以拍记(自调度锚点),变速换周期只动秒域映射,
///   判定误差按各 onset 检出时的周期折秒(拍数守恒,变速照评)。
class PracticeScoringController extends Notifier<PracticeScoringState> {
  StreamSubscription<Uint8List>? _sub;
  TunerRecorder? _recorder;
  OnsetDetector? _detector;
  MicAudioBuffer _buffer = MicAudioBuffer();
  final _onsets = <_OnsetRec>[];

  // 当前遍的期望点(拍域)、时间轴、锚点秒与周期;onPassStart 时由会话
  // 柄取定。时间轴缓存自取:曲末/停止时跟练控制器先清时间轴,报告组装
  // 仍要谱面信息(小节/槽位/行归属)。
  List<ScoringTarget> _strumTargets = const [];
  List<ScoringTarget> _prepTargets = const [];
  PlayTimeline? _passTimeline;
  double _passAnchorSec = 0;
  double _passPeriodMs = 750;

  // 报告期缓存:per-onset Chroma 最佳匹配(惰性算一次,滑块重算零重付);
  // 封闭集验证器(会话和弦表派生,每遍一建);重听定位时间;当前重听
  // 音源(新听旧卸)。
  final Map<int, ChromaBestMatch?> _chromaCache = {};
  ChromaMatcher? _matcher;
  List<({double? onsetSec, double expectedSec})> _replayTimes = const [];
  double _reportLatencySec = defaultLatencySec;
  EngineSound? _replaySound;
  int _replayGen = 0;

  PracticeSessionHandle get _handle => ref.read(practiceScoringHandleProvider);

  /// 判定用谱面和弦 → 发声音高类(0..11)的封闭集。主指法即用户照图
  /// 按的那一个;音高类从发声基频换算(midi 字段缺位同样可算)。
  Map<String, List<int>> get _midiByChord => {
    for (final entry in _handle.chords.entries)
      if (entry.value.fingerings.isNotEmpty)
        entry.key: [
          for (final freq in entry.value.primaryFingering.stringFrequencies)
            if (freq != null)
              ((69 + 12 * math.log(freq / 440) / math.ln2).round() % 12 + 12) %
                  12,
        ],
  };

  @override
  PracticeScoringState build() {
    ref.onDispose(_teardown);
    return const PracticeScoringState();
  }

  /// 空闲面板开关。会话中不可切(页面只在空闲面板露开关,这里再兜)。
  void setEnabled(bool value) {
    if (state.status != ScoringStatus.idle) return;
    state = state.copyWith(enabled: value, error: null);
  }

  /// 起评分会话:权限 → 开麦 → 复位 → listening,并给跟练会话接上
  /// 评分嘀声。返回 false = 开不了(权限拒/开麦失败),跟练照常开始
  /// 不评分(错误文案在 [PracticeScoringState.error])。
  Future<bool> startSession() async {
    if (!state.enabled || state.status != ScoringStatus.idle) return false;
    final recorder = ref.read(tunerRecorderProvider);
    final granted = await recorder.hasPermission(request: true);
    if (!ref.mounted) return false;
    if (!granted) {
      state = state.copyWith(error: '需要麦克风权限才能跟练评分');
      return false;
    }
    _detector ??= OnsetDetector(sampleRate: micSampleRate);
    _detector!.reset();
    _discardPassData();
    Stream<Uint8List> stream;
    try {
      stream = await recorder.startStream();
    } on Object catch (error) {
      if (!ref.mounted) return false;
      state = state.copyWith(error: '开麦失败,本轮不评分:$error');
      return false;
    }
    _recorder = recorder;
    await _sub?.cancel();
    _sub = stream.listen(
      _onPcmChunk,
      onError: (Object error) => _fail('麦克风出错,评分已停:$error'),
    );
    _handle.setScoringTicks(true);
    if (!ref.mounted) return false;
    state = state.copyWith(status: ScoringStatus.listening, error: null);
    return true;
  }

  /// 新一遍开始(首次开始/循环重启/回到开头):清本遍数据,取定期望点。
  void onPassStart() {
    if (state.status != ScoringStatus.listening) return;
    final timeline = _handle.timeline;
    final anchor = _handle.scheduleAnchor;
    if (timeline == null || anchor == null) return;
    _strumTargets = [
      for (final s in timeline.strums)
        ScoringTarget(
          s.scheduleBeat(PlayPracticeController.prepBeats),
          chord: s.chord,
        ),
    ];
    _prepTargets = [
      for (var k = 0; k < PlayPracticeController.prepBeats; k++)
        ScoringTarget(k.toDouble()),
    ];
    _passAnchorSec = anchor.inMicroseconds / 1e6;
    _passPeriodMs = _handle.periodMs;
    _passTimeline = timeline;
    _onsets.clear();
    _buffer = MicAudioBuffer();
    _chromaCache.clear();
  }

  /// 暂停挂起:采集照跑,onset 不收(锚点冻结期的拍域换算会错位)。
  void onPause() {
    if (state.status == ScoringStatus.listening) {
      state = state.copyWith(suspended: true);
    }
  }

  /// 继续恢复(时间轴已重锚,后续 onset 按新锚点换算)。
  void onResume() {
    if (state.status == ScoringStatus.listening) {
      state = state.copyWith(suspended: false);
    }
  }

  /// 会话结束(曲末/停止):停麦、算报告、拆评分接线。没有可评的数据
  /// (一开播就停)不弹报告直接回 idle——与 demo 同语义。
  void finishSession() {
    if (state.status != ScoringStatus.listening) return;
    _reportLatencySec = _calibratedLatency();
    _replayTimes = _buildReplayTimes();
    final report = _buildReport(_reportLatencySec);
    // 停麦 fire-and-forget:fake zone 里 cancel/close 的 Future 不被 pump
    // 驱动(记忆 stream-cancel-fake-zone-undriven),await 它会让报告
    // 永远不来。状态先行落地,麦的善后不拦报告。
    unawaited(_stopMic());
    if (!ref.mounted) return; // 容器已随应用退出:评分接线与状态无可落盘。
    _handle.setScoringTicks(false);
    if (_strumTargets.isEmpty || _onsets.isEmpty) {
      state = state.copyWith(status: ScoringStatus.idle, suspended: false);
      return;
    }
    state = state.copyWith(
      status: ScoringStatus.finished,
      suspended: false,
      report: report,
      reportLatencySec: _reportLatencySec,
    );
  }

  /// 弃评(退出跟练页):停麦、清数据、拆接线,无报告。
  void abort() {
    // 弃评先行落状态(停麦 fire-and-forget,同 finishSession 的 fake zone
    // 纪律);容器已死则一切善后无意义。
    unawaited(_stopMic());
    if (!ref.mounted) return; // 容器已随应用退出(测试即页弹):无善后可做。
    _handle.setScoringTicks(false);
    _discardPassData();
    state = state.copyWith(
      status: ScoringStatus.idle,
      suspended: false,
      report: null,
      reportLatencySec: null,
      error: null,
    );
  }

  /// 看完报告关闭(弃):回 idle,开关保留(用户可再开一轮)。
  void closeReport() {
    if (state.status != ScoringStatus.finished) return;
    _unloadReplaySound();
    _discardPassData();
    state = state.copyWith(
      status: ScoringStatus.idle,
      report: null,
      reportLatencySec: null,
    );
  }

  /// 报告延迟滑块(±200ms、10ms 一档):实时重算,不落库(落库走
  /// [saveReportLatency])。Chroma 缓存按 onset 记,重算零重付。
  void setReportLatencySec(double latencySec) {
    if (state.status != ScoringStatus.finished || state.report == null) return;
    _reportLatencySec = latencySec;
    // 重听定位随重算:延迟变了配对就变,新配上的点要听它的实际检出位。
    _replayTimes = _buildReplayTimes();
    state = state.copyWith(
      report: _buildReport(latencySec),
      reportLatencySec: latencySec,
    );
  }

  /// 保存报告当前滑块值(跨会话生效,GLOSSARY「延迟校准」)。
  Future<void> saveReportLatency() async {
    await ref
        .read(settingsProvider.notifier)
        .setScoringLatencyMs((_reportLatencySec * 1000).round());
  }

  /// 点格重听该声:命中点听它的检出窗,漏点听期望位置上下文。
  /// 一次性音源:上一条新听即卸(AudioEngine.unload)。
  Future<void> replay(int spotIndex) async {
    if (state.status != ScoringStatus.finished) return;
    if (spotIndex < 0 || spotIndex >= _replayTimes.length) return;
    final times = _replayTimes[spotIndex];
    final at = times.onsetSec ?? times.expectedSec;
    final wav = _buffer.wavSnippet(startSec: at - 0.5, endSec: at + 1.0);
    if (wav == null) return;
    try {
      final engine = ref.read(audioEngineProvider);
      final sound = await engine.loadMem('scoring-replay-${_replayGen++}', wav);
      if (!ref.mounted) {
        await engine.unload(sound);
        return;
      }
      _unloadReplaySound();
      _replaySound = sound;
      engine.playClocked(
        sound,
        engine.engineTime() + const Duration(milliseconds: 50),
      );
    } on Object {
      // 重听失败静默(善后动作,不打断看报告)。
    }
  }

  // ── 内部 ──────────────────────────────────────────────────────────

  /// 麦 chunk 到达:引擎钟打戳(ADR-0005)→ 存音频 → 检 onset(拍域)。
  /// 挂起期音频照存(重听上下文完整),onset 不收。
  void _onPcmChunk(Uint8List bytes) {
    if (state.status != ScoringStatus.listening) return;
    final detector = _detector;
    if (detector == null) return;
    final arrivalSec =
        ref.read(audioEngineProvider).engineTime().inMicroseconds / 1e6;
    final samples = _pcm16ToFloat64(bytes);
    _buffer.append(samples, arrivalSec);
    if (state.suspended) return;
    final anchor = _handle.scheduleAnchor;
    final timeline = _handle.timeline;
    if (anchor == null || timeline == null) return;
    final t0Sec = anchor.inMicroseconds / 1e6;
    final periodMs = _handle.periodMs;
    for (final t in detector.process(samples, arrivalSec)) {
      _onsets.add(_OnsetRec((t - t0Sec) * 1000 / periodMs, periodMs, t));
    }
  }

  Float64List _pcm16ToFloat64(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final n = bytes.lengthInBytes ~/ 2;
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  /// onset 记录 → 评分输入(拍位+检出周期;三处评分共用一份视图)。
  List<ScoredOnset> get _scoredOnsets => [
    for (final o in _onsets) ScoredOnset(o.beat, o.periodMs),
  ];

  /// 链路延迟:预备四下的 matched 误差中位数;采不到回退持久化值。
  /// 全 onset 参与配对比 worry 无虞:正曲首拍距预备末拍恒 1 拍,产品域
  /// 内 1 拍 ≥288ms(208BPM)> 容差 180ms,正曲 onset 进不了预备配对。
  double _calibratedLatency() {
    final pairs = matchPairs(
      targets: _prepTargets,
      onsets: _scoredOnsets,
      toleranceSec: strumToleranceSec,
    );
    return calibrateLatencySec(pairs) ?? _persistedLatencySec();
  }

  double _persistedLatencySec() => ref.read(scoringLatencyMsProvider) / 1000.0;

  /// 报告计算(评分 + 组装)。verifier 走 per-onset 惰性色度缓存;
  /// 和弦表为空(库未就绪)时整体不判错。
  ScoringReport _buildReport(double latencySec) {
    final result = scoreStrums(
      targets: _strumTargets,
      onsets: _scoredOnsets,
      latencySec: latencySec,
      toleranceSec: strumToleranceSec,
      onTimeWindowSec: strumOnTimeWindowSec,
      verifyChord: _midiByChord.isEmpty ? null : _verifyChord,
    );
    final timeline = _passTimeline;
    if (timeline == null) {
      // onPassStart 未走过(防御;正常流不可达):统计带出去,轨道留空壳。
      return ScoringReport(result: result, spots: const []);
    }
    return buildReport(timeline: timeline, result: result);
  }

  bool _verifyChord(int onsetIndex, String chord) {
    final matcher = _matcher ??= _buildMatcher();
    if (matcher == null) return false;
    final best = _chromaCache.putIfAbsent(
      onsetIndex,
      () => _chromaBest(matcher, onsetIndex),
    );
    if (best == null) return true; // 色度无证据(全零窗)不算错,时机判定为准。
    return best.label == chord && best.score > chromaMatchThreshold;
  }

  /// 会话封闭集验证器(和弦表每遍定一份);和弦表空(库未就绪)返回
  /// null,验证整体跳过。
  ChromaMatcher? _buildMatcher() =>
      _midiByChord.isEmpty ? null : ChromaMatcher(midiByChord: _midiByChord);

  /// onset 处的色度最佳匹配:窗 = [检出时刻−20ms, +min(300ms, 距下一
  /// onset 间隙−10ms))(300ms 上限是 glm 余音冷却先例;−20ms 兜检测器
  /// 帧中心 ±10ms 抖动;间隙下限 120ms 保住最短可用窗)。
  ChromaBestMatch? _chromaBest(ChromaMatcher matcher, int onsetIndex) {
    final onset = _onsets[onsetIndex];
    final nextGap = onsetIndex + 1 < _onsets.length
        ? _onsets[onsetIndex + 1].engineSec - onset.engineSec
        : 0.3;
    final end = onset.engineSec + math.min(0.3, math.max(nextGap - 0.01, 0.12));
    final samples = _buffer.window(onset.engineSec - 0.02, end);
    if (samples.isEmpty) return null;
    return matcher.bestMatch(
      chromaFromSamples(samples, sampleRate: micSampleRate),
    );
  }

  /// 重听定位:命中点用检出时刻,漏点用期望时刻(锚点+拍×当前遍周期;
  /// 变速后期望定位有毫米级近似,重听上下文足够)。
  List<({double? onsetSec, double expectedSec})> _buildReplayTimes() {
    final pairs = matchPairs(
      targets: _strumTargets,
      onsets: _scoredOnsets,
      toleranceSec: strumToleranceSec,
      latencySec: _reportLatencySec,
    );
    final onsetByTarget = {for (final (ti, oi, _) in pairs) ti: oi};
    return [
      for (var i = 0; i < _strumTargets.length; i++)
        (
          onsetSec: onsetByTarget.containsKey(i)
              ? _onsets[onsetByTarget[i]!].engineSec
              : null,
          expectedSec:
              _passAnchorSec + _strumTargets[i].beat * _passPeriodMs / 1000,
        ),
    ];
  }

  Future<void> _stopMic() async {
    await _sub?.cancel();
    _sub = null;
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      try {
        await recorder.stop();
      } on Object {
        // 停麦失败不拦收尾。
      }
    }
  }

  void _discardPassData() {
    _strumTargets = const [];
    _prepTargets = const [];
    _passTimeline = null;
    _onsets.clear();
    _buffer = MicAudioBuffer();
    _chromaCache.clear();
    _matcher = null;
    _replayTimes = const [];
  }

  void _unloadReplaySound() {
    final sound = _replaySound;
    _replaySound = null;
    if (sound != null && ref.mounted) {
      unawaited(ref.read(audioEngineProvider).unload(sound));
    }
  }

  /// 麦流错误:停掉会话,评分侧自灭(不弹报告),跟练照常。
  void _fail(String message) {
    unawaited(_stopMic());
    if (!ref.mounted) return;
    _handle.setScoringTicks(false);
    _discardPassData();
    state = state.copyWith(
      status: ScoringStatus.idle,
      suspended: false,
      report: null,
      error: message,
    );
  }

  /// 容器释放:引擎侧资源随容器走,这里只保证麦订阅不漏。
  void _teardown() {
    unawaited(_stopMic());
  }
}
