import 'audio_engine.dart';
import 'karplus_strong.dart';

/// 拨弦播放器:KarplusStrong 合成 → loadMem 注入 → playClocked 发声。
/// 音源与引擎解耦(ADR-0004),按「音高×时长」缓存注入结果——
/// 同音反复拨不重复合成/注入。和弦示范音等后续工单复用同一管线。
class PluckPlayer {
  PluckPlayer({required this.engine});

  final AudioEngine engine;
  final Map<String, Future<EngineSound>> _sounds = {};

  /// 拨响 [freq]Hz 音,持续 [ms] 毫秒;[after] 为相对引擎当前时刻的延迟
  /// (工单 05 和弦示范音据此错峰拨响)。首次拨响前确保引擎就绪;
  /// 初始化失败等错误原样上抛,由调用方决定呈现。
  Future<void> pluck({
    required double freq,
    int ms = 1500,
    Duration after = Duration.zero,
  }) async {
    await engine.ensureInitialized();
    // 键用 double 的精确串(最短往返表示):近音高不碰撞,同音必同键。
    final key = 'pluck_${freq}_$ms';
    final sound = await (_sounds[key] ??= _load(key, freq, ms));
    engine.playClocked(sound, engine.engineTime() + after);
  }

  Future<EngineSound> _load(String key, double freq, int ms) async {
    try {
      return await engine.loadMem(key, KarplusStrong.pluck(freq: freq, ms: ms));
    } on Object {
      _sounds.remove(key); // 注入失败不缓存,下次拨同音可重试
      rethrow;
    }
  }
}
