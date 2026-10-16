import 'dart:async';

import 'audio_engine.dart';
import 'karplus_strong.dart';
import '../model/strum_pattern.dart' show StrumDirection;

/// 拨弦播放器:KarplusStrong 合成 → loadMem 注入 → playClocked 发声。
/// 音源与引擎解耦(ADR-0004),按「音高×时长」缓存注入结果——
/// 同音反复拨不重复合成/注入。和弦示范音等后续工单复用同一管线。
class PluckPlayer {
  /// 和弦错峰间隔:相邻弦位拨响的时间差。慢扫琶音感可闻而不散,
  /// 静默的闷音弦同样占时位——拨片物理上扫过它。
  static const strumGap = Duration(milliseconds: 45);

  /// 下扫拨弦的衰减时长(毫秒,t60 语义见 KarplusStrong):全弦释放、
  /// 长衰减,与 pluck/strum 的默认时长一致,也是「音高×时长」键的
  /// 缺省时长——pluck/strum/缓存查取与下扫共用同一变体。
  static const int downStrumMs = 1500;

  /// 上扫拨弦的衰减时长:轻拨上挑、短促干脆——下/上扫音色区分
  /// (工单 11)的单一来源。换采样音源(ADR-0004)时此处换成采样选择,
  /// 调度引擎只认音源、不感知方向音色。
  static const int upStrumMs = 700;

  /// 扫弦方向对应的拨弦衰减时长。
  static int strumMs(StrumDirection direction) =>
      direction == StrumDirection.down ? downStrumMs : upStrumMs;

  PluckPlayer({required this.engine});

  final AudioEngine engine;
  final Map<String, Future<EngineSound>> _sounds = {};

  /// 注入成功的音源(键同 [loadedSound]):同步查取的底册。
  final Map<String, EngineSound> _ready = {};

  /// 拨响 [freq]Hz 音,持续 [ms] 毫秒;[after] 为相对引擎当前时刻的延迟
  /// (工单 05 和弦示范音据此错峰拨响)。首次拨响前确保引擎就绪;
  /// 初始化失败等错误原样上抛,由调用方决定呈现。
  Future<void> pluck({
    required double freq,
    int ms = downStrumMs,
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

  /// 「音高×时长」的音源键( [_soundFor]/[loadedSound] 单一来源;键用
  /// double 的精确串,近音高不碰撞、同音必同键)。缺省时长 = 下扫衰减
  /// ([downStrumMs])。
  static String _keyFor(double freq, [int ms = downStrumMs]) =>
      'pluck_${freq}_$ms';

  /// 「音高×时长」对应的音源,首次取用时合成并注入(缓存见类注释)。
  ///
  /// 注入失败清缓存挂在插入**之后**:异步函数同步段抛错(合成/引擎
  /// 同步失败)时,catch 先于本方法插入执行,内部的 remove 会落空——
  /// 错误 Future 一旦留在缓存,同音重试永远拿到同一失败(审计
  /// 2026-10-16 #6)。identical 守卫:若同音已被新一次取用重新插入,
  /// 旧失败的回滚不得误删。
  Future<EngineSound> _soundFor(double freq, [int ms = downStrumMs]) {
    final key = _keyFor(freq, ms);
    final existing = _sounds[key];
    if (existing != null) return existing;
    final future = _load(key, freq, ms);
    _sounds[key] = future;
    unawaited(future.then(
      (_) {},
      onError: (Object _) {
        if (identical(_sounds[key], future)) _sounds.remove(key);
      },
    ));
    return future;
  }

  /// 预注入一批拨弦音源(工单 10 参考音=示范扫弦:跟练起跑前把全曲
  /// 和弦音源一次注入到位,调度期免 await);与 pluck/strum 共用缓存。
  Future<void> preloadSounds(Iterable<double> freqs) async {
    await engine.ensureInitialized();
    for (final freq in freqs) {
      await _soundFor(freq);
    }
  }

  /// 预注入扫弦音源(工单 11:两个方向的衰减变体各一套);与既有缓存
  /// 共用,已注入的变体不重注入。错误原样上抛由调用方定呈现。
  Future<void> preloadStrumSounds(Iterable<double> freqs) async {
    await engine.ensureInitialized();
    for (final freq in freqs) {
      await _soundFor(freq, downStrumMs);
      await _soundFor(freq, upStrumMs);
    }
  }

  /// 已注入音源的同步查取(调度器过窗免 await 用);未注入返回 null。
  /// 只有注入成功过的音高非 null,无半成品。
  EngineSound? loadedSound(double freq, [int ms = downStrumMs]) =>
      _ready[_keyFor(freq, ms)];

  /// 方向定声的已注入音源查取(工单 11 扫弦路径):下/上扫各取各的
  /// 衰减变体(见 [strumMs])。
  EngineSound? loadedStrumSound(double freq, StrumDirection direction) =>
      loadedSound(freq, strumMs(direction));

  Future<EngineSound> _load(String key, double freq, int ms) async {
    final sound = await engine.loadMem(
      key,
      KarplusStrong.pluck(freq: freq, ms: ms),
    );
    return _ready[key] = sound;
  }
}
