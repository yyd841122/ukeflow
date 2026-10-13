import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/beat_scheduling.dart';
import '../../core/audio/beat_scheduler.dart';
import '../../core/audio/providers.dart';
import '../../core/audio/tick_synth.dart';
import '../../core/model/builtin_strum_patterns.dart';
import '../../core/model/strum_chart.dart';
import '../../core/model/strum_pattern.dart';
import '../../core/practice/play_timeline.dart';
import '../../core/practice/practice_state.dart';
import '../../data/chord_library.dart' show Chord;
import 'strum_scheduler.dart';

/// 跟练参考音(工单 10,用户故事 24「先跟拍、后脱拍」)。
enum ReferenceSound {
  /// 节拍声:4/4 强弱拍 tick。
  beat,

  /// 示范扫弦声:按时间轴扫弦事件拨响和弦(节拍网格照走,正曲拍静默)。
  strum,
}

/// 跟练页状态（GLOSSARY「跟练」）。
class PlayPracticeState {
  const PlayPracticeState({
    required this.bpm,
    required this.speed,
    required this.pattern,
    required this.engineReady,
    required this.running,
    required this.paused,
    required this.reference,
    this.error,
  });

  factory PlayPracticeState.initial() => PlayPracticeState(
    bpm: PlayPracticeController.defaultBpm,
    speed: 1.0,
    pattern: builtinStrumPatterns.first,
    engineReady: false,
    running: false,
    paused: false,
    reference: ReferenceSound.beat,
  );

  /// 当前 BPM（进谱默认取谱面 tempo,页内可调;运行中固定）。
  final int bpm;

  /// 变速比（原速的百分比,50%–100%;运行中可即时重编译,工单 10）。
  final double speed;

  /// 节奏型（时间轴编译参数;同一首谱可换型练,运行中固定）。
  final StrumPattern pattern;
  final bool engineReady;

  /// 会话进行中（含预备数拍与暂停）。曲末/停止后 false。
  final bool running;

  /// 暂停中:引擎侧调度已停、视觉时钟冻结在暂停时刻（[running] 仍 true）。
  final bool paused;

  /// 参考音（预备数拍不受它影响,任何模式下都数拍）。
  final ReferenceSound reference;

  /// 引擎错误文案(初始化失败/运行中引擎异常);null = 正常。
  final String? error;

  PlayPracticeState copyWith({
    int? bpm,
    double? speed,
    StrumPattern? pattern,
    bool? engineReady,
    bool? running,
    bool? paused,
    ReferenceSound? reference,
    Object? error = _sentinel,
  }) => PlayPracticeState(
    bpm: bpm ?? this.bpm,
    speed: speed ?? this.speed,
    pattern: pattern ?? this.pattern,
    engineReady: engineReady ?? this.engineReady,
    running: running ?? this.running,
    paused: paused ?? this.paused,
    reference: reference ?? this.reference,
    error: identical(error, _sentinel) ? this.error : error as String?,
  );

  static const _sentinel = Object();
}

final playPracticeProvider =
    NotifierProvider<PlayPracticeController, PlayPracticeState>(
      PlayPracticeController.new,
    );

/// 跟练控制器:内置弹唱谱 → 按当前 BPM+节奏型+变速编译时间轴 → 预备数拍
/// +正曲的节拍声有界调度(+可选的示范扫弦声)。
///
/// 音画同源（ADR-0005）在此接线:节拍声走 BeatScheduler→playClocked 管线,
/// 视觉不进调度——UI 轮询经 practiceStateAt 纯函数按 [visualNow] 算出
/// （跟练页负责轮询）。会话结构（工单 10）:
/// - 预备数拍 = 节拍网格的前 [prepBeats] 拍（专用音源,任何参考音模式都
///   响）,曲头锚点 = 调度 t0 + 预备跨度;调度 totalBeats = 预备+曲拍数,
///   曲末无幻拍声;
/// - 暂停 = 引擎侧机制:停调度器、冻结「已逝拍数」;继续 = 以引擎当前
///   时刻按冻结拍数重锚 t0 重建调度器（相位保持）,已响拍绝不重放——
///   恢复无错位是结构保证;
/// - 变速 = 重编译时间轴 + 调度器换拍周期（同一周期值,无双公式分叉）,
///   冻结/进行中的拍位按「拍数守恒」换算。
class PlayPracticeController extends Notifier<PlayPracticeState> {
  static const minBpm = 40;
  static const maxBpm = 208;

