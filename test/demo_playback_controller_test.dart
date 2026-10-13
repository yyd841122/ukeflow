import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/pluck_player.dart';
import 'package:ukeflow/core/audio/providers.dart';
import 'package:ukeflow/core/model/builtin_strum_patterns.dart';
import 'package:ukeflow/core/practice/play_timeline.dart';
import 'package:ukeflow/data/chord_library.dart' show Chord;
import 'package:ukeflow/features/demo/demo_playback_controller.dart';
import 'package:ukeflow/features/play/play_practice_controller.dart';

import 'helpers/chart_fixtures.dart';
import 'helpers/chord_fixtures.dart';

/// 示范试听控制器(工单 11):弹唱谱按所选节奏型+当前 BPM 整曲扫弦,
/// 与跟练同一时间轴、同一调度引擎。接缝在 DemoPlaybackState 与公开
/// 方法;引擎一律注入 FakeAudioEngine,时间用 engine.advance 推进。
/// fakeAsync 体保持同步(工单 10 教训):准备链的 await 都在假引擎上
/// 即时完成,flushMicrotasks 一次落定;真实 zone 预热的用例先在 zone 外
/// 完成。
void main() {
  late FakeAudioEngine engine;
  late ProviderContainer container;

  DemoPlaybackController demo() =>
      container.read(demoPlaybackProvider.notifier);
  PlayPracticeController practice() =>
      container.read(playPracticeProvider.notifier);
  DemoPlaybackState state() => container.read(demoPlaybackProvider);

  Map<String, Chord> fixtureChords() => {
    for (final chord in uiFixtureLibrary.chords) chord.label: chord,
  };

  /// Am 主指法(4→1 弦)的弦频:期望键名的独立数据源(fixture,非实现)。
  List<double?> amFreqs() =>
      fixtureChords()['Am']!.primaryFingering.stringFrequencies;

  Iterable<FakeScheduledCall> plucks() =>
      engine.scheduleLog.where((c) => c.key.startsWith('pluck_'));

  void startDemo() =>
      demo().start(chart: practiceFixtureChart, chords: fixtureChords());

  setUp(() {
    engine = FakeAudioEngine();
    container = ProviderContainer(
      overrides: [audioEngineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);
  });

  test('初始:idle 无错误', () {
    expect(state().status, DemoPlaybackStatus.idle);
    expect(state().error, isNull);
  });

  test('start 同步进 preparing 防双击,就绪后 playing:首过按时间轴预定下扫', () async {
    engine.now = const Duration(milliseconds: 1000);
    startDemo();
    expect(state().status, DemoPlaybackStatus.preparing, reason: '同步态先行');
    expect(plucks(), isEmpty, reason: '准备期不发声');

    await Future<void>.delayed(Duration.zero); // 准备链(假引擎即时完成)
    expect(state().status, DemoPlaybackStatus.playing);

    // 80 BPM、默认全下扫型:t0=1000,槽距 750ms,窗右沿 1400 → 只含槽 0。
    // Am 四弦错峰 45ms:1000/1045/1090/1135。
    final group = plucks().toList();
    expect(group, hasLength(4));
    expect(
      group.first.key,
      'pluck_${amFreqs()[0]}_1500',
      reason: '下扫长衰减变体(与既有默认时长一致)',
    );
    expect(group.map((c) => c.time).toList(), [
      const Duration(milliseconds: 1000),
      const Duration(milliseconds: 1045),
      const Duration(milliseconds: 1090),
      const Duration(milliseconds: 1135),
    ]);
    demo().stop(); // 收掉真实 zone 的周期定时器,不泄给后续用例
  });

  test('下/上扫各定各的衰减变体:上扫事件全走短衰减(island 型)', () {
    practice().setPattern(builtinStrumPatterns.last); // island:槽 3/5/7 上扫
    fakeAsync((async) {
      engine.now = const Duration(milliseconds: 100);
      startDemo();
      async.flushMicrotasks(); // 准备链落定(假引擎即时完成)
      expect(state().status, DemoPlaybackStatus.playing);

      // 首过窗 [60,460]:槽 0(t=100,下扫)。
      expect(plucks().map((c) => c.key), everyElement(endsWith('_1500')));

      // 推到槽 3(t=1125+100,上扫)入窗:全部弦走短衰减变体。
      engine.advance(const Duration(milliseconds: 1160)); // now=1260
      async.elapse(const Duration(milliseconds: 40));
      final upGroup = plucks()
          .where((c) => c.time.inMilliseconds >= 1200)
          .toList();
      expect(upGroup, hasLength(4), reason: '上扫事件一扫四弦(无闷音)');
      expect(upGroup.map((c) => c.key), everyElement(endsWith('_700')));
      expect(upGroup.first.time, const Duration(milliseconds: 1225));
      expect(
        plucks().where((c) => c.time.inMilliseconds < 1200).map((c) => c.key),
        everyElement(endsWith('_1500')),
        reason: '同曲同和弦,方向定声两套变体并存',
      );
    });
  });

  test('参数快照:按开始那一刻的变速编译(空闲改参不打扰在途试听)', () {
    practice().setSpeed(0.5);
    fakeAsync((async) {
      engine.now = Duration.zero;
      startDemo();
      async.flushMicrotasks();
      // slotMs = 375/0.5 = 750:第二扫锚在 t0+1500(弦间再错峰 45ms),
      // 原速网格的 t0+750 处无声。
      engine.advance(const Duration(milliseconds: 1540)); // now=1540
      async.elapse(const Duration(milliseconds: 40));
      final second = plucks()
          .where(
            (c) =>
                c.time >= const Duration(milliseconds: 1500) &&
                c.time < const Duration(milliseconds: 1650),
          )
          .toList();
      expect(second, hasLength(4), reason: '变速网格生效:槽 2 锚在 1500');
      expect(second.first.time, const Duration(milliseconds: 1500));
      expect(
        plucks().where((c) {
          final t = c.time.inMilliseconds;
          return t >= 700 && t < 900;
        }),
        isEmpty,
        reason: '原速网格的 750 处无事件',
      );
    });
  });

  test('中途停止:未响预定停净,之后不再调度', () {
    fakeAsync((async) {
      startDemo();
      async.flushMicrotasks();
      expect(state().status, DemoPlaybackStatus.playing);
      expect(plucks(), hasLength(4), reason: '槽 0 已排未响(now=0)');

      demo().stop();
      expect(state().status, DemoPlaybackStatus.idle);
      // 已响的不动(拨在 now 的首弦不可撤),未响的停净——无残留声。
      final nowAtStop = engine.engineTime();
      final pending = plucks().where((c) => c.time > nowAtStop).toList();
      expect(pending, hasLength(3), reason: '45/90/135ms 三弦未响');
      expect(pending.every((c) => c.stopped), isTrue);

      final frozen = engine.scheduleLog.length;
      engine.advance(const Duration(seconds: 3));
      async.elapse(const Duration(milliseconds: 40));
      expect(engine.scheduleLog, hasLength(frozen), reason: '停后不再调度');
    });
  });

  test('曲末自动回闲:过时间轴末端即停,轮询自停无幻声', () {
    fakeAsync((async) {
      startDemo();
      async.flushMicrotasks();
      // 80 BPM 4 小节:曲长 12s、判定 12s+错峰尾;逐 400ms 推进引擎与
      // 定时器(推进量须同时喂过 200ms 判定轮询的引擎时刻)。
      for (var i = 0; i < 40; i++) {
        engine.advance(const Duration(milliseconds: 400));
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(state().status, DemoPlaybackStatus.idle, reason: '曲末自动回闲');
      expect(
        plucks().map((c) => c.time.inMilliseconds).reduce((a, b) => b),
        lessThanOrEqualTo(12000 + 3 * PluckPlayer.strumGap.inMilliseconds),
        reason: '最后一扫不越曲末',
      );
      final frozen = engine.scheduleLog.length;
      engine.advance(const Duration(seconds: 2));
      async.elapse(const Duration(seconds: 1));
      expect(engine.scheduleLog, hasLength(frozen), reason: '回闲后一切冻结');
      expect(state().status, DemoPlaybackStatus.idle);
    });
  });

  test('曲末判定扫域(40–208 BPM 逐 1 × 变速两档):末扫锚+错峰尾都受判定覆盖', () {
    // CODING_STANDARDS「边界扫域」:round(totalBeats×period) 的曲末边界
    // 只在非整除域显形,单点 80 BPM 不作数。扫的关系:曲末判定时刻
    // (endOffset)不得早于最后一声的预定时刻(末扫锚 + 3×strumGap)。
    for (var bpm = 40; bpm <= 208; bpm++) {
      for (final speed in const [1.0, 0.5]) {
        final timeline = compileTimeline(
          chart: practiceFixtureChart,
          pattern: builtinStrumPatterns.first,
          bpm: bpm.toDouble(),
          speed: speed,
        );
        final end = DemoPlaybackController.endOffset(timeline);
        expect(
          end.inMilliseconds - timeline.strums.last.time.inMilliseconds,
          greaterThanOrEqualTo(3 * PluckPlayer.strumGap.inMilliseconds),
          reason: 'BPM $bpm @$speed:末扫的错峰尾弦不得落进曲末停机窗',
        );
      }
    }
  });

  test('引擎预定出错:自停并报错;解除后再开错误不残留', () {
    fakeAsync((async) {
      engine.failNow = true;
      startDemo();
      async.flushMicrotasks();
      expect(state().status, DemoPlaybackStatus.idle);
      expect(state().error, contains('试听'));

      engine.failNow = false;
      startDemo();
      async.flushMicrotasks();
      expect(state().status, DemoPlaybackStatus.playing);
      expect(state().error, isNull, reason: '上次错误不残留到成功之后');
    });
  });

  test('准备失败(引擎初始化):回 idle 并报错', () async {
    engine.failInitialization = true;
    startDemo();
    expect(state().status, DemoPlaybackStatus.preparing);

    await Future<void>.delayed(Duration.zero);
    expect(state().status, DemoPlaybackStatus.idle);
    expect(state().error, isNotNull);
  });

  test('准备期点停:异步链落地后不复活发声', () async {
    startDemo();
    demo().stop(); // 同步紧随:准备链尚未落地
    await Future<void>.delayed(Duration.zero);
    expect(state().status, DemoPlaybackStatus.idle);
    expect(plucks(), isEmpty, reason: '被打断的准备不再起调度器');
  });

  test('跟练运行中不开试听;试听中重复 start 忽略', () async {
    final p = practice();
    await p.warmup();
    p.start(chart: practiceFixtureChart, chords: fixtureChords());
    startDemo();
    expect(state().status, DemoPlaybackStatus.idle, reason: '跟练声在前');
    expect(plucks(), isEmpty);
    p.stop();

    startDemo();
    await Future<void>.delayed(Duration.zero);
    expect(state().status, DemoPlaybackStatus.playing);
    final logLen = engine.scheduleLog.length;

    startDemo();
    await Future<void>.delayed(Duration.zero);
    expect(state().status, DemoPlaybackStatus.playing);
    expect(engine.scheduleLog, hasLength(logLen), reason: '重复 start 不叠加');
    demo().stop();
  });
}
