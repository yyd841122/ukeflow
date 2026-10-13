import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/audio_engine.dart';
import 'package:ukeflow/core/audio/beat_scheduler.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';

/// 调度驱动器:40ms 轮询 + 400ms 窗口,发声全部经引擎 playClocked。
/// Timer 只当轮询触发器;一切时刻读引擎时钟(ADR-0005)。
void main() {
  late FakeAudioEngine engine;
  late EngineSound strong;
  late EngineSound weak;

  setUp(() async {
    engine = FakeAudioEngine();
    strong = await engine.loadMem('tick_strong', Uint8List(0));
    weak = await engine.loadMem('tick_weak', Uint8List(0));
  });

  test('start 立即首过:第 0 拍(强拍)预定在引擎当前时刻', () {
    fakeAsync((async) {
      final scheduler = BeatScheduler(
        engine: engine,
        pickSound: (beat) => beat % 4 == 0 ? strong : weak,
      );
      scheduler.start(bpm: 120);
      expect(scheduler.running, isTrue);
      expect(engine.scheduleLog, hasLength(1));
      expect(engine.scheduleLog.first.key, 'tick_strong');
      expect(engine.scheduleLog.first.time, Duration.zero);
    });
  });

  test('40ms 步进 10 秒:拍 0..20 全部按精确 500ms 网格预定', () {
    fakeAsync((async) {
      final scheduler = BeatScheduler(
        engine: engine,
        pickSound: (beat) => beat % 4 == 0 ? strong : weak,
      );
      scheduler.start(bpm: 120);
      for (var i = 0; i < 250; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      // now=10s,窗右沿 10.4s:拍 i ≤ 20(500×20=10000 ≤ 10400)→ 21 拍。
      expect(scheduler.scheduledCount, 21);
      for (var beat = 0; beat < 21; beat++) {
        expect(
          engine.scheduleLog[beat].time,
          Duration(milliseconds: beat * 500),
          reason: '拍 $beat',
        );
      }
      // 4/4 强弱:拍 0/4/8/16/20 强,其余弱。
      for (var beat = 0; beat < 21; beat++) {
        expect(
          engine.scheduleLog[beat].key,
          beat % 4 == 0 ? 'tick_strong' : 'tick_weak',
          reason: '拍 $beat',
        );
      }
    });
  });

  test('运行中 changeBpm:之后拍距变为新周期,无重复拍号', () {
    fakeAsync((async) {
      final scheduler = BeatScheduler(
        engine: engine,
        pickSound: (beat) => beat % 4 == 0 ? strong : weak,
      );
      scheduler.start(bpm: 120);
      for (var i = 0; i < 50; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      // now=2s:已预定拍 0..4(500×5=2500 > 2400 未到)→ nextBeat=5。
      expect(scheduler.scheduledCount, 5);
      scheduler.changeBpm(90);
      for (var i = 0; i < 100; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      // now=6s:换速点 2s,newT0 = 2000 − round(4×666.67) = −667ms(文档化舍入);
      // 拍 j = −667 + round(j×666.67)。窗右沿 6.4s → 拍 10(6000ms)止,共 11 拍。
      expect(scheduler.scheduledCount, 11);
      expect(engine.scheduleLog[5].time.inMilliseconds, 2666, reason: 'now+666.67ms');
      expect(engine.scheduleLog[10].time.inMilliseconds, 6000, reason: 'round(10×666.67)=6667');
      // 拍号无重复、时刻严格递增。
      final times = engine.scheduleLog.map((c) => c.time).toList();
      expect(times, times.toSet().toList(), reason: '无重复预定');
      for (var i = 1; i < times.length; i++) {
        expect(times[i], greaterThan(times[i - 1]), reason: '时刻单调 $i');
      }
    });
  });

  test('stop:未响拍全部停止,已响拍不动;之后不再调度', () {
    fakeAsync((async) {
      final scheduler = BeatScheduler(
        engine: engine,
        pickSound: (beat) => beat % 4 == 0 ? strong : weak,
      );
      scheduler.start(bpm: 120);
      for (var i = 0; i < 12; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      // now≈480ms:拍0(0ms)已响,拍1(500ms)未响。
      expect(engine.scheduleLog, isNotEmpty);
      final scheduledBeforeStop = engine.scheduleLog.length;

      scheduler.stop();
      expect(scheduler.running, isFalse);

      final stoppedVoices = engine.scheduleLog
          .where((c) => c.stopped)
          .map((c) => c.voice)
          .toSet();
      expect(stoppedVoices, hasLength(scheduledBeforeStop - 1),
          reason: '只有尚未发声的拍被 stop(拍0 已响)');
      expect(engine.scheduleLog.first.stopped, isFalse, reason: '拍0 已响不 stop');

      final countAfterStop = engine.scheduleLog.length;
      for (var i = 0; i < 10; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(engine.scheduleLog, hasLength(countAfterStop), reason: '停止后不再调度');
    });
  });

  test('totalBeats 有界:走出最后一拍不再预定(曲末无幻拍声)', () {
    fakeAsync((async) {
      final scheduler = BeatScheduler(
        engine: engine,
        pickSound: (beat) => beat % 4 == 0 ? strong : weak,
      );
      // 曲长 4 拍(500ms/拍):10 秒远超曲末,窗内也只到拍 3 为止。
      scheduler.start(bpm: 120, totalBeats: 4);
      for (var i = 0; i < 250; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(scheduler.scheduledCount, 4, reason: '只预定拍 0..3');
      expect(engine.scheduleLog.map((c) => c.time).toList(), [
        Duration.zero,
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 1000),
        const Duration(milliseconds: 1500),
      ]);
    });
  });

  test('引擎预定抛错:上报 onError 并自停', () {
    fakeAsync((async) {
      final broken = BrokenPlayEngine();
      final errors = <Object>[];
      final scheduler = BeatScheduler(
        engine: broken,
        pickSound: (beat) => strong,
        onError: errors.add,
      );
      scheduler.start(bpm: 120);
      expect(errors, hasLength(1), reason: 'start 即时首过即抛');
      expect(scheduler.running, isFalse, reason: '出错自停,不留半死定时器');
      // 定时器已取消:推进时间不再报错。
      engine.advance(const Duration(milliseconds: 40));
      async.elapse(const Duration(milliseconds: 40));
      expect(errors, hasLength(1));
    });
  });
}

class BrokenPlayEngine extends FakeAudioEngine {
  @override
  EngineVoice playClocked(EngineSound sound, Duration when) =>
      throw Exception('引擎预定失败(注入)');
}