  /// 无谱面 tempo 时的缺省速度（与节奏型训练器同源,慢练起步）。
  static const defaultBpm = 80;

  /// 预备数拍拍数（工单 10 验收:4 拍倒计）。
  static const prepBeats = 4;

  /// 变速范围（原速的 50%–100%）。
  static const minSpeed = 0.5;
  static const maxSpeed = 1.0;

  EngineSound? _strong;
  EngineSound? _weak;
  EngineSound? _count;
  BeatScheduler? _scheduler;
  StrumScheduler? _strumScheduler;
  PlayTimeline? _timeline;
  Future<void>? _warming;
  Future<void>? _strumPreloading;

  /// 会话锚点与参数:调度 t0（预备第 0 拍）、拍周期、当前谱与和弦表。
  /// 控制器持有（暂停后调度器已停,锚点仍须可查询）,调度器是 t0 的
  /// 产出源（start/changePeriod 后回读）。
  Duration _t0 = Duration.zero;
  double _periodMs = 0;
  double _elapsedBeatsAtPause = 0;
  ReferenceSound _reference = ReferenceSound.beat;
  StrumChart? _chart;
  Map<String, Chord> _chords = const {};

  /// 运行中的动作事件时间轴;未运行 null。
  PlayTimeline? get timeline => _timeline;

  /// 视觉层锚点:**曲头**时刻（预备数拍之后）与拍周期;未运行 null。
  ({Duration t0, double periodMs})? get visualAnchor {
    if (_timeline == null || !state.running) return null;
    return (t0: _t0 + _prepSpan, periodMs: _periodMs);
  }

  /// 视觉时钟（工单 10）:运行中 = 引擎当前时刻;暂停 = 冻结的暂停时刻
  /// （锚点 + 冻结拍数×当前周期,变速后按拍数守恒自动换算）;未运行 null。
  Duration? visualNow() {
    if (_timeline == null || !state.running) return null;
    if (state.paused) {
      return _t0 +
          Duration(milliseconds: (_elapsedBeatsAtPause * _periodMs).round());
    }
    return ref.read(audioEngineProvider).engineTime();
  }

  Duration get _prepSpan =>
      Duration(milliseconds: (prepBeats * _periodMs).round());

  /// 预备数拍查询（预备期有效）：锚在调度 t0（预备第 0 拍，无取整），
  /// 与节拍网格同刻；未运行/非预备期返回 null。页面轮询经此查询,
  /// 不自持锚点换算（round(prepBeats×period) 的曲头反推剩余拍会出
  /// ±1 拍的取整误差——见 prepStateAt 文档）。
  PrepState? prepStateNow() {
    if (_timeline == null || !state.running) return null;
    return prepStateAt(
      now: visualNow()!,
      t0Prep: _t0,
      periodMs: _periodMs,
      prepBeats: prepBeats,
    );
  }

  @override
  PlayPracticeState build() {
    ref.onDispose(_teardown);
    return PlayPracticeState.initial();
  }

  /// 引擎预热 + 注入强弱拍/预备拍音源(+已定和弦表的扫弦音源);失败进
  /// error 状态,页面上可见。并发调用共享同一次在途初始化(快速重进页
  /// 不重复注入音源)。
  Future<void> warmup() async {
    if (state.engineReady) return;
    return _warming ??= _doWarmup().whenComplete(() => _warming = null);
  }

