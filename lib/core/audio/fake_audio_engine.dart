import 'dart:typed_data';

import 'audio_engine.dart';

/// 测试假实现:不碰任何原生代码、不发起平台通道。
/// 测试手动驱动引擎时钟([advance]/[now]),[scheduleLog] 记录全部
/// 预定/停止调用供断言——后续工单(04 拨弦合成、09 跟练)由此可测而不碰真引擎。
class FakeAudioEngine implements AudioEngine {
  /// 注入初始化失败,测试错误路径用。
  bool failInitialization = false;

  /// 注入运行中预定失败(模拟真机引擎异常)。
  bool failNow = false;

  /// 注入同步 loadMem 失败(异常在 Future 之前同步抛出;测试
  /// 同步失败路径与缓存回滚时序)。
  bool failLoadMemSync = false;

  /// 注入 engineTime 失败(模拟引擎时钟不可读)。
  bool failClock = false;

  /// 注入 stop 失败(模拟取消失败)。
  bool failStop = false;

  final List<String> loadedKeys = [];
  final List<FakeScheduledCall> scheduleLog = [];

  Duration _now = Duration.zero;
  bool _initialized = false;
  int _nextVoiceId = 0;

  /// 直接设定引擎时刻(测试制造任意现场)。
  set now(Duration value) => _now = value;

  /// 引擎时钟前进 [delta](测试推进时间)。
  void advance(Duration delta) => _now += delta;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> ensureInitialized() async {
    if (failInitialization) {
      throw Exception('FakeAudioEngine: 模拟引擎初始化失败');
    }
    _initialized = true;
  }

  @override
  Duration engineTime() {
    if (failClock) throw Exception('FakeAudioEngine: 模拟引擎时钟不可读');
    return _now;
  }

  @override
  Future<EngineSound> loadMem(String key, Uint8List wavBytes) {
    // 非 async:failLoadMemSync 的异常同步抛给调用方(接口允许同步失败,
    // 真实现也有同步段,PluckPlayer 缓存回滚必须两头都兜)。
    if (failLoadMemSync) {
      throw Exception('FakeAudioEngine: 模拟同步注入失败');
    }
    loadedKeys.add(key);
    return Future.value(FakeSound(key));
  }

  @override
  EngineVoice playClocked(EngineSound sound, Duration when) {
    if (failNow) throw Exception('FakeAudioEngine: 模拟运行中引擎异常');
    final voice = FakeVoice(_nextVoiceId++);
    scheduleLog.add(FakeScheduledCall(key: sound.key, time: when, voice: voice));
    return voice;
  }

  @override
  void stop(EngineVoice voice) {
    if (failStop) throw Exception('FakeAudioEngine: 模拟取消失败');
    for (final call in scheduleLog) {
      if (identical(call.voice, voice)) call.stopped = true;
    }
  }

  @override
  void dispose() => _initialized = false;
}

final class FakeSound implements EngineSound {
  const FakeSound(this.key);

  @override
  final String key;
}

final class FakeVoice implements EngineVoice {
  const FakeVoice(this.id);

  /// 本假实现内部的记账序号(生产路径无此需求,不进接口)。
  final int id;
}

/// 一条预定记录:[key] 音源预定在引擎时刻 [time],[voice] 可被 stop 标记。
final class FakeScheduledCall {
  FakeScheduledCall({
    required this.key,
    required this.time,
    required this.voice,
  });

  final String key;
  final Duration time;
  final EngineVoice voice;
  bool stopped = false;
}
