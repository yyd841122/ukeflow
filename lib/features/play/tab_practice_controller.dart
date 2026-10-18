import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/beat_scheduler.dart';
import '../../core/audio/providers.dart';
import '../../core/audio/tick_sounds.dart';
import '../../core/model/tab_chart.dart';
import '../../core/practice/practice_state.dart';
import '../../core/practice/tab_timeline.dart';
import 'tab_note_scheduler.dart';

/// 指弹跟练页状态(GLOSSARY「跟练」)。
class TabSessionState {
  const TabSessionState({
    required this.bpm,
    required this.speed,
    required this.engineReady,
    required this.running,
    required this.paused,
    this.loop = false,
    this.pass = 1,
    this.error,
  });

  factory TabSessionState.initial() => const TabSessionState(
    bpm: TabPracticeController.defaultBpm,
    speed: 1.0,
    engineReady: false,
    running: false,
    paused: false,
    loop: false,
    pass: 1,
  );

  /// 当前 BPM(进谱默认取谱面 tempo,页内可调;运行中固定)。
  final int bpm;

  /// 变速比(原速的百分比,50%–100%;运行中可即时重编译,与弹唱跟练同)。
  final double speed;
  final bool engineReady;

  /// 会话进行中(含预备数拍与暂停)。曲末/停止后 false。
  final bool running;

  /// 暂停中:引擎侧调度已停、视觉时钟冻结在暂停时刻([running] 仍 true)。
  final bool paused;

  /// 引擎错误文案(初始化失败/运行中引擎异常);null = 正常。
  final String? error;

  /// 单曲循环:开则遍末自动接下一遍(预备数拍即遍间停顿)。会话级开关,
  /// start 复位,遍中可切;passEnd 重启时由控制器显式续上。
  final bool loop;

  /// 当前遍数(第 N 遍,循环开启时随 passEnd 递增;start/回到开头复位 1)。
  final int pass;

  TabSessionState copyWith({
    int? bpm,
    double? speed,
    bool? engineReady,
    bool? running,
    bool? paused,
    bool? loop,
    int? pass,
    Object? error = _sentinel,
  }) => TabSessionState(
    bpm: bpm ?? this.bpm,
    speed: speed ?? this.speed,
    engineReady: engineReady ?? this.engineReady,
    running: running ?? this.running,
    paused: paused ?? this.paused,
    loop: loop ?? this.loop,
    pass: pass ?? this.pass,
    error: identical(error, _sentinel) ? this.error : error as String?,
  );

  static const _sentinel = Object();
}

final tabPracticeProvider =
    NotifierProvider<TabPracticeController, TabSessionState>(
      TabPracticeController.new,
    );

/// 指弹跟练控制器:内置指弹谱 → 按当前 BPM+变速编译逐音事件时间轴 →
/// 预备数拍有界调度 + 正曲逐音示范声(TabNoteScheduler)。
///
/// 与弹唱跟练控制器(PlayPracticeController)同构、不同事件族(ADR-0003):
/// 会话结构、锚点纪律、变速/暂停恢复的引擎侧机制全部同型——预备数拍 =
/// 节拍网格前 4 拍(专用音源,曲头锚点 = 调度 t0 + 预备跨度);暂停 =
/// 停调度器冻结已逝拍数,继续按冻结拍数重锚重建(已响拍/音绝不重放);
/// 变速 = 重编译时间轴 + 调度器换拍周期 + 逐音调度器按新锚点重建。
/// 差别:无节奏型、无参考音切换——**KS 逐音示范声就是参考声**(与高亮
/// 出自同一份时间轴、同一曲头锚,同刻是结构保证),正曲拍静默,预备数拍
/// 恒响。
class TabPracticeController extends Notifier<TabSessionState> {
  static const minBpm = 40;
  static const maxBpm = 208;

  /// 无谱面 tempo 时的缺省速度(与弹唱跟练同源,慢练起步)。
  static const defaultBpm = 80;

