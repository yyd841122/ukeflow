import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/pluck_player.dart';

/// PluckPlayer:KarplusStrong 合成 → loadMem → playClocked 的引擎接缝。
/// 一律经 AudioEngine 接口断言(FakeAudioEngine),不碰真引擎——
/// fake_audio_engine.dart 预定的工单 04 消费方式。
void main() {
  test('拨弦即注入音源并在引擎当前时刻预定', () async {
    final engine = FakeAudioEngine()..now = const Duration(milliseconds: 500);
    final player = PluckPlayer(engine: engine);

    await player.pluck(freq: 440);

    expect(engine.loadedKeys, ['pluck_440.0_1500'], reason: '键含音高与时长');
    expect(engine.scheduleLog, hasLength(1));
    expect(engine.scheduleLog.single.key, 'pluck_440.0_1500');
    expect(
      engine.scheduleLog.single.time,
      const Duration(milliseconds: 500),
      reason: '立即拨响 = 引擎当前时刻',
    );
  });

  test('同参数反复拨响只注入一次(缓存命中)', () async {
    final engine = FakeAudioEngine();
    final player = PluckPlayer(engine: engine);

    await player.pluck(freq: 440);
    await player.pluck(freq: 440);
    await player.pluck(freq: 440, ms: 800);

    expect(engine.loadedKeys, hasLength(2), reason: '440@1500 与 440@800 各一次');
    expect(engine.scheduleLog, hasLength(3), reason: '三次都预定发声');
  });

  test('不同音高各注入各的音源', () async {
    final engine = FakeAudioEngine();
    final player = PluckPlayer(engine: engine);

    await player.pluck(freq: 392);
    await player.pluck(freq: 261.63);

    expect(engine.loadedKeys, ['pluck_392.0_1500', 'pluck_261.63_1500']);
  });

  test('引擎初始化失败:错误上抛给调用方', () async {
    final engine = FakeAudioEngine()..failInitialization = true;
    final player = PluckPlayer(engine: engine);

    await expectLater(player.pluck(freq: 440), throwsException);
  });

  test('after 参数:相对引擎当前时刻延迟预定(工单 05 错峰琶音依赖)', () async {
    final engine = FakeAudioEngine()..now = const Duration(seconds: 2);
    final player = PluckPlayer(engine: engine);

    await player.pluck(freq: 330, after: const Duration(milliseconds: 120));

    expect(engine.scheduleLog.single.time, const Duration(milliseconds: 2120));
  });
}
