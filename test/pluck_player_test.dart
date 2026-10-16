import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/audio_engine.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/pluck_player.dart';
import 'package:ukeflow/core/model/strum_pattern.dart' show StrumDirection;

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

  test('同步注入失败不留在缓存:同音重试成功(审计30 #6)', () async {
    final engine = FakeAudioEngine();
    final player = PluckPlayer(engine: engine);

    engine.failLoadMemSync = true;
    await expectLater(player.pluck(freq: 440), throwsException);
    engine.failLoadMemSync = false;
    await expectLater(player.pluck(freq: 440), completes);
    expect(player.loadedSound(440), isNotNull, reason: '重试成功后进就绪底册');
  });

  test('after 参数:相对引擎当前时刻延迟预定(工单 05 错峰琶音依赖)', () async {
    final engine = FakeAudioEngine()..now = const Duration(seconds: 2);
    final player = PluckPlayer(engine: engine);

    await player.pluck(freq: 330, after: const Duration(milliseconds: 120));

    expect(engine.scheduleLog.single.time, const Duration(milliseconds: 2120));
  });

/// 工单 05 seam 2:strum 错峰拨响(和弦示范音;工单 11 示范试听复用同一入口)。
group('strum 错峰拨响', () {
  test('四音各占一个弦位时位:公共基准 + 45ms 等差(含静默弦位)', () async {
    final engine = FakeAudioEngine()..now = const Duration(milliseconds: 700);
    final player = PluckPlayer(engine: engine);

    await player.strum(freqs: const [392.0, 261.63, 329.63, 523.25]);

    expect(engine.scheduleLog.map((c) => c.time), [
      const Duration(milliseconds: 700),
      const Duration(milliseconds: 745),
      const Duration(milliseconds: 790),
      const Duration(milliseconds: 835),
    ], reason: '错峰间隔 = strumGap,与各音加载完成先后无关');
    expect(engine.loadedKeys, hasLength(4));
  });

  test('闷音弦(null)占时位不发声;全闷音零注入零预定', () async {
    final engine = FakeAudioEngine()..now = const Duration(milliseconds: 100);
    final player = PluckPlayer(engine: engine);

    await player.strum(freqs: const [null, 329.63, 392.0, 523.25]);

    expect(engine.scheduleLog, hasLength(3));
    expect(engine.scheduleLog.map((c) => c.time), [
      const Duration(milliseconds: 145),
      const Duration(milliseconds: 190),
      const Duration(milliseconds: 235),
    ], reason: '0 号弦位静默但仍占时位——拨片物理上扫过它');

    final quietEngine = FakeAudioEngine();
    await PluckPlayer(
      engine: quietEngine,
    ).strum(freqs: const [null, null, null, null]);
    expect(quietEngine.scheduleLog, isEmpty);
    expect(quietEngine.loadedKeys, isEmpty);
  });

  test('加载期间的时钟流逝不挤压错峰:基准在全部注入完成后读一次', () async {
    final engine = _GatedLoadEngine()..now = Duration.zero;
    final player = PluckPlayer(engine: engine);

    final done = player.strum(freqs: const [392.0, 261.63, 329.63]);
    await Future<void>.delayed(Duration.zero); // 三笔注入都到门口
    expect(engine.gates.keys.toSet(), {
      'pluck_392.0_1500',
      'pluck_261.63_1500',
      'pluck_329.63_1500',
    });

    // 注入分批完成,期间时钟流逝(真机首次载入的病态放大版)。
    engine.now = const Duration(seconds: 1);
    engine.gates['pluck_392.0_1500']!.complete();
    await Future<void>.delayed(Duration.zero);
    engine.now = const Duration(seconds: 2);
    engine.gates['pluck_261.63_1500']!.complete();
    await Future<void>.delayed(Duration.zero);
    engine.now = const Duration(seconds: 3);
    engine.gates['pluck_329.63_1500']!.complete();

    await done;
    expect(engine.scheduleLog.map((c) => c.time), [
      const Duration(seconds: 3),
      const Duration(seconds: 3, milliseconds: 45),
      const Duration(seconds: 3, milliseconds: 90),
    ], reason: '基准 = 全部注入后的引擎时刻,一次读定;退化成逐音 pluck(after:) 会把加载时延揉进错峰间隔');
  });

  test('音源缓存与 pluck 共用:同音不重注入', () async {
    final engine = FakeAudioEngine();
    final player = PluckPlayer(engine: engine);

    await player.pluck(freq: 392);
    await player.strum(freqs: const [392.0, 261.63]);
    await player.strum(freqs: const [392.0, 261.63]);

    expect(engine.loadedKeys, hasLength(2), reason: '392 与 261.63 各注入一次');
    expect(engine.scheduleLog, hasLength(5), reason: '1 + 2 + 2 次预定');
  });

  test('引擎初始化失败:错误上抛给调用方', () async {
    final engine = FakeAudioEngine()..failInitialization = true;
    final player = PluckPlayer(engine: engine);

    await expectLater(player.strum(freqs: const [392.0]), throwsException);
  });
});

