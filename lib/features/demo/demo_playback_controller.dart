import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/pluck_player.dart';
import '../../core/audio/providers.dart';
import '../../core/model/strum_chart.dart';
import '../../core/model/strum_pattern.dart';
import '../../core/practice/play_timeline.dart';
import '../../data/chord_library.dart' show Chord;
import '../play/play_practice_controller.dart';
import '../play/strum_scheduler.dart';
import '../play/strum_voicing.dart';

/// 示范试听状态(GLOSSARY「示范试听」)。
enum DemoPlaybackStatus {
  /// 空闲。
  idle,

  /// 准备中:引擎初始化+全曲扫弦音源注入(发声前的一瞬)。
  preparing,

  /// 发声中:整曲扫弦按时间轴错峰预定。
  playing,
}

/// 示范试听页状态。
class DemoPlaybackState {
  const DemoPlaybackState({this.status = DemoPlaybackStatus.idle, this.error});

  final DemoPlaybackStatus status;

  /// 引擎/准备错误文案(试听已停止);null = 正常。停止后保留,下次
  /// 开试听清空。
  final String? error;
}

final demoPlaybackProvider =
    NotifierProvider<DemoPlaybackController, DemoPlaybackState>(
      DemoPlaybackController.new,
    );

/// 一次试听的参数快照(开始一刻从跟练状态取定,空闲改参不打扰在途)。
typedef _Session = ({
  StrumChart chart,
  StrumPattern pattern,
  double bpm,
  double speed,
});

/// 示范试听控制器(工单 11):弹前点一下,按**所选节奏型+当前 BPM**
/// (进谱参数快照,读自跟练控制器状态)把整曲扫弦经 [StrumScheduler]
/// 预定播放——与跟练参考音同一条时间轴、同一个调度引擎,「示范试听 =
/// 参考音=扫弦的完整曲预览」由此是结构保证而非两套实现的巧合。
///
/// - 结构同步(票面验收):发声事件取自 `compileTimeline` 产物
///   [PlayTimeline.strums],与跟练视觉同源;
/// - 可中途停止([stop] 停掉未响预定)、曲末自动回闲(轮询只当触发器,
///   时刻只读引擎时钟,ADR-0005);
/// - 开始后的变速/换型/改 BPM 不打扰在途试听(参数在开始一刻快照),
/// 再点一次即听到新参数;
/// - 跟练运行中拒绝开试听(两种发声不叠加;页面层还有按钮互斥)。
class DemoPlaybackController extends Notifier<DemoPlaybackState> {
  /// 曲末判定轮询周期:无画面要跟,粗粒度够用(时刻仍只读引擎时钟)。
  static const _endPoll = Duration(milliseconds: 200);

  /// 曲末判定时刻:名义曲长 + 末扫弦的错峰尾(一扫至多 4 弦,末弦在
  /// 事件锚后 3×strumGap 才预定)。曲末轮询不得早于最后一声的预定时刻
  /// 停机,否则末扫的尾弦会被当「未响预定」停掉。产品域(40–208 BPM、
  /// 变速 50%–100%)里名义曲长本就晚于末扫锚至少半拍(≥144ms),加尾后
  /// 是结构保证而非数值巧合——跨 BPM 扫域测试锁定(工单 11 评审修)。
  static Duration endOffset(PlayTimeline timeline) =>
      timeline.totalDuration + PluckPlayer.strumGap * 3;

  StrumScheduler? _scheduler;
  PlayTimeline? _timeline;
  StrumVoicer? _voicer;
  Duration _t0 = Duration.zero;
  Timer? _endWatch;

  @override
  DemoPlaybackState build() {
    ref.onDispose(_teardown);
    return const DemoPlaybackState();
  }

  /// 开试听:同步进 preparing 防双击双跑;跟练运行中拒绝。参数(BPM/
  /// 变速/节奏型)在调用一刻从跟练状态快照。
  void start({required StrumChart chart, required Map<String, Chord> chords}) {
    if (state.status != DemoPlaybackStatus.idle) return;
    final practice = ref.read(playPracticeProvider);
    if (practice.running) return;
    _voicer = StrumVoicer(
      chords: chords,
      player: ref.read(pluckPlayerProvider),
    );
    state = const DemoPlaybackState(status: DemoPlaybackStatus.preparing);
    _run((
      chart: chart,
      pattern: practice.pattern,
      bpm: practice.bpm.toDouble(),
      speed: practice.speed,
    ));
  }

  /// 停止:停掉未响预定、曲末轮询取消,回 idle(错误文案保留)。
  /// 引擎侧停止不依赖 ref(容器已销毁也照停);状态落盘前查 mounted
  /// (与跟练控制器 stop 同纪律)。
  void stop() {
    _discardSession();
    if (!ref.mounted) return;
    if (state.status != DemoPlaybackStatus.idle) {
      state = DemoPlaybackState(
        status: DemoPlaybackStatus.idle,
        error: state.error,
      );
    }
  }

  /// 引擎侧复位(不碰状态写入):曲末轮询取消、未响预定停掉、时间轴清空。
  void _discardSession() {
    _endWatch?.cancel();
    _endWatch = null;
    _scheduler?.stop();
    _scheduler = null;
    _timeline = null;
  }

  /// 一次试听的参数快照。
  Future<void> _run(_Session session) async {
    final engine = ref.read(audioEngineProvider);
    try {
      await engine.ensureInitialized();
      await _voicer!.preload();
    } on Object catch (error) {
      _failPreparing('试听准备失败:$error');
      return;
    }
    if (!ref.mounted || state.status != DemoPlaybackStatus.preparing) {
      return; // 途中被停/容器已退:不开声。
    }
    final timeline = compileTimeline(
      chart: session.chart,
      pattern: session.pattern,
      bpm: session.bpm,
      speed: session.speed,
    );
    final scheduler = StrumScheduler(
      engine: engine,
      strums: timeline.strums,
      pickStrings: _voicer!.voice,
      onError: _onEngineError,
    );
    _timeline = timeline;
    _scheduler = scheduler;
    _t0 = engine.engineTime();
    scheduler.start(t0: _t0);
    if (_scheduler != scheduler) return; // 首过即抛:错误状态已落地,不宣布发声。
    state = const DemoPlaybackState(status: DemoPlaybackStatus.playing);
    _endWatch = Timer.periodic(_endPoll, (_) => _checkEnd());
  }

  /// 曲末判定:引擎时刻走过 [endOffset](名义曲长+末扫错峰尾)即回闲。
  /// 已响声的余音不在停声范围(自然衰减,与曲末的跟练同一处理)。
  void _checkEnd() {
    final timeline = _timeline;
    if (timeline == null || _scheduler == null) return;
    if (ref.read(audioEngineProvider).engineTime() <
        _t0 + endOffset(timeline)) {
      return;
    }
    stop();
  }

  void _failPreparing(String message) {
    if (!ref.mounted || state.status != DemoPlaybackStatus.preparing) return;
    state = DemoPlaybackState(status: DemoPlaybackStatus.idle, error: message);
  }

  void _onEngineError(Object error) {
    stop();
    if (!ref.mounted) return; // 容器已随应用退出:状态无可落盘。
    state = DemoPlaybackState(error: '引擎出错,试听已停止:$error');
  }

  void _teardown() {
    _discardSession();
  }
}
