import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_engine.dart';

/// flutter_soloud 真实现(ADR-0005)。
/// 初始化参数为 spike B 真机验证值:44.1kHz / buffer 1024 / mono / lowLatency。
class SoloudAudioEngine implements AudioEngine {
  static const _sampleRate = 44100;
  static const _bufferSize = 1024;

  Future<void>? _initializing;

  @override
  bool get isInitialized => SoLoud.instance.isInitialized;

  @override
  Future<void> ensureInitialized() {
    if (SoLoud.instance.isInitialized) return Future.value();
    // 并发调用合并:SoLoud 内部会排队重复 init,这里直接复用同一个 Future。
    return _initializing ??= SoLoud.instance
        .init(
          sampleRate: _sampleRate,
          bufferSize: _bufferSize,
          channels: Channels.mono,
          lowLatency: true,
        )
        .whenComplete(() => _initializing = null);
  }

  @override
  Duration engineTime() {
    // 引擎已关时返回零点而非抛异常:停机路径(驱动器 stop)还会读时刻,
    // 死引擎上一切时刻比较都无害(voice 已随引擎消亡)。
    final soloud = SoLoud.instance;
    return soloud.isInitialized ? soloud.getEngineTime() : Duration.zero;
  }

  @override
  Future<EngineSound> loadMem(String key, Uint8List wavBytes) async {
    await ensureInitialized();
    final source = await SoLoud.instance.loadMem(
      key,
      wavBytes,
      mode: LoadMode.memory,
    );
    return SoloudSound(key, source);
  }

  @override
  EngineVoice playClocked(EngineSound sound, Duration when) {
    // 音源对象由本引擎的 loadMem 产出;跨引擎混用是程序错误,直接炸出。
    final source = (sound as SoloudSound).source;
    return SoloudVoice(SoLoud.instance.playClocked(source, when));
  }

  @override
  void stop(EngineVoice voice) {
    if (!SoLoud.instance.isInitialized) return;
    // stop 是异步的,停止发声不需要等它;引擎已关时这里已提前返回。
    unawaited(
      SoLoud.instance.stop((voice as SoloudVoice).handle).catchError((_) {}),
    );
  }

  @override
  void dispose() {
    if (SoLoud.instance.isInitialized) SoLoud.instance.deinit();
  }
}

final class SoloudSound implements EngineSound {
  const SoloudSound(this.key, this.source);

  @override
  final String key;
  final AudioSource source;
}

final class SoloudVoice implements EngineVoice {
  const SoloudVoice(this.handle);

  final SoundHandle handle;
}