  Future<void> _doWarmup() async {
    try {
      final engine = ref.read(audioEngineProvider);
      await engine.ensureInitialized();
      if (!ref.mounted) return; // 容器已随应用退出:状态无可落盘。
      final strong = await engine.loadMem('tick_strong', TickSynth.strong());
      final weak = await engine.loadMem('tick_weak', TickSynth.weak());
      final count = await engine.loadMem('tick_count', TickSynth.count());
      if (!ref.mounted) return;
      _strong = strong;
      _weak = weak;
      _count = count;
      // 扫弦音源注入失败只降级(参考音=扫弦时无声),不进 error 状态。
      await _ensureStrumSounds();
      if (!ref.mounted) return;
      // error: null——上次初始化失败的文案不残留到成功之后。
      state = state.copyWith(engineReady: true, error: null);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(error: '引擎初始化失败:$error');
    }
  }

  /// 进谱定参:取谱面 tempo 为当前 BPM（钳制 40–208）、变速回原速;记录
  /// 和弦表并预备扫弦音源。只应在进页时调;运行中是空操作（页内重启不
  /// 清已调好的参数——变速归零是例外:每首谱都从原速起）。
  void prepareFor(StrumChart chart, {Map<String, Chord> chords = const {}}) {
    if (state.running) return;
    _chart = chart;
    final tempo = chart.tempo ?? defaultBpm;
    state = state.copyWith(
      bpm: tempo.clamp(minBpm, maxBpm),
      speed: 1.0,
    );
    setChords(chords);
  }

  /// 更新和弦表（和弦库异步就绪后由页面推入）并预备扫弦音源;运行中
  /// 忽略（本会话扫弦音源已定）。
  void setChords(Map<String, Chord> chords) {
    if (state.running) return;
    _chords = chords;
    _ensureStrumSounds();
  }

  /// 预注入全曲和弦的拨弦音源（参考音=扫弦的调度是同步路径,免 await）。
  /// 失败静默降级;在途合并,重复调用不重注入（PluckPlayer 缓存兜底）。
  Future<void> _ensureStrumSounds() {
    if (_chords.isEmpty) return Future.value();
    return _strumPreloading ??= _preloadStrumSounds().whenComplete(
      () => _strumPreloading = null,
    );
  }

  Future<void> _preloadStrumSounds() async {
    try {
      final freqs = <double>{
        for (final chord in _chords.values)
          ...chord.primaryFingering.stringFrequencies.whereType<double>(),
      };
      await ref.read(pluckPlayerProvider).preloadSounds(freqs);
    } on Object {
      // 静默降级:和弦库缺位/引擎异常时参考音=扫弦无声,页面照跑。
    }
  }

  /// 设 BPM(钳制 40–208)。仅空闲生效:运行中固定速度。
  void setBpm(int bpm) {
    if (state.running) return;
    state = state.copyWith(bpm: bpm.clamp(minBpm, maxBpm));
  }

  /// 设变速比(钳制 50%–100%)。空闲仅记参;运行中即时重编译+重锚,
  /// 暂停中按拍数守恒换算冻结位置（工单 10 验收:变速即时生效）。
  void setSpeed(double speed) {
    final s = speed.clamp(minSpeed, maxSpeed);
    if (s == state.speed) return;
    final chart = _chart;
    PlayTimeline? newTimeline;
    if (state.running && chart != null) {
      newTimeline = compileTimeline(
        chart: chart,
        pattern: state.pattern,
        bpm: state.bpm.toDouble(),
        speed: s,
      );
    }
    state = state.copyWith(speed: s);
    if (newTimeline == null) return; // 空闲:仅记参,进谱/重启时编译
    if (state.paused) {
      // 冻结位置 = 锚点 + 冻结拍数×周期:拍数不变,换周期即守恒换算。
      _timeline = newTimeline;
      _periodMs = newTimeline.periodMs;
      return;
    }
    _scheduler!.changePeriod(newTimeline.periodMs);
    _adoptSchedulerAnchor();
    _timeline = newTimeline;
    _restartStrumScheduler();
  }

