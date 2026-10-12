import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/providers.dart';
import '../../core/model/builtin_strum_patterns.dart';
import '../../core/model/strum_pattern.dart';
import '../../core/practice/rhythm_state.dart';
import 'rhythm_trainer_controller.dart';

/// 节奏型训练页:选节奏型 + BPM 慢练,↓↑ 箭头随节拍逐槽高亮,节拍声可开关。
///
/// ADR-0005:轮询只是重绘触发器,箭头状态一律由引擎时刻经
/// [rhythmPracticeAt] 纯函数算出(工单 08 练习状态函数的最小先行版),
/// 页内无任何挂钟;轮询随运行启停,空闲页零定时器。
class RhythmTrainerPage extends ConsumerStatefulWidget {
  const RhythmTrainerPage({super.key});

  @override
  ConsumerState<RhythmTrainerPage> createState() => _RhythmTrainerPageState();
}

class _RhythmTrainerPageState extends ConsumerState<RhythmTrainerPage> {
  static const _pollInterval = Duration(milliseconds: 16);

  Timer? _poll;

  /// 最近一次轮询算出的练习状态(只取其槽位/拍号渲染);空闲 null。
  RhythmPracticeState? _visual;

  // dispose 里不能用 ref(Riverpod 3):notifier 在 initState 缓存成字段。
  late final RhythmTrainerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(rhythmTrainerProvider.notifier);
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
    final visual = rhythmPracticeAt(
      now: ref.read(audioEngineProvider).engineTime(),
      t0: anchor.t0,
      periodMs: anchor.periodMs,
      pattern: ref.read(rhythmTrainerProvider).pattern,
    );
    if (visual == null) return;
    if (visual.barIndex != _visual?.barIndex ||
        visual.slotInBar != _visual?.slotInBar) {
      setState(() => _visual = visual);
    }
  }

  void _startPoll() {
    _poll?.cancel();
    setState(() => _visual = null);
    _poll = Timer.periodic(_pollInterval, (_) => _onPoll());
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rhythmTrainerProvider);
    // 运行状态翻转时启停轮询(ref.listen 须在 build 内注册)。
    ref.listen(rhythmTrainerProvider, (previous, next) {
      if (previous?.running != next.running) {
        next.running ? _startPoll() : _stopPoll();
      }
    });
    final colorScheme = Theme.of(context).colorScheme;
    final currentSlot = state.running ? _visual?.slotInBar : null;

    return Scaffold(
      appBar: AppBar(title: const Text('节奏型训练')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _engineStatus(state, colorScheme),
                const SizedBox(height: 24),
                _patternPicker(state),
                const SizedBox(height: 24),
                _arrowStrip(state, currentSlot, colorScheme),
                const SizedBox(height: 16),
                Text(
                  state.running && _visual != null
                      ? '${_visual!.beatInBar + 1}'
                      : '·',
                  key: const Key('beat-number'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                const SizedBox(height: 24),
                _bpmControl(state, colorScheme),
                const SizedBox(height: 12),
                _clickSwitch(state),
                const SizedBox(height: 24),
                FilledButton.icon(
                  // key 供测试;引擎未就绪不可启。
                  key: const Key('rhythm-toggle'),
                  onPressed: state.engineReady
                      ? () => ref.read(rhythmTrainerProvider.notifier).toggle()
                      : null,
                  icon: Icon(state.running ? Icons.stop : Icons.play_arrow),
                  label: Text(state.running ? '停止' : '开始'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _engineStatus(RhythmTrainerState state, ColorScheme colorScheme) {
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
      textAlign: TextAlign.center,
    );
  }

  Widget _patternPicker(RhythmTrainerState state) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final pattern in builtinStrumPatterns)
          ChoiceChip(
            key: Key('pattern-${pattern.id}'),
            label: Text(pattern.name),
            selected: state.pattern == pattern,
            // 运行中换型即时生效:纯函数下一帧即按新节奏型查表。
            onSelected: (_) => _controller.setPattern(pattern),
          ),
      ],
    );
  }

  /// 一小节 8 槽一行均分:扫弦槽画 ↓/↑,空拍槽画小圆点;
  /// 当前槽主色填充(当前动作突出),本小节已扫槽淡出,未到槽描边待命。
  Widget _arrowStrip(
    RhythmTrainerState state,
    int? currentSlot,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        for (var slot = 0; slot < eighthsPerBar; slot++) ...[
          if (slot > 0) const SizedBox(width: 6),
          Expanded(child: _slotCell(state, slot, currentSlot, colorScheme)),
        ],
      ],
    );
  }

  Widget _slotCell(
    RhythmTrainerState state,
    int slot,
    int? currentSlot,
    ColorScheme colorScheme,
  ) {
    final isCurrent = currentSlot == slot;
    final isPlayed = currentSlot != null && slot < currentSlot;
    final stroke = state.pattern.slots[slot];
    final Color fill;
    final Color content;
    final Border? border;
    if (isCurrent) {
      fill = colorScheme.primary;
      content = colorScheme.onPrimary;
      border = null;
    } else if (isPlayed) {
      fill = colorScheme.surfaceContainerHighest;
      content = colorScheme.onSurfaceVariant;
      border = null;
    } else {
      fill = Colors.transparent;
      content = colorScheme.onSurface;
      border = Border.all(color: colorScheme.outlineVariant);
    }
    return Container(
      key: Key('arrow-slot-$slot'),
      height: 52,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: border,
      ),
      child: Center(
        child: stroke == null
            ? Text(
                '·',
                style: TextStyle(color: content, height: 1),
              )
            : Icon(
                stroke == StrumDirection.down
                    ? Icons.arrow_downward
                    : Icons.arrow_upward,
                color: content,
                size: 26,
              ),
      ),
    );
  }

  Widget _bpmControl(RhythmTrainerState state, ColorScheme colorScheme) {
    final controller = ref.read(rhythmTrainerProvider.notifier);
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
          min: RhythmTrainerController.minBpm.toDouble(),
          max: RhythmTrainerController.maxBpm.toDouble(),
          divisions: RhythmTrainerController.maxBpm - RhythmTrainerController.minBpm,
          label: '${state.bpm}',
          onChanged: state.engineReady ? (v) => controller.setBpm(v.round()) : null,
        ),
      ],
    );
  }

  Widget _clickSwitch(RhythmTrainerState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('节拍声'),
        const SizedBox(width: 8),
        Switch(
          key: const Key('click-switch'),
          value: state.clickOn,
          onChanged: (_) => _controller.toggleClick(),
        ),
      ],
    );
  }
}
