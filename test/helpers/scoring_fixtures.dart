import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/practice/play_timeline.dart';
import 'package:ukeflow/core/tuner/tuner_recorder.dart';
import 'package:ukeflow/data/chord_library.dart' show Chord;
import 'package:ukeflow/data/settings_providers.dart';
import 'package:ukeflow/features/play/scoring/practice_scoring_controller.dart';
import 'package:ukeflow/features/play/scoring/practice_session_handle.dart';

/// 跟练评分测试夹具(工单 33):合成扫弦/和弦信号、假录音器、假会话柄。
/// 与 onset_detector_test 的信号配方同源,提出来供控制器级测试复用。

const int scoringTestSampleRate = 44100;

/// 白噪声 × 指数衰减的宽带扫弦拟声(硬起音)。
Float64List strumBurst({
  required double atSec,
  double lengthSec = 0.15,
  double amp = 0.4,
  int seed = 1,
  int totalSamples = scoringTestSampleRate * 30,
}) {
  final out = Float64List(totalSamples);
  final random = math.Random(seed);
  final start = (atSec * scoringTestSampleRate).round();
  final len = (lengthSec * scoringTestSampleRate).round();
  for (var i = 0; i < len && start + i < totalSamples; i++) {
    final t = i / scoringTestSampleRate;
    out[start + i] = (random.nextDouble() * 2 - 1) * amp * math.exp(-t / 0.05);
  }
  return out;
}

/// 合成扫弦拟声(和弦):各弦基频正弦 × 错峰起振 × 指数衰减 + 微噪声。
/// 色度上就是该和弦(供「错」判定的封闭验证测试)。
Float64List chordBurst(
  List<int> midiNotes, {
  required double atSec,
  double lengthSec = 0.3,
  double amp = 0.4,
  int totalSamples = scoringTestSampleRate * 30,
}) {
  final out = Float64List(totalSamples);
  final start = (atSec * scoringTestSampleRate).round();
  final random = math.Random(atSec.hashCode & 0xffff);
  for (var s = 0; s < midiNotes.length; s++) {
    final f = 440.0 * math.pow(2, (midiNotes[s] - 69) / 12);
    final offset = start + s * (0.005 * scoringTestSampleRate).round();
    final len = (lengthSec * scoringTestSampleRate).round();
    for (var i = 0; offset + i < totalSamples && i < len; i++) {
      final t = i / scoringTestSampleRate;
      out[offset + i] +=
          math.sin(2 * math.pi * f * t) *
          amp /
          midiNotes.length *
          math.exp(-t / 0.08);
    }
  }
  for (var i = 0; i < totalSamples; i++) {
    out[i] += (random.nextDouble() * 2 - 1) * 0.003;
  }
  return out;
}

/// Float64 样本 → PCM16LE 字节(麦 chunk 的线上形态)。
Uint8List pcm16Bytes(Float64List samples) {
  final out = Uint8List(samples.length * 2);
  final view = ByteData.view(out.buffer);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(
      i * 2,
      (samples[i] * 32767).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return out;
}

/// 信号在 [fromSec, toSec) 的切片。
Float64List slice(Float64List signal, double fromSec, double toSec) {
  final sr = scoringTestSampleRate;
  final from = (fromSec * sr).round();
  final to = math.min((toSec * sr).round(), signal.length);
  return Float64List.sublistView(signal, from, math.max(to, from));
}

/// 假录音器:权限/启动可注入失败,chunk 经 [push] 手工灌入。
final class FakeRecorder implements TunerRecorder {
  bool granted = true;
  bool startOk = true;
  int stopCount = 0;

  StreamController<Uint8List>? _chunks;

  @override
  Future<bool> hasPermission({bool request = true}) async => granted;

  @override
  Future<Stream<Uint8List>> startStream() async {
    if (!startOk) throw Exception('模拟开麦失败');
    _chunks = StreamController<Uint8List>();
    return _chunks!.stream;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    await _chunks?.close();
    _chunks = null;
  }

  @override
  void dispose() {}

  void push(Uint8List chunk) => _chunks?.add(chunk);
}

/// 假会话柄:时间轴/锚点/周期/和弦表全部测试可控(变速用例直接改
/// periodMs,不经过真调度器)。
final class FakeSessionHandle implements PracticeSessionHandle {
  FakeSessionHandle({this.timeline, this.chords = const {}});

  @override
  PlayTimeline? timeline;

  @override
  Map<String, Chord> chords;

  Duration anchor = Duration.zero;

  @override
  double periodMs = 750;

  /// setScoringTicks 的调用记录(断言评分会话接线用)。
  final List<bool> scoringTicksCalls = [];

  @override
  Duration? get scheduleAnchor => timeline == null ? null : anchor;

  @override
  void setScoringTicks(bool value) => scoringTicksCalls.add(value);

  void closeSession() => timeline = null;
}

/// 测试容器:假引擎 + 假录音器 + 假会话柄(不触真库/真麦/真调度器)。
({
  FakeAudioEngine engine,
  FakeRecorder recorder,
  FakeSessionHandle handle,
  ProviderContainer container,
})
scoringTestContainer({int latencyMs = 100}) {
  final engine = FakeAudioEngine();
  final recorder = FakeRecorder();
  final handle = FakeSessionHandle();
  final container = ProviderContainer(
    overrides: [
      audioEngineProvider.overrideWithValue(engine),
      tunerRecorderProvider.overrideWithValue(recorder),
      practiceScoringHandleProvider.overrideWithValue(handle),
      scoringLatencyMsProvider.overrideWithValue(latencyMs),
    ],
  );
  return (
    engine: engine,
    recorder: recorder,
    handle: handle,
    container: container,
  );
}
