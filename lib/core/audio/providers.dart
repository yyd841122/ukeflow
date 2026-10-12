import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_engine.dart';
import 'pluck_player.dart';
import 'soloud_audio_engine.dart';

/// 全局唯一引擎实例(应用生命周期)。真实现在此装配,接口见 audio_engine.dart。
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = SoloudAudioEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// 全局拨弦播放器:音源缓存随应用存活——同音高反复拨/跨页面重进
/// 都不重复合成与注入(工单 05 和弦示范音复用同一实例)。
final pluckPlayerProvider = Provider<PluckPlayer>((ref) {
  return PluckPlayer(engine: ref.watch(audioEngineProvider));
});
