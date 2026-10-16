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
    final lc = InitLifecycle(isLive: () => true, shutdown: () {});
    final f1 = lc.ensureInitialized(() async {
      inits++;
      await gate.future;
    });
    final f2 = lc.ensureInitialized(() async {
      inits++;
      await gate.future;
    });
    expect(identical(f1, f2), isTrue, reason: '并发复用同一 Future');
    gate.complete();
    await f1;
    await f2;
    expect(inits, 1);
  });
}