/// 工单 10 接缝:预注入 + 同步查取(参考音=示范扫弦的调度器依赖——
/// 起跑前把全曲和弦音源一次注入到位,过窗调度免 await)。
group('preloadSounds/loadedSound', () {
  test('批量注入;loadedSound 同步查取已注入音源,未注入为 null', () async {
    final engine = FakeAudioEngine();
    final player = PluckPlayer(engine: engine);

    expect(player.loadedSound(392), isNull, reason: '未注入为 null');

    await player.preloadSounds(const [392.0, 261.63]);
    expect(engine.loadedKeys, ['pluck_392.0_1500', 'pluck_261.63_1500']);
    final sound = player.loadedSound(392);
    expect(sound, isNotNull);
    expect(sound!.key, 'pluck_392.0_1500');
    expect(player.loadedSound(440), isNull, reason: '未注入的音高仍 null');
  });

  test('与 pluck/strum 共用缓存:同音不重注入', () async {
    final engine = FakeAudioEngine();
    final player = PluckPlayer(engine: engine);

    await player.preloadSounds(const [392.0]);
    await player.strum(freqs: const [392.0, 261.63]);

    expect(engine.loadedKeys, hasLength(2), reason: '392 只注入一次');
    expect(engine.scheduleLog, hasLength(2), reason: 'strum 两弦都预定');
  });

  test('注入失败:错误上抛,同步查取不为 null(无半成品)', () async {
    final engine = FakeAudioEngine()..failInitialization = true;
    final player = PluckPlayer(engine: engine);

    await expectLater(player.preloadSounds(const [392.0]), throwsException);
    expect(player.loadedSound(392), isNull);
  });
});
/// 工单 11 接缝:方向定声——下/上扫各取各的衰减时长变体(音色区分
/// 的单一来源在 PluckPlayer,调度引擎只认音源)。
group('方向定声 strumMs/loadedStrumSound/preloadStrumSounds', () {
  test('preloadStrumSounds 两方向各注入一套;loadedStrumSound 按方向查取', () async {
    final engine = FakeAudioEngine();
    final player = PluckPlayer(engine: engine);

    expect(player.loadedStrumSound(392, StrumDirection.down), isNull,
        reason: '未注入为 null');

    await player.preloadStrumSounds(const [392.0]);
    expect(engine.loadedKeys.toSet(), {
      'pluck_392.0_1500',
      'pluck_392.0_700',
    }, reason: '下扫长衰减(与既有默认时长一致)、上扫短促,各一套');
    final down = player.loadedStrumSound(392, StrumDirection.down);
    final up = player.loadedStrumSound(392, StrumDirection.up);
    expect(down!.key, 'pluck_392.0_1500');
    expect(up!.key, 'pluck_392.0_700');
  });

  test('与既有缓存共用:同音同方向的变体不重注入', () async {
    final engine = FakeAudioEngine();
    final player = PluckPlayer(engine: engine);

    await player.preloadSounds(const [392.0]); // 下扫 1500 变体已在
    await player.preloadStrumSounds(const [392.0]);

    expect(
      engine.loadedKeys.where((k) => k == 'pluck_392.0_1500'),
      hasLength(1),
    );
    expect(
      engine.loadedKeys.where((k) => k == 'pluck_392.0_700'),
      hasLength(1),
    );
  });

  test('注入失败:错误上抛,同步查取无半成品', () async {
    final engine = FakeAudioEngine()..failInitialization = true;
    final player = PluckPlayer(engine: engine);

    await expectLater(
      player.preloadStrumSounds(const [392.0]),
      throwsException,
    );
    expect(player.loadedStrumSound(392, StrumDirection.down), isNull);
  });
});
}

/// loadMem 受门控的假引擎:模拟注入耗时不定的真机现场(工单 05 错峰把关用)。
class _GatedLoadEngine extends FakeAudioEngine {
  final gates = <String, Completer<void>>{};

  @override
  Future<EngineSound> loadMem(String key, Uint8List wavBytes) =>
      (gates[key] ??= Completer<void>()).future.then(
        (_) => super.loadMem(key, wavBytes),
      );
}
