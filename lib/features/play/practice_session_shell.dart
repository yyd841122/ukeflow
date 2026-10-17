import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 跟练会话页基类(工单 19 评审提取:弹唱跟练页与指弹跟练会话页的三壳
/// 收拢——16ms 轮询壳、预备数拍过渡、dispose 停声纪律)。
///
/// ADR-0005:轮询只是重绘触发器,一切时刻由子类经控制器按引擎时刻查询,
/// 页内无第二时间源;轮询随运行启停,空闲零定时器。
abstract class PracticeSessionState<W extends ConsumerStatefulWidget>
    extends ConsumerState<W> {
  Timer? _poll;

  /// 预备数拍期剩余倒计(4..1);非 null = 倒计面板。正曲期 null。
  int? _prepCount;
  int? get prepCount => _prepCount;

  /// 启动运行轮询:先清上一轮状态(预备倒计与子类视觉缓存),再起
  /// 16ms 定时器并**同步首查**——与 BeatScheduler 先过窗同理,进入即有
  /// 画面,不等第一 tick。
  void startPolling() {
    _poll?.cancel();
    setState(() {
      _prepCount = null;
      resetVisual();
    });
    _poll = Timer.periodic(pollInterval, (_) => onPoll());
    onPoll();
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Duration get pollInterval => const Duration(milliseconds: 16);

  /// 清空子类的运行中视觉缓存(新一轮会话从零起算)。
  @protected
  void resetVisual();

  /// 一次轮询:子类按引擎时刻查练习状态,任一显示要素推进才重绘
  /// (薄渲染纪律)。曲末自停由子类调控制器 stop,轮询随之自停。
  @protected
  void onPoll();

  /// 预备数拍过渡。返回 true = 仍在预备期,调用方直接返回;返回 false =
  /// 正曲期,预备毕的那一帧已就地重绘一次(倒计面板切正曲视图)。
  @protected
  bool advancePrep(int? count) {
    if (count != null) {
      if (count != _prepCount) setState(() => _prepCount = count);
      return true;
    }
    if (_prepCount != null) setState(() => _prepCount = null);
    return false;
  }

  /// 弹回即停纪律:Riverpod 3 禁止 widget unmount 期间改 provider 状态
  /// (直接 stop 会抛"tried to modify a provider"),推迟一个微任务:
  /// 引擎调度与声音在下一宏任务前即全停,无任何残留。子类 dispose 里
  /// 调用;轮询定时器由本基类 dispose 取消。
  @protected
  void stopSessionOnUnmount(List<VoidCallback> stops) {
    scheduleMicrotask(() {
      for (final stop in stops) {
        stop();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