  /// 预备数拍拍数(与弹唱跟练一致:4 拍倒计)。
  static const prepBeats = 4;

  /// 变速范围(原速的 50%–100%)。
  static const minSpeed = 0.5;
  static const maxSpeed = 1.0;

  EngineSound? _count;
  BeatScheduler? _scheduler;
  TabNoteScheduler? _noteScheduler;
  TabTimeline? _timeline;

  /// 会话锚点与参数:调度 t0(预备第 0 拍)、拍周期、当前谱。
  Duration _t0 = Duration.zero;
  double _periodMs = 0;
  double _elapsedBeatsAtPause = 0;
  TabChart? _chart;

  /// 运行中的逐音事件时间轴;未运行 null。
  TabTimeline? get timeline => _timeline;

  /// 视觉层锚点:**曲头**时刻(预备数拍之后)与拍周期;未运行 null。
  ({Duration t0, double periodMs})? get visualAnchor {
    if (_timeline == null || !state.running) return null;
    return (t0: _t0 + _prepSpan, periodMs: _periodMs);
  }

  /// 视觉时钟:运行中 = 引擎当前时刻;暂停 = 冻结的暂停时刻(变速后按
  /// 拍数守恒自动换算);未运行 null。
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

  /// 预备数拍查询(预备期有效):锚在调度 t0(预备第 0 拍,无取整),
  /// 与节拍网格同刻;未运行/非预备期返回 null。与弹唱跟练共用
  /// prepStateAt 纯函数(预备数拍是两谱共用的练习体验)。
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
  TabSessionState build() {
    ref.onDispose(_teardown);
    return TabSessionState.initial();
  }

  /// 引擎预热 + 注入预备拍音源(+已登记谱面的全曲拨弦音源);失败进
  /// error 状态。并发调用共享同一次在途初始化(SingleFlight,快速重进页
  /// 不重复注入)。
  Future<void> warmup() async {
    if (state.engineReady) {
      // 运行时错误后的重试(页上重试钮同一入口):引擎仍就绪,清陈错即
      // 恢复可用,真正重跑走 start(审计 2026-10-16 #33 同型)。
      if (state.error != null) state = state.copyWith(error: null);
      return;
    }
    return _warmups.run(_doWarmup);
  }

  final SingleFlight _warmups = SingleFlight();

  Future<void> _doWarmup() async {
    try {
      final engine = ref.read(audioEngineProvider);
      await engine.ensureInitialized();
      if (!ref.mounted) return; // 容器已随应用退出:状态无可落盘。
      _count =
          (await TickSounds.load(engine, count: true)).count;
      // 拨弦音源注入失败只降级(示范声静默、高亮照走),不进 error 状态。
      await _ensurePluckSounds();
      if (!ref.mounted) return;
      // error: null——上次初始化失败的文案不残留到成功之后。
      state = state.copyWith(engineReady: true, error: null);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(error: '引擎初始化失败:$error');
    }
  }

  /// 进谱定参:取谱面 tempo 为当前 BPM(钳制 40–208)、变速回原速,并
  /// 预备全曲拨弦音源。只应在进页时调;运行中是空操作(页内重启不清已
  /// 调好的参数——变速归零是例外:每首谱都从原速起)。
  void prepareFor(TabChart chart) {
    if (state.running) return;
    _chart = chart;
    state = state.copyWith(bpm: chart.tempo.clamp(minBpm, maxBpm), speed: 1.0);
    _ensurePluckSounds();
  }

  /// 预注入当前谱全曲音高的拨弦音源(示范声调度是同步路径,免 await)。
  /// 失败静默降级;**按谱键控**——换谱后各注入各的,PluckPlayer 缓存
  /// 按音源键去重兜底(旧「在途合并」会把换谱后的预载落在旧谱上,新谱
  /// 音源静默缺失,审计 2026-10-16 #40)。
  Future<void> _ensurePluckSounds() {
    final chart = _chart;
    if (chart == null) return Future.value();
    return _preloadPluckSounds(chart);
  }

