import 'dart:async';

/// 引擎初始化/关闭竞态守卫:dispose 与挂起中的初始化赛跑时,保证原生
/// 资源最终被释放、且 dispose 后不再复活引擎。
///
/// 背景(审计 2026-10-16 #9):dispose 只看 isInitialized——初始化在途
/// 时它是 false,deinit 被跳过;随后初始化完成,引擎无人持有,原生资源
/// 滞留到进程死。本类把「在途初始化落定后补关停」与「dispose 后拒绝再
/// 初始化」收进一个小状态机,经 [isLive]/[shutdown] 注入即可单测,
/// 不依赖任何真引擎(真 SoLoud 私有构造不可替身)。
class InitLifecycle {
  InitLifecycle({required this.isLive, required this.shutdown});

  /// 原生引擎当前是否已初始化(真实现读 SoLoud.instance.isInitialized)。
  final bool Function() isLive;

  /// 释放原生引擎(真实现调 SoLoud.instance.deinit)。
  final void Function() shutdown;

  bool _disposed = false;
  Future<void>? _pending;

  /// 是否已 dispose(dispose 后初始化一律拒绝)。
  bool get disposed => _disposed;

  /// 幂等初始化;并发调用合并为同一次;dispose 后抛 [StateError]。
  Future<void> ensureInitialized(Future<void> Function() init) {
    if (_disposed) {
      return Future.error(StateError('引擎已关闭,不能再次初始化'));
    }
    return _pending ??= init().whenComplete(() => _pending = null);
  }

  /// 关停:初始化在途则待其落定后补 shutdown(异步收尾,不等它);
  /// 初始化失败与重复 dispose 均无害。dispose 后的初始化请求被拒,
  /// 不会出现「关闭后又初始化」的复活路径。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final pending = _pending;
    if (pending != null) {
      unawaited(
        pending.whenComplete(() {
          if (_disposed && isLive()) shutdown();
        }).catchError((Object _) {}),
      );
    } else if (isLive()) {
      shutdown();
    }
  }
}
