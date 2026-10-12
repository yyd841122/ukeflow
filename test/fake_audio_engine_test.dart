import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';

/// FakeAudioEngine:后续工单(04 合成拨弦/09 跟练)的测试引擎。
/// 验证它能当引擎用:时钟手动驱动、预定可断言、停止可观测——全程不碰原生代码。
void main() {
  test('初始化生命周期:未初始化→就绪;注入失败时错误可见', () async {
    final ok = FakeAudioEngine();
    expect(ok.isInitialized, isFalse);
    await ok.ensureInitialized();
    expect(ok.isInitialized, isTrue);

    final bad = FakeAudioEngine()..failInitialization = true;
    await expectLater(bad.ensureInitialized(), throwsException);
    expect(bad.isInitialized, isFalse);
  });

  test('引擎时钟由测试手动驱动,单调可设', () {
    final engine = FakeAudioEngine();
    expect(engine.engineTime(), Duration.zero);
    engine.advance(const Duration(milliseconds: 123));
    expect(engine.engineTime(), const Duration(milliseconds: 123));
    engine.now = const Duration(seconds: 5);
    expect(engine.engineTime(), const Duration(seconds: 5));
  });

  test('loadMem 记录注入的音源键,playClocked 记录时刻与音源', () async {
    final engine = FakeAudioEngine();
    final sound = await engine.loadMem('tick_strong', Uint8List(4));
    expect(engine.loadedKeys, ['tick_strong']);

    engine.advance(const Duration(milliseconds: 50));
    engine.playClocked(sound, const Duration(milliseconds: 500));
    engine.playClocked(sound, const Duration(milliseconds: 1000));

    expect(
      engine.scheduleLog.map((c) => (c.key, c.time)),
      [
        ('tick_strong', const Duration(milliseconds: 500)),
        ('tick_strong', const Duration(milliseconds: 1000)),
      ],
    );
  });

  test('stop 标记对应预定记录;每个 voice 有唯一 id', () async {
    final engine = FakeAudioEngine();
    final sound = await engine.loadMem('tick_weak', Uint8List(4));
    final a = engine.playClocked(sound, Duration.zero) as FakeVoice;
    final b = engine.playClocked(sound, Duration.zero) as FakeVoice;
    expect(a.id, isNot(b.id));

    engine.stop(a);
    expect(engine.scheduleLog[0].stopped, isTrue);
    expect(engine.scheduleLog[1].stopped, isFalse);
  });
}
