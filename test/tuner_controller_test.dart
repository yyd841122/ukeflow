import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/tuner/tuner_recorder.dart';
import 'package:ukeflow/data/settings_providers.dart';
import 'package:ukeflow/features/tuner/tuner_controller.dart';

/// 调音控制器:录音器一律注入假件,检测链用合成正弦 PCM16 过**真 YIN**
/// (pitch_detector_dart 纯 Dart,假绿风险不在算法在接线)。
class FakeRecorder implements TunerRecorder {
  final controller = StreamController<Uint8List>();
  bool permissionGranted = true;
  int requestCalls = 0;
  int startStreamCalls = 0;
  int stopCalls = 0;

  @override
  Future<bool> hasPermission({bool request = true}) async {
    if (request) requestCalls++;
    return permissionGranted;
  }

  @override
  Future<Stream<Uint8List>> startStream() async {
    startStreamCalls++;
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  void dispose() {}
}

/// [hz] 正弦的 PCM16LE(44.1kHz)整段,切成等长 [chunks] 段。
List<Uint8List> sineChunks(
  double hz, {
  int chunks = 3,
  int samplesPerChunk = 1600,
}) {
  const sampleRate = 44100;
  final total = chunks * samplesPerChunk;
  final bytes = ByteData(total * 2);
  for (var i = 0; i < total; i++) {
    final v = (6000 * math.sin(2 * math.pi * hz * i / sampleRate)).round();
    bytes.setInt16(i * 2, v, Endian.little);
  }
  return [
    for (var c = 0; c < chunks; c++)
      bytes.buffer.asUint8List(c * samplesPerChunk * 2, samplesPerChunk * 2),
  ];
}

void main() {
  late FakeRecorder recorder;
  late ProviderContainer container;

  setUp(() {
    recorder = FakeRecorder();
    container = ProviderContainer(
      overrides: [
        tunerRecorderProvider.overrideWithValue(recorder),
        // A4 参考音走派生 provider(设置消费缝,工单 20):override 隔离,
        // 不触真库(链路另一端是 drift 库,单测环境不可打开)。
        referenceA4Provider.overrideWithValue(440.0),
      ],
    );
    addTearDown(container.dispose);
  });

  TunerController tuner() => container.read(tunerProvider.notifier);
  TunerState state() => container.read(tunerProvider);

  /// 逐段推送正弦并让异步检测链落定。
  Future<void> pluck(List<Uint8List> chunks) async {
    for (final chunk in chunks) {
      recorder.controller.add(chunk);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('440Hz 正弦入流:读数稳定为 A4', () async {
    await tuner().start();
    expect(state().listening, isTrue);

    await pluck(sineChunks(440.0));
    final reading = state().reading;
    expect(reading, isNotNull, reason: '清亮正弦必出读数');
    expect(reading!.noteName, 'A4');
    expect(reading.cents, closeTo(0, 10));
  });

  test('权限拒绝:不进监听、给引导态,可再请求', () async {
    recorder.permissionGranted = false;
    await tuner().start();
    expect(state().listening, isFalse, reason: '无权限不开麦');
    expect(state().permissionDenied, isTrue, reason: '引导态供页面上设置指引');
    expect(recorder.startStreamCalls, 0);
    expect(recorder.requestCalls, 1, reason: '查状态拒后应触发一次系统弹窗请求');

    // 用户去设置开启后,再开始即可正常进入。
    recorder.permissionGranted = true;
    await tuner().start();
    expect(state().listening, isTrue);
    expect(state().permissionDenied, isFalse);
  });

  test('停止:退监听、清读数、录音器停', () async {
    await tuner().start();
    await pluck(sineChunks(440.0));
    expect(state().reading, isNotNull);

    await tuner().stop();
    expect(state().listening, isFalse);
    expect(state().reading, isNull, reason: '停止后不留陈旧读数');
    expect(recorder.stopCalls, 1);
  });

  test('静音入流(零样本)不出读数', () async {
    await tuner().start();
    await pluck(sineChunks(440.0));
    expect(state().reading, isNotNull);
    // 全零 PCM16:YIN 无周期,概率贴地。帧距越过 60ms 检测节流,
    // 模拟真实麦克风在静音期也持续推帧。
    for (final chunk in silenceChunks()) {
      recorder.controller.add(chunk);
      await Future<void>.delayed(const Duration(milliseconds: 70));
    }
    expect(state().reading, isNull, reason: '静音段不得残留/误报音高');
  });
}

/// 全零 PCM16LE,总时长与 sineChunks 默认同量级。
List<Uint8List> silenceChunks() => [
  Uint8List(3200),
  Uint8List(3200),
  Uint8List(3200),
];
