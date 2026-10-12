import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_engine.dart';
import 'soloud_audio_engine.dart';

/// 全局唯一引擎实例(应用生命周期)。真实现在此装配,接口见 audio_engine.dart。
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = SoloudAudioEngine();
  ref.onDispose(engine.dispose);
  return engine;
});