  Future<void> _preloadPluckSounds(TabChart chart) async {
    try {
      await ref
          .read(pluckPlayerProvider)
          .preloadSounds(chart.notes.map((n) => n.frequency).toSet());
    } on Object {
      // 静默降级:引擎异常时示范声无声,高亮照走。
    }
  }

  /// 设 BPM(钳制 40–208)。仅空闲生效:运行中固定速度。
  void setBpm(int bpm) {
    if (state.running) return;
    state = state.copyWith(bpm: bpm.clamp(minBpm, maxBpm));
  }

  /// 设变速比(钳制 50%–100%)。空闲仅记参;运行中即时重编译+重锚,
  /// 暂停中按拍数守恒换算冻结位置(与弹唱跟练同:变速即时生效)。
  void setSpeed(double speed) {
    final s = speed.clamp(minSpeed, maxSpeed);
    if (s == state.speed) return;
    final chart = _chart;
    TabTimeline? newTimeline;
    if (state.running && chart != null) {
      newTimeline = compileTabTimeline(
        chart: chart,
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
    // 本地持有再变速:changePeriod 尾过窗若同步报错,onError→stop 会清
    // _scheduler——此时错误状态已落地,不得再回读锚点(空断言崩,
    // 审计 2026-10-16 #41)。
    final scheduler = _scheduler!;
    scheduler.changePeriod(newTimeline.periodMs);
    if (_scheduler != scheduler) return; // 变速首过即抛:错误状态已落地。
    _adoptSchedulerAnchor();
    _timeline = newTimeline;
    _restartNoteScheduler(continuing: true);
  }

  /// 开始跟练:编译时间轴,预备数拍起跑(调度 totalBeats = 预备+曲拍数,
  /// 曲末无幻拍声)+逐音示范声按曲头锚预定。未就绪或已在跑则拒绝。
  void start({required TabChart chart}) {
    if (!state.engineReady || state.running) return;
    _chart = chart; // 会话参数登记(变速重编译/restart 的依据)
    _ensurePluckSounds(); // 直进(未走 prepareFor)也补注入;缓存兜底
    final timeline = compileTabTimeline(
      chart: chart,
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
    // 新会话:循环与遍数复位(passEnd 重启后由控制器显式续上)。
    state = state.copyWith(
      running: true,
      paused: false,
      error: null,
      loop: false,
      pass: 1,
    );
    _restartNoteScheduler();
  }

  /// 单曲循环开关(遍中可切,对当前遍无感,自下一遍起效;空闲无效)。
  void toggleLoop() {
    if (!state.running) return;
    state = state.copyWith(loop: !state.loop);
  }

  /// 曲末(节拍网格走出最后一拍,页面轮询判得):循环开→干净重启接下一遍
  /// (预备数拍即遍间停顿,遍数+1;循环由这里显式续上——start 复位它);
  /// 关→回闲。暂停中视觉时钟冻结,轮询到不了曲末,此守卫只是双保险。
  void passEnd() {
    if (!state.running || state.paused) return;
    if (!state.loop) {
      stop();
      return;
    }
    final chart = _chart;
    if (chart == null || !state.engineReady) {
      stop();
      return;
    }
    final wasLoop = state.loop;
    final next = state.pass + 1;
    stop();
    start(chart: chart);
    if (state.running) state = state.copyWith(loop: wasLoop, pass: next);
  }

  /// 回读调度器锚点(t0 的唯一来源:启动/重锚后各一次,保证与声同一刻)。
  void _adoptSchedulerAnchor() {
    final anchor = _scheduler!.anchor!;
    _t0 = anchor.t0;
    _periodMs = anchor.periodMs;
  }

  /// 暂停:引擎侧机制——停掉两个调度器(未响拍/音全停),冻结已逝拍数;
  /// 时间轴与锚点保留,视觉时钟随之冻结。
  void pause() {
    if (!state.running || state.paused) return;
    final scheduler = _scheduler;
    if (scheduler == null) return;
    final now = ref.read(audioEngineProvider).engineTime();
    _elapsedBeatsAtPause = (now - _t0).inMicroseconds / (_periodMs * 1000);
    _noteScheduler?.stop();
    _noteScheduler = null;
    scheduler.stop();
    state = state.copyWith(paused: true);
  }

  /// 继续:以引擎当前时刻按冻结拍数重锚 t0,重建调度器(相位保持)。
  /// nextBeat = ceil(已逝拍数)——已响拍绝不重放;逐音示范声按重锚曲头
  /// 重建,恢复窗前的音按「已随暂停消逝」处理。
  void resume() {
    if (!state.running || !state.paused) return;
    final timeline = _timeline;
    if (timeline == null) return;
    final engine = ref.read(audioEngineProvider);
    final t0 =
        engine.engineTime() -
        Duration(milliseconds: (_elapsedBeatsAtPause * _periodMs).round());
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
    _restartNoteScheduler(continuing: true); // 暂停前已响音不重放。
    state = state.copyWith(paused: false);
  }

  /// 回到开头:干净复位后重新开始(含预备数拍)。仅会话中有效。
  void restart() {
    final chart = _chart;
    if (chart == null || !state.running || !state.engineReady) return;
    stop();
    start(chart: chart);
  }

  /// 停止:取消轮询调度、停掉尚未发声的预定、时间轴清空、退出会话。
  void stop() {
    // 引擎侧停止不依赖 ref:容器已销毁(应用退出竞态)也照停。
    _noteScheduler?.stop();
    _noteScheduler = null;
    _scheduler?.stop();
    _scheduler = null;
    _timeline = null;
    if (!ref.mounted) return; // 容器已随应用退出:状态无可落盘。
    if (state.running) {
      state = state.copyWith(running: false, paused: false);
    }
  }

  /// 重建逐音示范声调度器(启动/恢复/变速的统一入口):以**曲头锚**
  /// (_t0 + 预备跨度,与 [visualAnchor] 同一刻)起跑——时间轴音事件时刻
  /// 是曲头相对量,锚在预备拍 0 会让整曲提前一个预备跨度响;锚点前过期
  /// 事件越过不回放。[continuing] 标记会话进行中的重建(恢复/变速):
  /// 此刻前的音已由旧调度器消费,传入已消费截止线,迟到容差窗内已响音
  /// 不重放(审计 2026-10-16 #42)。
  void _restartNoteScheduler({bool continuing = false}) {
    final old = _noteScheduler;
    _noteScheduler = null;
    old?.stop();
    final timeline = _timeline;
    if (timeline == null) return;
    final scheduler = TabNoteScheduler(
      engine: ref.read(audioEngineProvider),
      notes: timeline.notes,
      pickSound: _pickPluck,
      onError: _onEngineError,
    );
    _noteScheduler = scheduler;
    scheduler.start(
      t0: _t0 + _prepSpan,
      consumedUntil:
          continuing ? ref.read(audioEngineProvider).engineTime() : null,
    );
    if (_noteScheduler != scheduler) _noteScheduler = null;
  }

  /// 节拍声选音:预备拍恒用预备音源(数拍不是参考音,指弹跟练一样先
  /// 数拍);正曲拍恒静默(逐音示范声接管)。返回 null 表示该拍静默。
  EngineSound? _pick(int beat) => beat < prepBeats ? _count : null;

  /// 单音定声:按音高查预注入的 KS 音源;未就绪返回 null(该音静默
  /// 越过,高亮照走——预注入失败的降级路径)。
  EngineSound? _pickPluck(TabNoteEvent note) =>
      ref.read(pluckPlayerProvider).loadedSound(note.frequency);

  void _onEngineError(Object error) {
    stop();
    state = state.copyWith(running: false, error: '引擎出错,跟练已停止:$error');
  }

  void _teardown() {
    _noteScheduler?.stop();
    _noteScheduler = null;
    _scheduler?.stop();
    _scheduler = null;
    _timeline = null;
  }
}
