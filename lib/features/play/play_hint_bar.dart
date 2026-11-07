import 'package:flutter/material.dart';

import '../../core/audio/beat_scheduling.dart' show beatsPerBar;
import '../../core/chart/score_sheet_defs.dart';
import '../../core/model/tab_chart.dart';
import '../../core/practice/score_sheet_layout.dart';

/// 弹奏提示条(票07,新手跟弹):运行中常驻,随播放从曲头到曲尾逐列
/// 推进——当列该弹的弦/品点亮,下一列描边预亮;头部给当位和弦名、
/// 小节拍位与扫弦/卷弦记号。数据面纯函数 [playHintAt](布局 + 主轴拍位
/// → 提示帧),页面轮询在当位变化时算一帧喂进来。
///
/// 提示只跟伴奏层(主轴):双轨混播的旋律轨是代唱(+20 拍偏移),不是
/// 用户该弹的东西;扫弦逐弦错峰是毫秒级发声细节,提示按列拍整列亮。

/// 一帧提示(纯数据,widget 只管画)。
class PlayHintFrame {
  const PlayHintFrame({
    required this.current,
    required this.next,
    required this.chordLabel,
    required this.strum,
    required this.barNumber,
    required this.beatInBar,
  });

  /// 当列音(该现在弹的;空 = 列拍存在但无音——理论不见,列拍来自音)。
  final List<TabNote> current;

  /// 下一列音(预亮);曲末列 next 为空。
  final List<TabNote> next;

  /// 当位和弦名(曲头前无锚则 null)。
  final String? chordLabel;

  /// 当列扫弦记号(卷弦/下扫/上扫;普通拨弦 null)。
  final ScoreStrumKind? strum;

  /// 当列所在小节(1 起)。
  final int barNumber;

  /// 小节内拍位(1..4)。
  final int beatInBar;
}

/// 主轴拍位 → 提示帧。当列 = 最后一个 ≤ 拍位(容差 1e-9)的列拍;
/// 曲头后但首列未到(前奏空拍期)= 引导帧(当列空、首列预亮);
/// 拍位还在曲头之前(预备数拍)返回 null。谱面无音也返回 null(空壳
/// 谱没有可提示的东西)。
PlayHintFrame? playHintAt(ScoreSheetLayout layout, double mainBeat) {
  // 列拍 = 伴奏谱去重升序拍位(tabNotes 已按拍排序,相邻去重即列序)。
  final beats = <double>[];
  for (final n in layout.tabNotes) {
    if (beats.isEmpty || beats.last != n.beat) beats.add(n.beat);
  }
  if (beats.isEmpty) return null;
  double? currentBeat;
  double? nextBeat;
  for (final b in beats) {
    if (b <= mainBeat + 1e-9) {
      currentBeat = b;
    } else {
      nextBeat = b;
      break;
    }
  }
  if (currentBeat == null) {
    // 曲头后、首列前(前奏空拍期):当列空、首列预亮,给新手「马上
    // 要弹的是这个」的引导;拍位照主轴网格报小节拍。
    if (mainBeat < 0) return null; // 预备数拍期
    return PlayHintFrame(
      current: const [],
      next: [
        for (final n in layout.tabNotes) if (n.beat == beats.first) n,
      ],
      chordLabel: null,
      strum: null,
      barNumber: (mainBeat ~/ beatsPerBar).floor() + 1,
      beatInBar: (mainBeat % beatsPerBar).floor() + 1,
    );
  }
  List<TabNote> notesAt(double? beat) => beat == null
      ? const []
      : [for (final n in layout.tabNotes) if (n.beat == beat) n];
  ScoreChordAnchor? chord;
  for (final c in layout.def.chords) {
    if (c.beat <= mainBeat + 1e-9) chord = c;
  }
  ScoreStrumKind? strum;
  for (final e in layout.def.strums) {
    if ((e.beat - currentBeat).abs() < 1e-9) strum = e.kind;
  }
  return PlayHintFrame(
    current: notesAt(currentBeat),
    next: notesAt(nextBeat),
    chordLabel: chord?.label,
    strum: strum,
    barNumber: (currentBeat ~/ beatsPerBar).floor() + 1,
    beatInBar: (currentBeat % beatsPerBar).floor() + 1,
  );
}

/// 提示条本体:头部一行(和弦名 + 拍位 + 扫弦记号)+ 四个弦格
/// (④③②① 左→右,与和弦图同序——新手照和弦图的方位找弦)。
/// frame = null 时显示预备期占位。
class PlayHintBar extends StatelessWidget {
  const PlayHintBar({super.key = const Key('play-hint-bar'), this.frame});

  final PlayHintFrame? frame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final f = frame;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (f == null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.av_timer, size: 20, color: colors.outline),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '跟着拍子数,开弹后这里逐列提示该弹的弦和品',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.outline),
                  ),
                ),
              ],
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  f.chordLabel ?? '·',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '第${f.barNumber}小节 · 拍${f.beatInBar}',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: colors.outline),
                ),
                const Spacer(),
                if (f.strum != null) _strumBadge(theme, f.strum!),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final string in const [4, 3, 2, 1])
                  _stringCell(
                    theme,
                    string: string,
                    current: _noteOn(f.current, string),
                    next: _noteOn(f.next, string),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static TabNote? _noteOn(List<TabNote> notes, int string) {
    for (final n in notes) {
      if (n.string == string) return n;
    }
    return null;
  }

  Widget _strumBadge(ThemeData theme, ScoreStrumKind kind) {
    final (:icon, :label) = switch (kind) {
      ScoreStrumKind.roll => (icon: Icons.waves, label: '卷弦'),
      ScoreStrumKind.strumDown => (icon: Icons.south, label: '下扫'),
      ScoreStrumKind.strumUp => (icon: Icons.north, label: '上扫'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.labelLarge),
      ],
    );
  }

  /// 弦格:弦名 + 该弦当列品数(点亮大字)/ 下一列品数(描边预亮)/
  /// 该弦两列都无音显示弱化的「—」。空弦品 0 照显(0 = 空弦拨响)。
  Widget _stringCell(
    ThemeData theme, {
    required int string,
    required TabNote? current,
    required TabNote? next,
  }) {
    final colors = theme.colorScheme;
    final label = Text(
      '$string弦',
      style: theme.textTheme.labelMedium?.copyWith(color: colors.outline),
    );
    String fretTextOf(TabNote note) => '${note.fret}';
    Widget body;
    if (current != null) {
      // 当列:实底胶囊点亮。
      body = Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: colors.onPrimaryContainer),
          child: Text(
            fretTextOf(current),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } else if (next != null) {
      // 下一列:描边预亮(小一号,弱色)。
      body = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: colors.outline),
          child: Text(
            fretTextOf(next),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } else {
      body = Text(
        '—',
        style: theme.textTheme.titleMedium?.copyWith(color: colors.outline),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [label, const SizedBox(height: 2), body],
    );
  }
}
