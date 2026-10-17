import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/providers.dart';
import '../../core/model/uke_string.dart';
import '../../core/tuner/pitch_math.dart';
import '../../core/tuner/tuner_filter.dart';
import '../../core/ui/equal_row.dart';
import '../../data/settings_providers.dart';
import '../../tab_index.dart';
import 'tuner_controller.dart';

/// 调音器正式页(工单 19,spike A 迁入):麦克风拾音调音 + 空弦试音。
///
/// 上卡「麦克风调音」:选 GCEA 目标弦 → 拨弦看实时音名与偏差音分,
/// ±5 音分点亮「已调准」;静音/噪声段不出读数、读数带阻尼(语义见
/// [TunerFilter])。权限拒绝给引导态,重试再走请求。A4 参考音随设置
/// ([referenceA4Provider],工单 20):目标频率/判准/试音/音名同源换算。
/// 下卡「空弦试音」:点弦名拨响标准音对照听音调弦(GLOSSARY:调音器页
/// 常驻,音源走拨弦合成管线)。
class TunerPage extends ConsumerStatefulWidget {
  const TunerPage({super.key});

  @override
  ConsumerState<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends ConsumerState<TunerPage>
    with WidgetsBindingObserver {
  /// 当前目标弦(默认 4 弦 G,与弦号序一致)。
  UkeString _target = UkeString.g;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 隐私纪律(真机验收反馈):拾音只发生在调音器页可见时——切走页签
  /// 或 App 退后台,立即停麦。回来不自动续:重开是显式动作。
  void _stopIfListening() {
    if (ref.read(tunerProvider).listening) {
      ref.read(tunerProvider.notifier).stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _stopIfListening();
  }

  Future<void> _pluck(UkeString string, double a4) async {
    try {
      await ref.read(pluckPlayerProvider).pluck(freq: string.frequencyAt(a4));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('试音失败:$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tuner = ref.watch(tunerProvider);
    final a4 = ref.watch(referenceA4Provider);
    // 切走页签即停(IndexedStack 保活,本页不 dispose;真机验收反馈)。
    ref.listen(activeTabIndexProvider, (previous, next) {
      if (next != tunerTabIndex) _stopIfListening();
    });
    return ListView(
      // 页签页无 AppBar:顶部留白放宽,内容不贴状态栏(真机验收反馈)。
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        const SizedBox(height: 32),
        _MicTunerCard(
          state: tuner,
          target: _target,
          a4: a4,
          onTargetChanged: (s) => setState(() => _target = s),
          onToggle: () => ref.read(tunerProvider.notifier).toggle(),
          onRetry: () => ref.read(tunerProvider.notifier).start(),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('空弦试音', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '点弦名拨响标准音,对照实体琴调弦',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                // 一行四钮宽度均分走共享等分行组件(工单 19 提取);
                // 按钮水平内边距收小防「4弦」折行(见 EqualRow 注)。
                KeyedSubtree(
                  key: const Key('pluck-row'),
                  child: EqualRow(
                    children: [
                      for (final string in UkeString.values)
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          onPressed: () => _pluck(string, a4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                string.label,
                                maxLines: 1,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                '${string.number}弦',
                                maxLines: 1,
                                softWrap: false,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline,
                                    ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 麦克风调音卡:目标弦行 + 实时读数区(权限引导态/大音名/偏差条)+
/// 开始/停止。
class _MicTunerCard extends StatelessWidget {
  const _MicTunerCard({
    required this.state,
    required this.target,
    required this.a4,
    required this.onTargetChanged,
    required this.onToggle,
    required this.onRetry,
  });

  final TunerState state;
  final UkeString target;

  /// A4 参考音 Hz(设置,工单 20):目标频率/判准随它换算。
  final double a4;

  final ValueChanged<UkeString> onTargetChanged;
  final VoidCallback onToggle;
  final VoidCallback onRetry;

  /// 相对目标弦的偏差音分(偏差条与判准共用一次换算,勿两处各算)。
  double? get _targetCents {
    final reading = state.reading;
    return reading == null
        ? null
        : centsBetween(reading.freq, target.frequencyAt(a4));
  }

  /// ±5 音分判准(spec 用户故事 3)。
  bool get _inTune {
    final cents = _targetCents;
    return cents != null && cents.abs() <= tunedThresholdCents;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('麦克风调音', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '选目标弦,拨弦看偏差',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: const Key('target-row'),
              child: EqualRow(
                children: [
                  for (final string in UkeString.values)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: string == target
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        foregroundColor: string == target
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      onPressed: () => onTargetChanged(string),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            string.label,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${string.frequencyAt(a4).round()}Hz',
                            maxLines: 1,
                            softWrap: false,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (state.permissionDenied)
              _PermissionGuide(onRetry: onRetry)
            else ...[
              _Reading(reading: state.reading, listening: state.listening),
              const SizedBox(height: 16),
              _DeviationBar(
                cents: _targetCents,
                target: target,
                inTune: _inTune,
              ),
              if (state.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.error!,
                  style: TextStyle(color: scheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
            if (_inTune) ...[
              const SizedBox(height: 12),
              Text(
                '✔ 已调准',
                key: const Key('in-tune'),
                style: TextStyle(color: Colors.green.shade700, fontSize: 18),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('mic-toggle'),
              onPressed: onToggle,
              icon: Icon(state.listening ? Icons.mic_off : Icons.mic),
              label: Text(state.listening ? '停止' : '开始调音'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 权限引导态(工单验收:权限拒绝给引导态):说明去哪开,重试再请求。
class _PermissionGuide extends StatelessWidget {
  const _PermissionGuide({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(Icons.mic_off_outlined, size: 40, color: scheme.outline),
        const SizedBox(height: 8),
        Text('需要麦克风权限才能调音'),
        const SizedBox(height: 4),
        Text(
          '请在系统设置 › 应用 › UkeFlow › 权限中允许麦克风,再回来重试',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.outline),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const Key('mic-retry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      ],
    );
  }
}

/// 实时读数:大音名 + 频率行。静音段不显示音高(占位符随状态)。
/// 频率行只报 Hz 不报音分——页面唯一的音分是偏差条上相对目标弦的那份,
/// 两份口径并列(相对最近音 vs 相对目标弦)必互相打架。
class _Reading extends StatelessWidget {
  const _Reading({required this.reading, required this.listening});

  final TunerReading? reading;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reading = this.reading;
    return Column(
      children: [
        Text(
          reading?.noteName ?? (listening ? '…' : '—'),
          key: const Key('note-name'),
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: reading == null ? scheme.outline : scheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(switch (reading) {
          null => listening ? '倾听中…' : '开始后拨响琴弦',
          final r => '${r.freq.toStringAsFixed(1)} Hz',
        }, style: TextStyle(color: scheme.outline)),
      ],
    );
  }
}

/// 偏差指示条:指针位置 = 相对目标弦偏差([cents],±50¢ 满量程),±5¢
/// 判准带高亮(已调准时条体转绿)。
class _DeviationBar extends StatelessWidget {
  const _DeviationBar({
    required this.cents,
    required this.target,
    required this.inTune,
  });

  /// 相对目标弦的偏差音分;null = 无读数。
  final double? cents;
  final UkeString target;
  final bool inTune;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 280,
      child: Column(
        children: [
          Text(
            cents == null
                ? '相对 ${target.label} 弦:—'
                : '相对 ${target.label} 弦:${_signed(cents!)}',
            style: TextStyle(color: scheme.outline),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 14,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: inTune
                        ? Colors.green.shade200
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                Align(
                  alignment: Alignment(((cents ?? 0) / 50).clamp(-1.0, 1.0), 0),
                  child: Container(
                    width: 4,
                    height: 14,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _signed(double cents) =>
      '${cents >= 0 ? '+' : ''}${cents.toStringAsFixed(0)}¢';
}
