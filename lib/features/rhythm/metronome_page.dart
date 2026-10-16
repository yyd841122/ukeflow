import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/beat_scheduling.dart';
import '../../core/audio/providers.dart';
import 'metronome_controller.dart';

/// 节拍器页:BPM 40–208 即时可调、启停、4/4 强弱拍(每小节第 1 拍重音)。
///
/// ADR-0005:轮询只是重绘触发器,拍状态一律由引擎时刻经 [beatAt]
/// 纯函数算出,页内无任何挂钟。轮询随运行启停,空闲页零定时器。
class MetronomePage extends ConsumerStatefulWidget {
  const MetronomePage({super.key});

  @override
  ConsumerState<MetronomePage> createState() => _MetronomePageState();
}

class _MetronomePageState extends ConsumerState<MetronomePage> {
  static const _pollInterval = Duration(milliseconds: 16);

  Timer? _poll;
  int _lastBeatIndex = -1;
  int _lastBeatInBar = -1;

  // dispose 里不能用 ref(Riverpod 3):notifier 在 initState 缓存成字段。
  late final MetronomeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(metronomeProvider.notifier);
    // 引擎预热;离开页面即停:不留后台节拍声。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.warmup();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.stop();
    super.dispose();
  }

  void _onPoll() {
    final anchor = _controller.visualAnchor;
    if (anchor == null) return;
    _controller.refreshScheduled();
    final visual = beatAt(
      now: ref.read(audioEngineProvider).engineTime(),
      t0: anchor.t0,
      periodMs: anchor.periodMs,
    );
    if (visual == null) return;
    final (beatIndex, beatInBar, _) = visual;
    if (beatIndex != _lastBeatIndex) {
      setState(() {
        _lastBeatIndex = beatIndex;
        _lastBeatInBar = beatInBar;
      });
    }
  }

  void _startPoll() {
    _poll?.cancel();
    setState(() {
      _lastBeatIndex = -1;
      _lastBeatInBar = -1;
    });
    _poll = Timer.periodic(_pollInterval, (_) => _onPoll());
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(metronomeProvider);
    // 运行状态翻转时启停轮询(ref.listen 须在 build 内注册)。
    ref.listen(metronomeProvider, (previous, next) {
      if (previous?.running != next.running) {
        next.running ? _startPoll() : _stopPoll();
      }
    });
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('节拍器')),
      // 矮视口(短屏/横屏)可滚:不可滚 Column 内容被裁(审计 2026-10-16
      // #47);minHeight 保持常态下的竖直居中布局。
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: _bodyChildren(state, colorScheme),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _bodyChildren(MetronomeState state, ColorScheme colorScheme) => [
        _engineStatus(state, colorScheme),
        const SizedBox(height: 32),
        _beatRow(state.running ? _lastBeatInBar : null, colorScheme),
        const SizedBox(height: 16),
        Text(
          state.running ? '${_lastBeatInBar + 1}' : '·',
          style: Theme.of(context).textTheme.displayLarge,
        ),
        const SizedBox(height: 32),
        _bpmControl(state, colorScheme),
        const SizedBox(height: 32),
        FilledButton.icon(
          // key 供测试;引擎未就绪不可启。
          key: const Key('metronome-toggle'),
          onPressed: state.engineReady
              ? () => ref.read(metronomeProvider.notifier).toggle()
              : null,
          icon: Icon(state.running ? Icons.stop : Icons.play_arrow),
          label: Text(state.running ? '停止' : '开始'),
        ),
        const SizedBox(height: 24),
        if (state.running) Text('已预定 ${state.scheduledBeats} 拍'),
      ];

  Widget _engineStatus(MetronomeState state, ColorScheme colorScheme) {
    if (state.error != null) {
      return Text(
        state.error!,
        style: TextStyle(color: colorScheme.error),
        textAlign: TextAlign.center,
      );
    }
    return Text(
      state.engineReady ? '引擎就绪' : '引擎初始化中…',
      style: TextStyle(color: colorScheme.outline),
    );
  }

  /// 4/4 拍点:当前拍点亮,强拍(每小节第 1 拍)更大。
  Widget _beatRow(int? beatInBar, ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < beatsPerBar; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Container(
            key: Key('beat-dot-$i'),
            width: i == 0 ? 24 : 18,
            height: i == 0 ? 24 : 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: beatInBar == i
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ],
    );
  }

  Widget _bpmControl(MetronomeState state, ColorScheme colorScheme) {
    final controller = ref.read(metronomeProvider.notifier);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: state.engineReady
                  ? () => controller.setBpm(state.bpm - 1)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 96,
              child: Text(
                '${state.bpm}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              onPressed: state.engineReady
                  ? () => controller.setBpm(state.bpm + 1)
                  : null,
              icon: const Icon(Icons.add),
            ),
            Text('BPM', style: TextStyle(color: colorScheme.outline)),
          ],
        ),
        Slider(
          value: state.bpm.toDouble(),
          min: MetronomeController.minBpm.toDouble(),
          max: MetronomeController.maxBpm.toDouble(),
          divisions: MetronomeController.maxBpm - MetronomeController.minBpm,
          label: '${state.bpm}',
          onChanged: state.engineReady ? (v) => controller.setBpm(v.round()) : null,
        ),
      ],
    );
  }
}