  /// 换节奏型。仅空闲生效:节奏型是编译参数,运行中换型=重编译(工单
  /// 10 未放开,变速先行)。
  void setPattern(StrumPattern pattern) {
    if (state.running) return;
    state = state.copyWith(pattern: pattern);
  }

  /// 设参考音。运行中即时接线(节拍声靠 pickSound 读字段,扫弦声靠
  /// 扫弦调度器启停);暂停中仅记参,恢复时按状态接线。
  void setReference(ReferenceSound reference) {
    if (reference == state.reference) return;
    _reference = reference;
    state = state.copyWith(reference: reference);
    if (!state.running || state.paused) return;
    if (reference == ReferenceSound.strum) {
      _restartStrumScheduler();
    } else {
      _strumScheduler?.stop();
      _strumScheduler = null;
    }
  }

  /// 开始跟练:编译时间轴,预备数拍+节拍声与时间轴同源起跑（调度
  /// totalBeats = 预备+曲拍数,曲末无幻拍声）。未就绪或已在跑则拒绝。
  void start({required StrumChart chart, Map<String, Chord> chords = const {}}) {
    if (!state.engineReady || state.running) return;
    _chart = chart; // 会话参数登记(变速重编译/restart 的依据)
    _chords = chords;
    final timeline = compileTimeline(
      chart: chart,
      pattern: state.pattern,
      bpm: state.bpm.toDouble(),
      speed: state.speed,
    );
    final scheduler = BeatScheduler(
      engine: ref.read(audioEngineProvider),
      pickSound: _pick,
      onError: _onEngineError,
    );
    // 先挂字段再起跑:首过即抛时 onError→stop 会当场清掉它们(下方据此识别)。
    _timeline = timeline;
    _scheduler = scheduler;
    scheduler.start(
      periodMs: timeline.periodMs,
      totalBeats: prepBeats + timeline.totalBeats,
    );
    if (_scheduler != scheduler) return; // 首过即抛:错误状态已落地,不宣布运行。
    _adoptSchedulerAnchor();
    state = state.copyWith(running: true, paused: false, error: null);
    _restartStrumScheduler(); // 参考音=扫弦时随会话起跑(空闲预选不丢)
  }

  /// 回读调度器锚点（t0 的唯一来源:启动/重锚后各一次,保证与声同一刻）。
  void _adoptSchedulerAnchor() {
    final anchor = _scheduler!.anchor!;
    _t0 = anchor.t0;
    _periodMs = anchor.periodMs;
  }

  /// 暂停:引擎侧机制——停掉两个调度器(未响拍/弦全停),冻结已逝拍数;
  /// 时间轴与锚点保留,视觉时钟随之冻结。恢复无错位见 [resume]。
  void pause() {
    if (!state.running || state.paused) return;
    final scheduler = _scheduler;
    if (scheduler == null) return;
    final now = ref.read(audioEngineProvider).engineTime();
    _elapsedBeatsAtPause = (now - _t0).inMicroseconds / (_periodMs * 1000);
    _strumScheduler?.stop();
    _strumScheduler = null;
    scheduler.stop();
    state = state.copyWith(paused: true);
  }

