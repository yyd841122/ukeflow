import 'dart:typed_data';

/// 已注入引擎的音源(loadMem 产物),可反复用于 playClocked 预定。
abstract interface class EngineSound {
  String get key;
}

/// 一次预定的发声实例(playClocked 产物);对象身份即是可 stop 的凭据。
abstract interface class EngineVoice {}

/// 音频引擎封装(ADR-0005 音频骨干)。
///
/// 唯一时钟规则:产品内一切时间同步只认 [engineTime];实现与调用方
/// 都不得引入挂钟(DateTime/Stopwatch)参与音画对齐。
abstract interface class AudioEngine {
  bool get isInitialized;

  /// 幂等初始化;并发调用合并为同一次。
  Future<void> ensureInitialized();

  /// 唯一可信时钟:引擎混音时钟,自引擎启动起单调递增。
  Duration engineTime();

  /// 内存 PCM(WAV 字节)注入,返回可预定的音源。
  Future<EngineSound> loadMem(String key, Uint8List wavBytes);

  /// 在引擎时刻 [when] 采样级预定发声(playClocked 语义,~2 秒窗口)。
  EngineVoice playClocked(EngineSound sound, Duration when);

  /// 停止一个 voice;已响完则为无害空操作。
  void stop(EngineVoice voice);

  /// 释放一个音源(停止其全部在响实例并回收内存;工单 33 评分重听的
  /// 一次性音源用)。释放后再 play 是程序错误;引擎已关时无害返回。
  Future<void> unload(EngineSound sound);

  /// 关闭引擎(应用退出时)。
  void dispose();
}
