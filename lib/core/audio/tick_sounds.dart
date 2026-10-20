import 'audio_engine.dart';
import 'scoring_tick_synth.dart';
import 'tick_synth.dart';

/// 强弱拍/预备拍 tick 音源的一揽子装载(工单 19 评审提取:节拍器、节奏型
/// 训练、弹唱跟练、指弹跟练四份控制器的逐字重复收拢)。
///
/// 各控制器按需取子集:节拍器/训练 strong+weak,弹唱跟练再加 count,
/// 指弹跟练仅 count。loadMem 逐支 await——flutter_soloud 对并发注入的
/// 顺序无保证,顺序装载是工单 30 #9 回归后的既定纪律。
class TickSounds {
  TickSounds({
    this.strong,
    this.weak,
    this.count,
    this.scoringBeep,
    this.scoringAccent,
  });

  final EngineSound? strong;
  final EngineSound? weak;
  final EngineSound? count;

  /// 评分嘀声对(工单 33):880Hz 普通拍 / 1320Hz 重音,4ms 软化淡入,
  /// 麦端陷波缝上可滤(见 [ScoringTickSynth])。弹唱跟练 warmup 一并装载。
  final EngineSound? scoringBeep;
  final EngineSound? scoringAccent;

  static Future<TickSounds> load(
    AudioEngine engine, {
    bool strong = false,
    bool weak = false,
    bool count = false,
    bool scoring = false,
  }) async {
    return TickSounds(
      strong: strong
          ? await engine.loadMem('tick_strong', TickSynth.strong())
          : null,
      weak: weak ? await engine.loadMem('tick_weak', TickSynth.weak()) : null,
      count: count
          ? await engine.loadMem('tick_count', TickSynth.count())
          : null,
      scoringBeep: scoring
          ? await engine.loadMem('tick_scoring_beep', ScoringTickSynth.beep())
          : null,
      scoringAccent: scoring
          ? await engine.loadMem(
              'tick_scoring_accent',
              ScoringTickSynth.accent(),
            )
          : null,
    );
  }
}

/// 在途合并闸:并发调用共享同一次执行(工单 19 评审提取并顺修——节拍器/
/// 节奏型训练的 warmup 原缺此合并,快速重进页会重复注入音源;与弹唱/指弹
/// 跟练既有的 `_warming ??=` 同一语义)。
class SingleFlight {
  Future<void>? _pending;

  Future<void> run(Future<void> Function() body) =>
      _pending ??= body().whenComplete(() => _pending = null);
}
