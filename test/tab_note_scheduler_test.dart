import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/audio_engine.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/practice/tab_timeline.dart';
import 'package:ukeflow/features/play/tab_note_scheduler.dart';

/// 逐音示范声调度器(工单 13):时间轴单音事件 → 引擎 playClocked
/// 预定拨弦。纪律与 BeatScheduler/StrumScheduler 相同:40ms 轮询 +
/// 400ms 提前量 + 40ms 迟到容差,时刻只读引擎时钟(ADR-0005)。
void main() {
  late FakeAudioEngine engine;
  late EngineSound pluckC5;
  late EngineSound pluckA4;
  late EngineSound pluckE5;

  /// 音高 → 音源(440 给 A4、659.25 给 E5,其余给 C5;null 模拟音源
  /// 缺位降级)。
  EngineSound? Function(TabNoteEvent) resolver() =>
      (note) => switch (note) {
        TabNoteEvent(frequency: 440.0) => pluckA4,
        TabNoteEvent(frequency: 659.25) => pluckE5,
        _ => pluckC5,
      };

  /// 三音时间轴:t=0、t=500、t=1250ms(半拍音钉非整除边界)。
  List<TabNoteEvent> notes() => [
    TabNoteEvent(time: Duration.zero, string: 1, fret: 3, frequency: 523.25),
    TabNoteEvent(
      time: const Duration(milliseconds: 500),
      string: 1,
      fret: 0,
      frequency: 440.0,
    ),
    TabNoteEvent(
      time: const Duration(milliseconds: 1250),
      string: 2,
      fret: 3,
      frequency: 659.25,
    ),
  ];

  setUp(() async {
    engine = FakeAudioEngine();
    pluckC5 = await engine.loadMem('pluck_523.25_1500', Uint8List(0));
    pluckA4 = await engine.loadMem('pluck_440.0_1500', Uint8List(0));
    pluckE5 = await engine.loadMem('pluck_659.25_1500', Uint8List(0));
  });

  test('start 立即首过:窗内事件按 t0+event.time 预定,过期事件越过不回放', () {
    fakeAsync((async) {
      final scheduler = TabNoteScheduler(
        engine: engine,
        notes: notes(),
        pickSound: resolver(),
      );
      // 锚点 0、引擎已走到 450ms:t=0 过期 450ms(超容差)→ 越过;
      // t=500 在窗 [410, 850] 内 → 立即预定。
      engine.now = const Duration(milliseconds: 450);
      scheduler.start(t0: Duration.zero);

      expect(engine.scheduleLog.map((c) => c.key), ['pluck_440.0_1500']);
      expect(engine.scheduleLog.single.time, const Duration(milliseconds: 500));
      expect(scheduler.scheduledCount, 2, reason: 't=0 越过,t=500 已预定');
    });
  });

  test('40ms 步进:后续事件按时刻依次入窗', () {
    fakeAsync((async) {
      final scheduler = TabNoteScheduler(
        engine: engine,
        notes: notes(),
        pickSound: resolver(),
      );
      scheduler.start(t0: Duration.zero);
      expect(
        engine.scheduleLog.single.key,
        'pluck_523.25_1500',
        reason: '首过只有 t=0',
      );

      engine.advance(const Duration(milliseconds: 460));
      async.elapse(const Duration(milliseconds: 40));
      expect(engine.scheduleLog.map((c) => c.key).toList(), [
        'pluck_523.25_1500',
        'pluck_440.0_1500',
      ]);
      expect(engine.scheduleLog.last.time, const Duration(milliseconds: 500));

      engine.advance(const Duration(milliseconds: 400));
      async.elapse(const Duration(milliseconds: 80));
      expect(
        engine.scheduleLog.last.key,
        'pluck_659.25_1500',
        reason: 't=1250 半拍音按事件时刻预定',
      );
      expect(engine.scheduleLog.last.time, const Duration(milliseconds: 1250));
      expect(scheduler.scheduledCount, 3, reason: '全部事件已预定,曲末无幻声');
    });
  });

  test('stop:未发声的预定停掉,轮询取消', () {
    fakeAsync((async) {
      final scheduler = TabNoteScheduler(
        engine: engine,
        notes: notes(),
        pickSound: resolver(),
      );
      scheduler.start(t0: Duration.zero);
      expect(engine.scheduleLog, hasLength(1));

      engine.advance(const Duration(milliseconds: 460));
      async.elapse(const Duration(milliseconds: 40)); // t=500 已预定未响
      expect(engine.scheduleLog, hasLength(2));

      scheduler.stop();
      expect(scheduler.running, isFalse);
      expect(
        engine.scheduleLog
            .where((c) => c.key == 'pluck_440.0_1500')
            .every((c) => c.stopped),
        isTrue,
        reason: '未响的预定被 stop',
      );

      engine.advance(const Duration(seconds: 2));
      async.elapse(const Duration(milliseconds: 200));
      expect(engine.scheduleLog, hasLength(2), reason: '停后不再预定');
    });
  });

  test('音源缺位(pickSound null):事件静默越过,不抛错', () {
    fakeAsync((async) {
      final scheduler = TabNoteScheduler(
        engine: engine,
        notes: notes(),
        pickSound: (_) => null,
      );
      scheduler.start(t0: Duration.zero);
      engine.advance(const Duration(milliseconds: 1400));
      async.elapse(const Duration(milliseconds: 100));
      expect(engine.scheduleLog, isEmpty);
      expect(scheduler.scheduledCount, 3, reason: '事件照常推进,只是无声');
    });
  });

  test('引擎预定出错:onError 必达,调度器停机、在途清空', () {
    fakeAsync((async) {
      Object? reported;
      final scheduler = TabNoteScheduler(
        engine: engine,
        notes: notes(),
        pickSound: resolver(),
        onError: (e) => reported = e,
      );
      scheduler.start(t0: Duration.zero);
      engine.failNow = true;
      engine.advance(const Duration(milliseconds: 460));
      async.elapse(const Duration(milliseconds: 40));
      expect(reported, isNotNull, reason: '错误原样上报');
      expect(scheduler.running, isFalse, reason: '出错即停机');
    });
  });

  test('consumedUntil 截止线:迟到窗内已消费音不重放(审计30 #39)', () {
    fakeAsync((async) {
      // 曲头锚 0:推进到 520(音 500 已由旧调度器消费,在迟到窗内)。
      final now = const Duration(milliseconds: 520);
      final consumed = TabNoteScheduler(
        engine: engine,
        notes: notes(),
        pickSound: resolver(),
      )..start(t0: Duration.zero, consumedUntil: now);
      expect(consumed.scheduledCount, 2, reason: '音 0/500 已消费,越过');
      expect(
        engine.scheduleLog
            .where((e) => e.time.inMilliseconds >= 480 && e.time.inMilliseconds <= 520),
        isEmpty,
        reason: '迟到窗内已消费音不重排',
      );
      consumed.stop();
    });
  });

}
