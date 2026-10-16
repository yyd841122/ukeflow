import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/init_lifecycle.dart';

/// InitLifecycle:dispose 与挂起初始化的竞态守卫(审计 2026-10-16 #9)。
/// isLive/shutdown 注入假状态,不碰真引擎(真 SoLoud 私有构造不可替身)。
void main() {
  test('初始化完成后 dispose:立即关停', () async {
    var live = false;
    var shutdowns = 0;
    final lc = InitLifecycle(isLive: () => live, shutdown: () => shutdowns++);
    await lc.ensureInitialized(() async => live = true);
    lc.dispose();
    expect(shutdowns, 1);
    expect(lc.disposed, isTrue);
  });

  test('初始化在途时 dispose:落定后补关停,原生资源不滞留', () async {
    var live = false;
    var shutdowns = 0;
    final gate = Completer<void>();
    final lc = InitLifecycle(isLive: () => live, shutdown: () => shutdowns++);
    final init = lc.ensureInitialized(() async {
      await gate.future;
      live = true;
    });
    lc.dispose();
    expect(shutdowns, 0, reason: '初始化未落定,立即关停无意义');
    gate.complete();
    await init;
    await Future<void>.delayed(Duration.zero);
    expect(shutdowns, 1, reason: '落定后补关停');
  });

  test('dispose 后初始化:拒绝(StateError),引擎不复活', () async {
    var initCalls = 0;
    final lc = InitLifecycle(isLive: () => initCalls > 0, shutdown: () {});
    await lc.ensureInitialized(() async => initCalls++);
    lc.dispose();
    await expectLater(
      lc.ensureInitialized(() async => initCalls++),
      throwsStateError,
    );
    expect(initCalls, 1, reason: '拒绝在先,初始化闭包不再执行');
  });

  test('初始化失败:错误照常上抛;之后 dispose 不补关停(未 live)', () async {
    var shutdowns = 0;
    final lc = InitLifecycle(isLive: () => false, shutdown: () => shutdowns++);
    await expectLater(
      lc.ensureInitialized(() async => throw Exception('初始化失败')),
      throwsException,
    );
    lc.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(shutdowns, 0);
  });

  test('初始化在途且最终失败时 dispose:不补关停、无未处理异步错误', () async {
    var shutdowns = 0;
    var live = false;
    final gate = Completer<void>();
    final lc = InitLifecycle(isLive: () => live, shutdown: () => shutdowns++);
    final init = lc.ensureInitialized(() async {
      await gate.future;
      throw Exception('初始化在落定时失败(引擎未 live)');
    });
    lc.dispose();
    gate.complete();
    await expectLater(init, throwsException);
    await Future<void>.delayed(Duration.zero);
    expect(shutdowns, 0, reason: '初始化失败,引擎未 live,无需关停');
  });

  test('重复 dispose 幂等;未初始化直接 dispose 不关停', () {
    var shutdowns = 0;
    final lc = InitLifecycle(isLive: () => false, shutdown: () => shutdowns++);
    lc.dispose();
    lc.dispose();
    expect(shutdowns, 0);
  });

  test('并发初始化合并为同一次(既有语义保持)', () async {
    var inits = 0;
    final gate = Completer<void>();
    // 完成前引擎不 live(gate 放行才置位):并发合并在未完成窗口内生效。
    final lc = InitLifecycle(isLive: () => inits > 0, shutdown: () {});
    // 真实时序:引擎在初始化**完成时**才 live——闭包先等闸、后置位。
    final f1 = lc.ensureInitialized(() async {
      await gate.future;
      inits++;
    });
    final f2 = lc.ensureInitialized(() async {
      await gate.future;
      inits++;
    });
    expect(identical(f1, f2), isTrue, reason: '并发复用同一 Future');
    gate.complete();
    await f1;
    await f2;
    expect(inits, 1);
  });

  test('初始化完成后重复调用:闭包不重跑,幂等返回(verify 复核 #9 回归)', () async {
    var inits = 0;
    final lc = InitLifecycle(isLive: () => inits > 0, shutdown: () {});
    await lc.ensureInitialized(() async => inits++);
    await lc.ensureInitialized(() async => inits++);
    await lc.ensureInitialized(() async => inits++);
    expect(inits, 1, reason: '已完成初始化后重复调用不得重跑闭包'
        '(真引擎再 init = 清音源登记 + deinit/reinit)');
  });

  test('连续注入两个音源的顺序加载路径:初始化只执行一次(verify 复核场景)', () async {
    var inits = 0;
    final lc = InitLifecycle(isLive: () => inits > 0, shutdown: () {});
    // 模拟 loadMem×2:每个都先 await ensureInitialized 再干活。
    Future<String> load(String key) async {
      await lc.ensureInitialized(() async => inits++);
      return key;
    }

    await Future.wait([load('a'), load('b')]);
    expect(inits, 1, reason: '并发合并');
    await load('c');
    expect(inits, 1, reason: '顺序跟进也不再初始化');
  });

}