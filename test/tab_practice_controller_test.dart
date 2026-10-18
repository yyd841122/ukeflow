import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/audio_engine.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/model/tab_chart.dart';
import 'package:ukeflow/core/practice/tab_practice_state.dart';
import 'package:ukeflow/features/play/tab_practice_controller.dart';

import 'helpers/chart_fixtures.dart';

/// 指弹跟练控制器:接缝在 TabSessionState 与公开方法;
/// 引擎一律注入 FakeAudioEngine(不碰真引擎)。
/// 与弹唱跟练控制器的差别:无节奏型、无参考音切换——KS 逐音示范声
/// 就是参考声,正曲拍静默(工单 13)。
void main() {
  late FakeAudioEngine engine;
  late ProviderContainer container;

  TabPracticeController controller() =>
      container.read(tabPracticeProvider.notifier);

  /// 拨弦音源键(PluckPlayer 缓存键格式 'pluck_音高_时长',音高来自
  /// 模型频率,独立于控制器内部换算)。
  String pluckKey(double frequency) => 'pluck_${frequency}_1500';

  setUp(() {
    engine = FakeAudioEngine();
    container = ProviderContainer(
      overrides: [audioEngineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);
  });

  test('初始态:BPM 80、原速、未就绪未运行', () {
    final state = container.read(tabPracticeProvider);
    expect(state.bpm, TabPracticeController.defaultBpm);
    expect(state.speed, 1.0);
    expect(state.engineReady, isFalse);
    expect(state.running, isFalse);
    expect(state.paused, isFalse);
    expect(state.error, isNull);
  });

  test('warmup:只注入预备拍音源(正曲拍静默,无强弱拍 tick)', () async {
    await controller().warmup();
    final state = container.read(tabPracticeProvider);
    expect(state.engineReady, isTrue);
    expect(engine.loadedKeys, contains('tick_count'));
    expect(
      engine.loadedKeys.where((k) => k == 'tick_strong' || k == 'tick_weak'),
      isEmpty,
      reason: '指弹跟练正曲拍无 tick,强弱拍音源不注入',
    );
  });

  test('prepareFor:取谱面 tempo 为当前 BPM(钳制),变速回原速,拨弦音源预注入', () async {
    final c = controller();
    c.setBpm(95);
    c.setSpeed(0.6);
    c.prepareFor(tabFixtureChart);
    final state = container.read(tabPracticeProvider);
    expect(state.bpm, 80, reason: '谱面 tempo');
    expect(state.speed, 1.0, reason: '每首谱都从原速起');
    expect(engine.loadedKeys, isEmpty, reason: '拨弦注入是异步在途,此刻不保证完成');

    c.prepareFor(
      const TabChart(
        title: '慢速谱',
        tempo: 10,
        notes: [TabNote(string: 1, fret: 0, beat: 0)],
      ),
    );
    expect(container.read(tabPracticeProvider).bpm, 40, reason: '钳制下限');

    // 预注入完成:全曲唯一音高的拨弦音源都进了引擎。
    await Future<void>.delayed(Duration.zero);
    final freqs = tabFixtureChart.notes.map((n) => n.frequency).toSet();
    for (final freq in freqs) {
      expect(
        engine.loadedKeys,
        contains(pluckKey(freq)),
        reason: '全曲音源起跑前注入到位(调度期免 await)',
      );
    }
  });

  test('start:预备数拍起跑,锚点在预备 4 拍后,时间轴按当前 BPM 编译', () async {
    final c = controller();
    await c.warmup();
    engine.advance(const Duration(milliseconds: 700));
    c.start(chart: tabFixtureChart);

    final state = container.read(tabPracticeProvider);
    expect(state.running, isTrue);
    final timeline = c.timeline;
    expect(timeline, isNotNull);
    expect(timeline!.periodMs, closeTo(750, 1e-9), reason: '60000/80');
    expect(timeline.totalBeats, 4);
    final anchor = c.visualAnchor!;
    expect(
      anchor.t0,
      const Duration(milliseconds: 700 + 4 * 750),
      reason: '曲头锚在预备 4 拍之后',
    );
    expect(engine.scheduleLog.single.key, 'tick_count');
    expect(engine.scheduleLog.single.time, const Duration(milliseconds: 700));
  });

  test('示范声与高亮同刻:首音预定时刻 = 高亮翻转时刻(同一份时间轴)', () async {
    final c = controller();
    c.prepareFor(tabFixtureChart);
    await c.warmup(); // warmup 等全曲拨弦音源注入完成,开始键才可用
    fakeAsync((async) {
      engine.advance(const Duration(milliseconds: 700));
      c.start(chart: tabFixtureChart);
      expect(
        engine.scheduleLog.where((e) => e.key.startsWith('pluck_')),
        isEmpty,
        reason: '启动窗内只有预备拍:首音在曲头锚,远在 400ms 提前量外',
      );

      // 引擎走到 3400:曲头 3700 进入窗(3400+400),首音即刻预定。
      engine.advance(const Duration(milliseconds: 2700));
      async.elapse(const Duration(milliseconds: 40));
      final anchor = c.visualAnchor!;
      final plucks = engine.scheduleLog
          .where((e) => e.key.startsWith('pluck_'))
          .toList();
      expect(plucks, hasLength(1));
      expect(plucks.single.time, anchor.t0, reason: '首音预定在曲头锚那一毫秒');
      expect(
        plucks.single.key,
        pluckKey(tabFixtureChart.notes.first.frequency),
      );

      // 同一刻查询练习状态:高亮恰翻第 0 音(示范声与高亮同刻的结构验证)。
      final firstNoteNow = anchor.t0 + c.timeline!.notes.first.time;
      final visual = tabPracticeStateAt(
        timeline: c.timeline!,
        t0: anchor.t0,
        now: firstNoteNow,
      );
      expect(visual!.currentNoteIndex, 0);
    });
  });

  test('正曲拍静默:整曲走完只有预备 tick 与逐音拨弦,无强弱拍 tick', () async {
    final c = controller();
    c.prepareFor(tabFixtureChart);
    await c.warmup(); // 预备拍音源+全曲拨弦音源一并就绪(真实 zone)
    fakeAsync((async) {
      engine.advance(const Duration(milliseconds: 700));
      c.start(chart: tabFixtureChart);
      // 预备 3 秒 + 全曲 3 秒:分步推进喂轮询(7200ms > 3700+3000)。
      for (var i = 0; i < 20; i++) {
        engine.advance(const Duration(milliseconds: 350));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(
        engine.scheduleLog.where(
          (e) => e.key.startsWith('tick_') && e.key != 'tick_count',
        ),
        isEmpty,
        reason: '正曲拍静默:KS 逐音示范声即参考声',
      );
      final plucks = engine.scheduleLog
          .where((e) => e.key.startsWith('pluck_'))
          .toList();
      expect(plucks, hasLength(4), reason: '全曲 4 音各一声');
      expect(
        plucks.map((e) => e.time.inMilliseconds).toList(),
        [3700, 4450, 5575, 5950],
        reason: '逐音按事件时刻预定(0/750/1875/2250 + 曲头锚 3700)',
      );
    });
  });

  test('prepStateNow:预备期倒计,锚在调度 t0(与页面同式)', () async {
    final c = controller();
    c.prepareFor(tabFixtureChart);
    await c.warmup();
    engine.advance(const Duration(milliseconds: 700));
    c.start(chart: tabFixtureChart);

    // 80BPM:750ms/拍,预备窗 [700, 3700)。启动瞬间在预备第 1 拍。
    expect(c.prepStateNow()!.count, 4);
    // 正曲逐音状态在预备期不可得(页面据此切倒计面板)。
    expect(
      tabPracticeStateAt(
        timeline: c.timeline!,
        t0: c.visualAnchor!.t0,
        now: c.visualNow()!,
      ),
      isNull,
    );
    // 预备期重复 start 不重启、不重铺预备拍。
    final logBefore = engine.scheduleLog.length;
    c.start(chart: tabFixtureChart);
    expect(engine.scheduleLog, hasLength(logBefore));
  });

  group('工单 13:暂停/继续/回到开头', () {
    test('pause:在途拨弦停净、视觉时钟冻结;会话与时间轴保留', () async {
      final c = controller();
      c.prepareFor(tabFixtureChart);
      await c.warmup();
      fakeAsync((async) {
        engine.advance(const Duration(milliseconds: 700));
        c.start(chart: tabFixtureChart);
        // 曲头前停(预备第 2 拍中段):此刻无在途拨弦,只有预备拍在途。
        engine.advance(const Duration(milliseconds: 1000));
        c.pause();
        final state = container.read(tabPracticeProvider);
        expect(state.paused, isTrue);
        expect(state.running, isTrue, reason: '暂停仍在会话内');
        expect(c.timeline, isNotNull);

        final frozen = c.visualNow()!;
        engine.advance(const Duration(seconds: 5));
        expect(c.visualNow()!, frozen, reason: '视觉时钟冻结,不随引擎走');
        expect(
          c.prepStateNow()!.count,
          3,
          reason: '倒计一并冻结(1000ms ∈ [750,1500))',
        );

        c.resume();
        expect(container.read(tabPracticeProvider).paused, isFalse);
        expect(c.prepStateNow()!.count, 3, reason: '恢复从同一预备拍继续,不跳拍不重数');
        // 恢复重锚:t0' = 引擎当前 6700 − 冻结逝时 1000 = 5700(暂停的
        // 5 秒墙钟被丢弃),曲头锚随之顺移。
        final anchor = c.visualAnchor!;
        expect(anchor.t0, const Duration(milliseconds: 6700 - 1000 + 3000));
      });
    });

    test('pause 在曲中:已预定未响的音停掉;恢复不重放已响音', () async {
      final c = controller();
      c.prepareFor(tabFixtureChart);
      await c.warmup();
      fakeAsync((async) {
        engine.advance(const Duration(milliseconds: 700));
        c.start(chart: tabFixtureChart);
        // 分步推进到曲内 4600ms(绝对 5300):前两音已过,三音(5575)
        // 已预定未响(fake 环境轮询只随 elapse 跑,须步进喂窗)。
        for (var i = 0; i < 13; i++) {
          engine.advance(const Duration(milliseconds: 350));
          async.elapse(const Duration(milliseconds: 40));
        }
        final plucks = engine.scheduleLog
            .where((e) => e.key.startsWith('pluck_'))
            .toList();
        expect(
          plucks.map((e) => (e.time.inMilliseconds, e.stopped)).toList(),
          [(3700, false), (4450, false), (5575, false)],
          reason: '暂停前:两音已响、三音已预定未响',
        );

        c.pause();
        expect(plucks[2].stopped, isTrue, reason: '未响的预定停掉');
        expect(plucks[0].stopped, isFalse, reason: '已响的不动');
        expect(plucks[1].stopped, isFalse, reason: '已响的不动');

        c.resume(); // 立即恢复:重锚 t0' = 5300 − 4600 = 700,曲头锚 3700 不变
        expect(c.visualAnchor!.t0, const Duration(milliseconds: 3700));
        // 恢复首过:已响音过期越过,5575 在窗重排(新 voice,未停)。
        final resumed = engine.scheduleLog
            .where(
              (e) =>
                  e.key.startsWith('pluck_') &&
                  e.time == const Duration(milliseconds: 5575),
            )
            .toList();
        expect(resumed, hasLength(2), reason: '原预定已停,恢复重排一声');
        expect(resumed.last.stopped, isFalse);
      });
    });

    test('restart:旧在途停净,新会话重新预备数拍', () async {
      final c = controller();
      c.prepareFor(tabFixtureChart);
      c.setBpm(208); // 拍周期 288ms:启动首过窗含预备拍 0、1,重启时有在途未响拍
      await c.warmup();
      fakeAsync((async) {
        engine.advance(const Duration(milliseconds: 100));
        c.start(chart: tabFixtureChart);
        expect(engine.scheduleLog, hasLength(2), reason: '预备拍 0@100、1@388');

        engine.advance(const Duration(milliseconds: 100)); // now=200
        c.restart();
        final state = container.read(tabPracticeProvider);
        expect(state.running, isTrue);
        expect(state.paused, isFalse, reason: '干净复位,不带着暂停态重开');
        expect(
          engine.scheduleLog.first.stopped,
          isFalse,
          reason: '已响的预备拍 0 不动',
        );
        expect(engine.scheduleLog[1].stopped, isTrue, reason: '在途的预备拍 1 停掉');
        expect(
          c.visualAnchor!.t0,
          const Duration(milliseconds: 200 + 1154),
          reason: '新会话曲头 = now + round(4×288.46)',
        );
      });
    });
  });

  group('工单 13:变速', () {
    test('空闲 setSpeed 记参并钳制 0.5–1.0;start 后时间轴按变速编译', () async {
      final c = controller();
      c.setSpeed(0.3);
      expect(container.read(tabPracticeProvider).speed, 0.5, reason: '钳制下限');
      c.setSpeed(1.5);
      expect(container.read(tabPracticeProvider).speed, 1.0, reason: '钳制上限');
      c.setSpeed(0.7);

      c.prepareFor(tabFixtureChart);
      expect(
        container.read(tabPracticeProvider).speed,
        1.0,
        reason: '进谱回原速(每首谱都从原速起)',
      );

      c.setSpeed(0.5);
      await c.warmup();
      c.start(chart: tabFixtureChart);
      expect(c.timeline!.periodMs, closeTo(1500, 1e-9), reason: '60000/80/0.5');
      expect(c.visualAnchor!.periodMs, closeTo(1500, 1e-9));
    });

    test('运行中 setSpeed:重编译+相位保持重锚,首音按新网格曲头预定', () async {
      final c = controller();
      c.prepareFor(tabFixtureChart);
      await c.warmup();
      fakeAsync((async) {
        engine.advance(const Duration(milliseconds: 100));
        c.start(chart: tabFixtureChart);
        // 走到预备第 4 拍中段(now=2500,拍数守恒:旧曲头 3100 = 4 拍)。
        engine.advance(const Duration(milliseconds: 2400));
        c.setSpeed(0.5);
        expect(container.read(tabPracticeProvider).speed, 0.5);
        expect(c.timeline!.periodMs, closeTo(1500, 1e-9));
        // 重锚后拍数守恒:变速时已逝 3.2 拍(2400ms/750),新网格下同
        // 拍位展开 3.2×1500 = 4800 → t0' = 2500−4800 = −2300;曲头 =
        // −2300 + 4×1500 = 3700(拍内相位守恒,变速拍之后的拍顺延)。
        final anchor = c.visualAnchor!;
        expect(anchor.periodMs, closeTo(1500, 1e-9));
        expect(
          anchor.t0,
          const Duration(milliseconds: 3700),
          reason: '新曲头 = 重锚 t0 + 新预备跨度(拍数守恒手算)',
        );
        // 步进跨过新曲头:首音在新网格曲头锚预定,不丢声。
        for (var i = 0; i < 4; i++) {
          engine.advance(const Duration(milliseconds: 350));
          async.elapse(const Duration(milliseconds: 40));
        }
        final plucks = engine.scheduleLog
            .where((e) => e.key.startsWith('pluck_') && !e.stopped)
            .toList();
        expect(plucks, isNotEmpty, reason: '变速后示范声按新网格重排,不丢声');
        expect(plucks.first.time, anchor.t0, reason: '首音恒在曲头锚那一毫秒');
      });
    });

    test('暂停中 setSpeed:拍位守恒,恢复按新周期重锚', () async {
      final c = controller();
      c.prepareFor(tabFixtureChart);
      await c.warmup();
      fakeAsync((async) {
        engine.advance(const Duration(milliseconds: 700));
        c.start(chart: tabFixtureChart);
        engine.advance(const Duration(milliseconds: 4000)); // 曲内 1000ms
        c.pause();
        final beatBefore = tabPracticeStateAt(
          timeline: c.timeline!,
          t0: c.visualAnchor!.t0,
          now: c.visualNow()!,
        )!.beat;

        c.setSpeed(0.5);
        final beatAfter = tabPracticeStateAt(
          timeline: c.timeline!,
          t0: c.visualAnchor!.t0,
          now: c.visualNow()!,
        )!.beat;
        expect(beatAfter, beatBefore, reason: '冻结画面按拍数守恒换算,拍位不变');

        c.resume();
        final anchor = c.visualAnchor!;
        expect(anchor.periodMs, closeTo(1500, 1e-9));
        expect(
          anchor.t0.inMilliseconds,
          closeTo(4700 - 4000.0 / 750 * 1500 + 4 * 1500, 1),
          reason: '重锚 t0 = 引擎当前 − 冻结拍数×新周期;曲头锚再加新预备跨度',
        );
      });
    });
  });

  test('引擎预定出错:自停并进错误状态', () async {
    final c = controller();
    c.prepareFor(tabFixtureChart);
    await c.warmup();
    engine.failNow = true;
    c.start(chart: tabFixtureChart);
    final state = container.read(tabPracticeProvider);
    expect(state.running, isFalse, reason: '首过即抛,出错自停');
    expect(state.error, isNotNull);
  });

  group('审计30(#40/#41/#42)', () {
    test('运行中变速首过即抛:错误落地,不再回读锚点空断言崩(#41)', () async {
      final c = controller();
      c.prepareFor(tabFixtureChart);
      await c.warmup();
      fakeAsync((async) {
        c.start(chart: tabFixtureChart);
        // now=740:变速重锚后首拍 960 落在窗内,changePeriod 尾过窗必调
        // playClocked(错误才触发)。
        engine.advance(const Duration(milliseconds: 640));
        engine.failNow = true;
        expect(() => c.setSpeed(0.5), returnsNormally);
        final s = container.read(tabPracticeProvider);
        expect(s.running, isFalse, reason: '错误路径自停');
        expect(s.error, isNotNull);
      });
    });

    test('变速重建逐音调度:迟到窗内已响音不重放(#42)', () async {
      final c = controller();
      c.prepareFor(tabFixtureChart);
      await c.warmup();
      fakeAsync((async) {
        engine.advance(const Duration(milliseconds: 100));
        c.start(chart: tabFixtureChart);
        // 曲头 3100:推进到 3130,喂窗让首音(3100)预定;此刻它在
        // 40ms 迟到窗内刚响。
        engine.advance(const Duration(milliseconds: 3030));
        async.elapse(const Duration(milliseconds: 40));
        expect(
          engine.scheduleLog.where((e) => e.key.startsWith('pluck_')),
          hasLength(1),
          reason: '曲头首音已预定',
        );
        c.setSpeed(0.9); // 变速重建:新曲头锚落回迟到窗内,须按截止线跳过
        async.elapse(const Duration(milliseconds: 40));
        expect(
          engine.scheduleLog
              .where((e) =>
                  e.key.startsWith('pluck_') &&
                  e.time.inMilliseconds < 3130)
              .map((e) => e.time),
          hasLength(1),
          reason: '首音不因重建重放(旧实现重排出第二声)',
        );
      });
    });

    test('预载按谱键控:换谱后新谱音源必被加载(#40)', () async {
      const chartB = TabChart(
        title: 'B',
        artist: 'x',
        tempo: 80,
        notes: [TabNote(string: 4, fret: 0, beat: 0)],
      );
      final gated = GatedLoadEngine();
      final local = ProviderContainer(
        overrides: [audioEngineProvider.overrideWithValue(gated)],
      );
      addTearDown(local.dispose);
      final c = local.read(tabPracticeProvider.notifier);
      c.prepareFor(tabFixtureChart); // 预载 fixture:卡在 gate
      c.prepareFor(chartB); // 换谱:在途预载不得吞掉新谱的预载
      gated.gate.complete();
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        gated.loadedKeys,
        contains('pluck_${chartB.notes.first.frequency}_1500'),
        reason: '换谱后新谱音高被补载(旧在途合并会落空)',
      );
    });
  });
  test('单曲循环:passEnd 循环关→回闲;循环开→接第 2 遍(遍数+1,预备数拍再起)', () async {
    final c = controller();
    await c.warmup();
    // BPM 208(拍周期 288ms):启动首过窗(400ms)恒含预备拍 0、1,计数确定。
    c.setBpm(208);
    c.start(chart: tabFixtureChart);
    c.passEnd();
    expect(container.read(tabPracticeProvider).running, isFalse, reason: '循环关:曲末回闲');

    c.start(chart: tabFixtureChart);
    c.toggleLoop();
    expect(container.read(tabPracticeProvider).loop, isTrue);

    c.passEnd();
    final state = container.read(tabPracticeProvider);
    expect(state.running, isTrue, reason: '循环开:遍末即接下一遍,不停机');
    expect(state.pass, 2, reason: '遍数+1');
    expect(
      engine.scheduleLog.where((e) => e.key == 'tick_count'),
      hasLength(6),
      reason: '三次启动各含预备拍 0、1(首启+回闲后再启+循环重启),重启即预备数拍再起',
    );
  });
}

/// loadMem 可闸住的假引擎:预载在途与换谱的竞态用。
class GatedLoadEngine extends FakeAudioEngine {
  final Completer<void> gate = Completer<void>();

  @override
  Future<EngineSound> loadMem(String key, Uint8List wavBytes) {
    if (key.startsWith('pluck_')) {
      return gate.future.then((_) => super.loadMem(key, wavBytes));
    }
    return super.loadMem(key, wavBytes);
  }

}
