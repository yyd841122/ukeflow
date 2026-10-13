import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/audio_engine.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/model/strum_pattern.dart' show StrumDirection;
import 'package:ukeflow/core/practice/play_timeline.dart';
import 'package:ukeflow/features/play/strum_scheduler.dart';

/// 示范扫弦声调度器(工单 10 参考音=扫弦):时间轴扫弦事件 → 引擎
/// playClocked 预定。纪律与 BeatScheduler 相同:40ms 轮询 + 400ms
/// 提前量 + 40ms 迟到容差,时刻只读引擎时钟(ADR-0005)。
void main() {
  late FakeAudioEngine engine;
  late EngineSound str4;
  late EngineSound str3;
  late EngineSound str2;
  late EngineSound str1;

  /// 和弦 → 弦音表(4 弦→1 弦序,音源名即弦位):C 的 4 弦闷音、
  /// G 的 1 弦闷音;其余和弦名查不到 → null(降级静默)。
  /// 方向不参与定声(既有形状断言依赖)。
  List<EngineSound?>? Function(String, StrumDirection) resolver() => (chord, _) =>
      switch (chord) {
        'C' => [null, str3, str2, str1],
        'G' => [str4, str3, str2, null],
        _ => null,
      };

  /// 三事件时间轴:t=0 C 下扫、t=500 G 上扫、t=1000 无名扫弦(和弦库
  /// 查不到的降级路径)。
  List<PlayStrumEvent> strums() => [
        PlayStrumEvent(
          time: Duration.zero,
          barIndex: 0,
          slotInBar: 0,
          direction: StrumDirection.down,
          chord: 'C',
        ),
        PlayStrumEvent(
          time: const Duration(milliseconds: 500),
          barIndex: 0,
          slotInBar: 4,
          direction: StrumDirection.up,
          chord: 'G',
        ),
        PlayStrumEvent(
          time: const Duration(milliseconds: 1000),
          barIndex: 1,
          slotInBar: 0,
          direction: StrumDirection.down,
          chord: null,
        ),
      ];

  setUp(() async {
    engine = FakeAudioEngine();
    str4 = await engine.loadMem('string4', Uint8List(0));
    str3 = await engine.loadMem('string3', Uint8List(0));
    str2 = await engine.loadMem('string2', Uint8List(0));
    str1 = await engine.loadMem('string1', Uint8List(0));
  });

  test('start 立即首过:窗内事件按 t0+event.time 预定,方向定弦序、45ms 错峰', () {
    fakeAsync((async) {
      final scheduler = StrumScheduler(
        engine: engine,
        strums: strums(),
        pickStrings: resolver(),
      );
      // 锚点 0、引擎已走到 450ms:t=0 的事件过期 450ms(超容差)→ 越过
      // 不回放;t=500 的事件在窗 [410, 850] 内 → 立即预定。上扫弦序
      // 反转:1 弦(闷音,占 500ms 时位不发声)先「扫过」,2/3/4 弦在
      // 545/590/635ms 依次发声。
      engine.now = const Duration(milliseconds: 450);
      scheduler.start(t0: Duration.zero);

      expect(engine.scheduleLog.map((c) => c.key).toList(),
          ['string2', 'string3', 'string4'], reason: '上扫 1→4,闷音 1 弦占时位');
      expect(engine.scheduleLog.map((c) => c.time).toList(), [
        const Duration(milliseconds: 545),
        const Duration(milliseconds: 590),
        const Duration(milliseconds: 635),
      ]);
      expect(scheduler.scheduledCount, 2, reason: 't=0 事件越过,t=500 已预定');
    });
  });

  test('40ms 步进:后续事件按时刻依次入窗,下扫 4 弦先扫过', () {
    fakeAsync((async) {
      final scheduler = StrumScheduler(
        engine: engine,
        strums: strums(),
        pickStrings: resolver(),
      );
      scheduler.start(t0: Duration.zero);
      // now=0:t=0 的 C 下扫立即入窗;4 弦闷音占 0ms 时位,3/2/1 弦在
      // 45/90/135ms 依次发声;窗右沿 400ms 内无更多事件。
      expect(engine.scheduleLog.map((c) => c.key).toList(),
          ['string3', 'string2', 'string1'], reason: '下扫 4→1,闷音 4 弦占时位');
      expect(engine.scheduleLog.map((c) => c.time).toList(), [
        const Duration(milliseconds: 45),
        const Duration(milliseconds: 90),
        const Duration(milliseconds: 135),
      ]);

      for (var i = 0; i < 13; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      // now=520:窗 [480, 920] → t=500 的 G 上扫已入窗(3 弦发声)。
      expect(
        engine.scheduleLog.where((c) => c.time.inMilliseconds >= 500),
        hasLength(3),
      );
      // t=1000 的事件和弦无名 → 静默,但推进不卡死。
      for (var i = 0; i < 15; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(scheduler.scheduledCount, 3, reason: '三事件全部越过(末事件无声)');
      final liveTimes = engine.scheduleLog.map((c) => c.time).toList();
      expect(liveTimes, liveTimes.toSet().toList(), reason: '无重复预定');
    });
  });

  test('stop:未响预定停止;停止后不再调度', () {
    fakeAsync((async) {
      final scheduler = StrumScheduler(
        engine: engine,
        strums: strums(),
        pickStrings: resolver(),
      );
      scheduler.start(t0: Duration.zero);
      // now=0:C 下扫 3 弦在 45/90/135ms,全部未响。
      expect(engine.scheduleLog, hasLength(3));

      scheduler.stop();
      expect(scheduler.running, isFalse);
      expect(
        engine.scheduleLog.where((c) => c.stopped).map((c) => c.time),
        [
          const Duration(milliseconds: 45),
          const Duration(milliseconds: 90),
          const Duration(milliseconds: 135),
        ],
        reason: '未响的弦全部 stop',
      );

      final countAfterStop = engine.scheduleLog.length;
      for (var i = 0; i < 40; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(engine.scheduleLog, hasLength(countAfterStop), reason: '停止后不再调度');
    });
  });

  test('曲末:事件走完不再预定,长跑不积内存', () {
    fakeAsync((async) {
      final scheduler = StrumScheduler(
        engine: engine,
        strums: strums(),
        pickStrings: resolver(),
      );
      scheduler.start(t0: Duration.zero);
      for (var i = 0; i < 60; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(scheduler.scheduledCount, 3);
      final countAtEnd = engine.scheduleLog.length;
      for (var i = 0; i < 50; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(engine.scheduleLog, hasLength(countAtEnd), reason: '曲末无幻扫');
    });
  });

  test('引擎出错:onError 上报并自停,状态清干净', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final broken = BrokenEngine();
      final sound = broken.loadMemSync('string1');
      final scheduler = StrumScheduler(
        engine: broken,
        strums: strums(),
        pickStrings: (_, _) => [sound],
        onError: errors.add,
      );
      scheduler.start(t0: Duration.zero);
      expect(errors, hasLength(1), reason: '首过即抛,上报原错误');
      expect(scheduler.running, isFalse, reason: '出错自停');
      expect(scheduler.scheduledCount, 0, reason: '调度状态清干净');
    });
  });

  test('定声缝收方向:每事件的扫弦方向原样传入,两方向可定不同音源', () {
    fakeAsync((async) {
      final seen = <(String, StrumDirection)>[];
      EngineSound strumSound(StrumDirection direction) =>
          direction == StrumDirection.down ? str1 : str2;
      final scheduler = StrumScheduler(
        engine: engine,
        strums: strums(), // t=0 C 下扫、t=500 G 上扫、t=1000 无名(不过缝)
        pickStrings: (chord, direction) {
          seen.add((chord, direction));
          return switch (chord) {
            'C' => [null, null, null, strumSound(direction)],
            'G' => [null, null, null, strumSound(direction)],
            _ => null,
          };
        },
      );
      scheduler.start(t0: Duration.zero);
      // t=0 C 下扫立即入窗:单弦发声(4 弦位),1 弦音源@45ms。
      expect(engine.scheduleLog.map((c) => c.key).toList(), ['string1']);
      expect(seen, [('C', StrumDirection.down)]);

      for (var i = 0; i < 14; i++) {
        engine.advance(const Duration(milliseconds: 40));
        async.elapse(const Duration(milliseconds: 40));
      }
      // now=560:t=500 的 G 上扫入窗——拿到的是上扫方向与上扫音源。
      expect(seen, [('C', StrumDirection.down), ('G', StrumDirection.up)]);
      expect(
        engine.scheduleLog.where((c) => c.time.inMilliseconds >= 500).map((c) => c.key),
        ['string2'],
        reason: '上扫事件定到上扫音源——音色区分经此缝成立',
      );
    });
  });
}

class BrokenEngine extends FakeAudioEngine {
  @override
  EngineVoice playClocked(EngineSound sound, Duration when) =>
      throw Exception('引擎预定失败(注入)');

  EngineSound loadMemSync(String key) => FakeSound(key);
}