  /// 继续:以引擎当前时刻按冻结拍数重锚 t0,重建调度器（相位保持）。
  /// nextBeat = ceil(已逝拍数)——已响拍绝不重放;恰在拍点恢复的拍迟到
  /// 0ms 在调度器迟到容差内,立即补响。扫弦声按参考音状态一并重建。
  void resume() {
    if (!state.running || !state.paused) return;
    final timeline = _timeline;
    if (timeline == null) return;
    final engine = ref.read(audioEngineProvider);
    final t0 = engine.engineTime() -
        Duration(
          milliseconds: (_elapsedBeatsAtPause * _periodMs).round(),
        );
    final nextBeat = _elapsedBeatsAtPause <= 0
        ? 0
        : _elapsedBeatsAtPause.ceil();
    final scheduler = BeatScheduler(
      engine: engine,
      pickSound: _pick,
      onError: _onEngineError,
    );
    _timeline = timeline;
    _scheduler = scheduler;
    scheduler.start(
      periodMs: _periodMs,
      totalBeats: prepBeats + timeline.totalBeats,
      t0: t0,
      nextBeat: nextBeat,
    );
    if (_scheduler != scheduler) return; // 首过即抛:错误状态已落地。
    _t0 = t0;
    _restartStrumScheduler();
    state = state.copyWith(paused: false);
  }

  /// 回到开头:干净复位后重新开始（含预备数拍）。仅会话中有效。
  void restart() {
    final chart = _chart;
    if (chart == null || !state.running || !state.engineReady) return;
    stop();
    start(chart: chart, chords: _chords);
  }

  /// 停止:取消轮询调度、停掉尚未发声的预定、时间轴清空、退出会话。
  void stop() {
    // 引擎侧停止不依赖 ref:容器已销毁(应用退出竞态)也照停。
    _strumScheduler?.stop();
    _strumScheduler = null;
    _scheduler?.stop();
    _scheduler = null;
    _timeline = null;
    if (!ref.mounted) return; // 容器已随应用退出:状态无可落盘。
    if (state.running) {
      state = state.copyWith(running: false, paused: false);
    }
  }

  /// 参考音=扫弦时重建扫弦调度器（启动/恢复/变速/切换的统一入口）:
  /// 以**曲头锚**（_t0 + 预备跨度,与 [visualAnchor] 同一刻）起跑——时间轴
  /// 扫弦事件时刻是曲头相对量,锚在预备拍 0 会让整曲提前一个预备跨度响、
  /// 末小节永不发声;锚点前过期事件越过不回放。
  void _restartStrumScheduler() {
    _strumScheduler?.stop();
    _strumScheduler = null;
    if (_reference != ReferenceSound.strum) return;
    final timeline = _timeline;
    if (timeline == null) return;
    final scheduler = StrumScheduler(
      engine: ref.read(audioEngineProvider),
      strums: timeline.strums,
      pickStrings: _stringSounds,
      onError: _onEngineError,
    );
    _strumScheduler = scheduler;
    scheduler.start(t0: _t0 + _prepSpan);
    if (_strumScheduler != scheduler) _strumScheduler = null;
  }

  /// 和弦名 → 弦音表(4 弦→1 弦序,闷音弦 null 占位)。音源未就绪
  /// （预注入未完成/失败）按闷音处理——无声降级,不打扰练习。
  List<EngineSound?>? _stringSounds(String chordName) {
    final chord = _chords[chordName];
    if (chord == null) return null;
    final player = ref.read(pluckPlayerProvider);
    return [
      for (final freq in chord.primaryFingering.stringFrequencies)
        freq == null ? null : player.loadedSound(freq),
    ];
  }

  /// 节拍声选音:预备拍恒用预备音源（数拍不是参考音,任何模式都响）;
  /// 正曲拍按参考音模式——节拍声给 4/4 强弱,扫弦声模式静默(由扫弦
  /// 调度器接管)。返回 null 表示该拍静默。
  EngineSound? _pick(int beat) {
    if (beat < prepBeats) return _count;
    if (_reference != ReferenceSound.beat) return null;
    return (beat - prepBeats) % beatsPerBar == 0 ? _strong : _weak;
  }

  void _onEngineError(Object error) {
    stop();
    state = state.copyWith(running: false, error: '引擎出错,跟练已停止:$error');
  }

  void _teardown() {
    _strumScheduler?.stop();
    _strumScheduler = null;
    _scheduler?.stop();
    _scheduler = null;
    _timeline = null;
  }
}
