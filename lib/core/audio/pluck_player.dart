import 'audio_engine.dart';
import 'karplus_strong.dart';

/// 拨弦播放器:KarplusStrong 合成 → loadMem 注入 → playClocked 发声。
/// 音源与引擎解耦(ADR-0004),按「音高×时长」缓存注入结果——
/// 同音反复拨不重复合成/注入。和弦示范音等后续工单复用同一管线。
class PluckPlayer {
  /// 和弦错峰间隔:相邻弦位拨响的时间差。慢扫琶音感可闻而不散,
  /// 静默的闷音弦同样占时位——拨片物理上扫过它。
  static const strumGap = Duration(milliseconds: 45);

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
    final sound = await _soundFor(freq, ms);
    engine.playClocked(sound, engine.engineTime() + after);
  }

  /// 错峰拨响一组弦音(和弦示范音,工单 11 示范试听复用同一入口):
  /// [freqs] 按弹奏位次排列(4 弦→1 弦),闷音弦为 null——占时位但不拨响,
  /// 相邻弦位错峰 [strumGap]。全部音源先完成注入再读一次引擎时钟作
  /// 公共基准,采样级错峰——错峰间隔不受加载耗时影响(合成串行、
  /// loadMem 注入并发,时序保证只在注入这一层需要)。
  Future<void> strum({required List<double?> freqs}) async {
    await engine.ensureInitialized();
    final sounds = await Future.wait([
      for (final freq in freqs)
        if (freq != null) _soundFor(freq),
    ]);
    final base = engine.engineTime();
    var slot = Duration.zero;
    var next = 0;
    for (final freq in freqs) {
      final sound = freq == null ? null : sounds[next++];
      if (sound != null) engine.playClocked(sound, base + slot);
      slot += strumGap;
    }
  }

  /// 「音高×时长」对应的音源,首次取用时合成并注入(缓存见类注释)。
  Future<EngineSound> _soundFor(double freq, [int ms = 1500]) {
    // 键用 double 的精确串(最短往返表示):近音高不碰撞,同音必同键。
    final key = 'pluck_${freq}_$ms';
    return _sounds[key] ??= _load(key, freq, ms);
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
