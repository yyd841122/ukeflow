import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

/// 麦克风采集的窄接口(工单 19):控制器依赖此缝,测试以假件注入。
/// 采集参数(PCM16/44.1kHz/单声道)是检测管线的契约,定死在实现里。
abstract interface class TunerRecorder {
  /// 麦克风权限。[request] 为 true 时触发系统弹窗;false 仅查状态。
  Future<bool> hasPermission({bool request});

  /// 开始采集,返回 PCM16LE 字节流。调用前须已获权限。
  Future<Stream<Uint8List>> startStream();

  /// 停止采集。
  Future<void> stop();

  /// 释放底层资源。
  void dispose();
}

/// record 包的真实实现(调音链路:PCM16/44.1kHz/单声道,spike A 验证参数;
/// 工单 33 评分复用同一配置——AGC/回声消除/降噪须全关,record_platform_
/// interface 2.1.0 三字段 Dart 缺省即 false,这里显式钉死:AGC 动幅度毁
/// 安静门、降噪动频谱毁色度,平台侧是否照办真机机检兜底)。
class RecordTunerRecorder implements TunerRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  static const _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 44100,
    numChannels: 1,
    autoGain: false,
    echoCancel: false,
    noiseSuppress: false,
  );

  @override
  Future<bool> hasPermission({bool request = true}) =>
      _recorder.hasPermission(request: request);

  @override
  Future<Stream<Uint8List>> startStream() => _recorder.startStream(_config);

  @override
  Future<void> stop() => _recorder.stop();

  @override
  void dispose() => _recorder.dispose();
}

/// 全局唯一录音器(调音器页生命周期共用;引擎类资源随容器释放)。
final tunerRecorderProvider = Provider<TunerRecorder>((ref) {
  final recorder = RecordTunerRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});
