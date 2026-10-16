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
      scheduler.start(periodMs: 500);
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
      scheduler.start(periodMs: 500);
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

  test('运行中 changePeriod:之后拍距变为新周期,无重复拍号', () {
    fakeAsync((async) {
      final scheduler = BeatScheduler(
        engine: engine,
        pickSound: (beat) => beat % 4 == 0 ? strong : weak,
      );
      scheduler.start(periodMs: 500);
      for (var i = 0; i < 50; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      // now=2s:已预定拍 0..4(500×5=2500 > 2400 未到)→ nextBeat=5。
      expect(scheduler.scheduledCount, 5);
      scheduler.changePeriod(60000 / 90);
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

  test('大跨度变速 40→208:已排队未响拍按新网格重排,不倒挂', () {
    fakeAsync((async) {
      final scheduler = BeatScheduler(
        engine: engine,
        pickSound: (beat) => beat % 4 == 0 ? strong : weak,
      );
      // 40BPM(1500ms/拍)跑到 now=1120ms:拍 1(1500ms)已排队未响
      // (1120+400=1520 ≥ 1500),拍 2(3000ms)未到。
      scheduler.start(periodMs: 1500);
      for (var i = 0; i < 28; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(scheduler.scheduledCount, 2);

      // 换 208BPM(288.46ms/拍):elapsed=0.747 拍 → 新 t0 = 1120−215 = 905ms。
      // 旧拍 1(排队在 1500ms)须停掉并按新网格重排到 905+288=1193ms;
      // 若不重排,新网格拍 2(1482ms)会先于旧拍 1(1500ms)响——倒挂。
      scheduler.changePeriod(60000 / 208);
      // 旧拍 1 的原预定被取消。
      final oldBeat1 = engine.scheduleLog
          .lastWhere((c) => c.time == const Duration(milliseconds: 1500));
      expect(oldBeat1.stopped, isTrue, reason: '已排队未响的旧拍 1 停掉');
      // 拍 1 按新网格重排,拍 2 在其后:时刻严格递增,无倒挂。
      expect(engine.scheduleLog[2].time.inMilliseconds, 1193, reason: 'now+73ms(剩余相位×新周期)');
      expect(engine.scheduleLog[2].stopped, isFalse);
      expect(engine.scheduleLog[3].time.inMilliseconds, 1482, reason: '905+round(2×288.46)');
      final live = engine.scheduleLog.where((c) => !c.stopped).map((c) => c.time).toList();
      for (var i = 1; i < live.length; i++) {
        expect(live[i], greaterThan(live[i - 1]), reason: '未停预定时刻单调 $i');
      }
      expect(scheduler.scheduledCount, 3);

      // 新网格继续:拍 3(905+round(3×288.46)=1770ms)在其取整时刻照常入窗。
      for (var i = 0; i < 7; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(engine.scheduleLog.last.time, const Duration(milliseconds: 1770));
    });
  });

  test('stop:未响拍全部停止,已响拍不动;之后不再调度', () {
    fakeAsync((async) {
      final scheduler = BeatScheduler(
        engine: engine,
        pickSound: (beat) => beat % 4 == 0 ? strong : weak,
      );
      scheduler.start(periodMs: 500);
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
      scheduler.start(periodMs: 500, totalBeats: 4);
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

  test('start/changePeriod 非正拍周期:ArgumentError,运行状态不受扰动', () {
    fakeAsync((async) {
      final scheduler = BeatScheduler(
        engine: engine,
        pickSound: (beat) => beat % 4 == 0 ? strong : weak,
      );
      // 未运行也不静默吞掉:非法入参即抛(控制器钳制是它的职责,公共缝
      // 自守——负值曾使 scheduleDue 死循环)。
      expect(() => scheduler.start(periodMs: 0), throwsArgumentError);
      expect(() => scheduler.start(periodMs: -5), throwsArgumentError);
      expect(scheduler.running, isFalse);

      scheduler.start(periodMs: 500);
      expect(scheduler.running, isTrue);
      expect(() => scheduler.changePeriod(0), throwsArgumentError);
      expect(() => scheduler.changePeriod(-1), throwsArgumentError);
      expect(scheduler.running, isTrue, reason: '非法变速不扰动运行中的网格');
      // 网格未被扰动:拍 1 仍按 500ms 网格预定。
      engine.advance(const Duration(milliseconds: 460));
      async.elapse(const Duration(milliseconds: 460));
      expect(engine.scheduleLog[1].time, const Duration(milliseconds: 500));
      expect(scheduler.scheduledCount, 2);
    });
  });

  test('锚点重建(暂停恢复):t0 在过去+nextBeat 起步,已响拍不重放', () {
    fakeAsync((async) {
      final scheduler = BeatScheduler(
        engine: engine,
        pickSound: (beat) => beat % 4 == 0 ? strong : weak,
      );
      // 暂停现场:500ms 网格跑到 elapsed=1800ms(拍 0..3 已响,拍 4 在
      // 2000ms 未到),暂停期间引擎时钟照走 100ms。
      scheduler.start(periodMs: 500);
      for (var i = 0; i < 45; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(engine.engineTime(), const Duration(milliseconds: 1800));
      scheduler.stop(); // 引擎侧暂停:停调度、停未响拍
      final logBefore = engine.scheduleLog.length;

      // 恢复:now'=1900,t0' = 1900−1800 = 100ms,nextBeat = ceil(3.6) = 4。
      engine.advance(const Duration(milliseconds: 100));
      final resumed = BeatScheduler(
        engine: engine,
        pickSound: (beat) => beat % 4 == 0 ? strong : weak,
      );
      resumed.start(
        periodMs: 500,
        t0: engine.engineTime() - const Duration(milliseconds: 1800),
        nextBeat: 4,
      );
      // 已响的拍 0..3 不重放;拍 4 在新锚点上 100+2000 = 2100ms 入窗。
      final resumedEntries = engine.scheduleLog.sublist(logBefore);
      expect(resumedEntries, hasLength(1));
      expect(resumedEntries.single.time, const Duration(milliseconds: 2100));
      expect(resumedEntries.single.key, 'tick_strong', reason: '拍 4 强拍');
      expect(resumed.scheduledCount, 5);
      // 继续跑:拍 5@2600、拍 6@3100 依次按新网格入窗。
      for (var i = 0; i < 20; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(resumed.scheduledCount, 7, reason: 'now=2700,窗右沿 3100:拍 6 恰入');
    });
  });

  test('锚点重建:恰在拍点恢复,该拍立即入窗(未响过,须补响)', () {
    fakeAsync((async) {
      // 恰在拍 4 网格点(elapsed=2000)暂停并立即恢复:t0' = −2000,
      // 拍 4 落在引擎时刻 0(== now),迟到 0ms 在容差内,立即预定。
      final resumed = BeatScheduler(
        engine: engine,
        pickSound: (beat) => beat % 4 == 0 ? strong : weak,
      );
      resumed.start(
        periodMs: 500,
        t0: engine.engineTime() - const Duration(milliseconds: 2000),
        nextBeat: 4,
      );
      expect(engine.scheduleLog, hasLength(1));
      expect(engine.scheduleLog.single.time, Duration.zero);
      expect(engine.scheduleLog.single.key, 'tick_strong');
    });
  });

  test('错误恢复:引擎 stop 也失败时不掩盖原错误,onError 照达、状态清干净', () {
    fakeAsync((async) {
      final halfBroken = HalfBrokenEngine();
      final errors = <Object>[];
      final scheduler = BeatScheduler(
        engine: halfBroken,
        pickSound: (beat) => weak,
        onError: errors.add,
      );
      // 208BPM:拍 5(@1442ms)是第 6 次 playClocked,注入失败;此刻拍 4
      // (@1154ms)仍在途——恢复路径若直接调 stop(),会在它的引擎调用上
      // 再抛,掩盖原错误且 onError 不达。
      scheduler.start(periodMs: 60000 / 208);
      for (var i = 0; i < 27; i++) {
        halfBroken.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(errors, hasLength(1), reason: '上报的是原错误(预定失败),非 stop 的次生错误');
      expect(errors.first.toString(), contains('引擎预定失败'));
      expect(scheduler.running, isFalse, reason: '出错自停,不留半死定时器');
      expect(scheduler.scheduledCount, 0, reason: '调度状态清干净,无残留');
      // 定时器已取消:推进时间不再报错。
      halfBroken.advance(const Duration(milliseconds: 40));
      async.elapse(const Duration(milliseconds: 40));
      expect(errors, hasLength(1));
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
      scheduler.start(periodMs: 500);
      expect(errors, hasLength(1), reason: 'start 即时首过即抛');
      expect(scheduler.running, isFalse, reason: '出错自停,不留半死定时器');
      // 定时器已取消:推进时间不再报错。
      engine.advance(const Duration(milliseconds: 40));
      async.elapse(const Duration(milliseconds: 40));
      expect(errors, hasLength(1));
    });
  });

  test('stop 清理容错:时钟不可读仍全量取消待发声,不外抛(审计30 #3)', () {
    fakeAsync((async) {
      final scheduler = BeatScheduler(
        engine: engine,
        pickSound: (beat) => strong,
      );
      scheduler.start(periodMs: 500);
      for (var i = 0; i < 3; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      engine.failClock = true;
      expect(scheduler.stop, returnsNormally, reason: '时钟读不出不得让停机外抛');
      expect(scheduler.running, isFalse);
      final stopped = engine.scheduleLog.where((c) => c.stopped);
      expect(
        stopped,
        isNotEmpty,
        reason: '读不出时刻 = 全量取消(已响 voice 的 stop 是无害空操作)',
      );
    });
  });

  test('stop 清理容错:单个取消失败不中断其余取消、不外抛(审计30 #3)', () {
    fakeAsync((async) {
      final scheduler = BeatScheduler(
        engine: engine,
        pickSound: (beat) => strong,
      );
      scheduler.start(periodMs: 500);
      for (var i = 0; i < 3; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      engine.failStop = true;
      expect(scheduler.stop, returnsNormally, reason: '取消失败不得让停机外抛');
      expect(scheduler.running, isFalse, reason: '本地状态先行清空,引擎失败不残留');
    });
  });
}

class BrokenPlayEngine extends FakeAudioEngine {
  @override
  EngineVoice playClocked(EngineSound sound, Duration when) =>
      throw Exception('引擎预定失败(注入)');
}

/// 预定前 5 次成功、此后必失败,且 stop 一律失败:制造「失败时有在途
/// 预定 + 恢复路径引擎调用必抛」的现场。
class HalfBrokenEngine extends FakeAudioEngine {
  int _playCalls = 0;

  @override
  EngineVoice playClocked(EngineSound sound, Duration when) {
    _playCalls++;
    if (_playCalls > 5) throw Exception('引擎预定失败(注入)');
    return super.playClocked(sound, when);
  }

  @override
  void stop(EngineVoice voice) => throw Exception('引擎停止失败(注入)');
}
