import 'package:flutter/material.dart';

import '../../core/audio/beat_scheduling.dart' show beatsPerBar;
import '../../core/model/strum_chart.dart';
import '../../core/model/strum_pattern.dart';
import '../../core/practice/play_timeline.dart';
import '../../core/practice/practice_state.dart';
import '../../data/chord_library.dart' show Chord;
import '../chords/chord_diagram.dart';

/// 跟练运行视图(GLOSSARY「跟练」的显示层):给定练习状态画全部视觉。
/// 版式:右手要看的在**上**——当前和弦指法卡、扫弦箭头条、拍号;
/// 唱的在下——段落标签与歌词提词(沉底)。薄渲染(ADR-0005):无时钟
/// 无动画,一切信息读 [practice],由跟练页以 ~16ms 轮询重灌;
/// 本组件自己不产生任何时间。
class PracticeView extends StatelessWidget {
  const PracticeView({
    super.key,
    required this.timeline,
    required this.practice,
    required this.pattern,
    required this.chords,
  });

  final PlayTimeline timeline;
  final PracticeState practice;

  /// 时间轴编译所用的节奏型(箭头条槽位排布来源)。
  final StrumPattern pattern;

  /// 和弦名 → 和弦(指法图数据)。谱面和弦已过白名单校验,恒可查。
  final Map<String, Chord> chords;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lyricIndex = practice.currentLine == null
        ? -1
        : timeline.lyrics.indexOf(practice.currentLine!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 上:右手弹奏提示 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: LinearProgressIndicator(
            key: const Key('progress'),
            value: timeline.totalBeats == 0
                ? 0
                : practice.beat / timeline.totalBeats,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ChordCard(
                chordName: practice.currentStrum?.chord,
                chord: _currentChord,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ArrowStrip(pattern: pattern, currentSlot: _currentSlot),
        ),
        const SizedBox(height: 4),
        Text(
          '${practice.beatInBar + 1}',
          key: const Key('beat-number'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        // ── 下:唱词 ──
        if (practice.currentSection?.section.label case final label?) ...[
          const SizedBox(height: 12),
          Text(
            label,
            key: const Key('section-label'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: scheme.primary),
          ),
        ],
        Expanded(
          child: _LyricsArea(lyrics: timeline.lyrics, currentIndex: lyricIndex),
        ),
      ],
    );
  }

  /// 当前和弦 = 当前扫弦动作携带的和弦(小节分配约定:换和弦即换小节)。
  Chord? get _currentChord {
    final name = practice.currentStrum?.chord;
    return name == null ? null : chords[name];
  }

  /// 当前点亮槽位。跨小节空档(下小节首槽是空拍)时上一小节的动作
  /// 不带入新小节,整行回描边待命。
  int? get _currentSlot {
    final strum = practice.currentStrum;
    if (strum == null || strum.barIndex != practice.beat ~/ beatsPerBar) {
      return null;
    }
    return strum.slotInBar;
  }
}

/// 歌词提词:上一行淡出、当前行大字高亮、后续两行渐淡,整块垂直居中。
/// 行随练习状态推进整体上移,即「歌词随节拍滚动」(阶梯式;平滑滚动
/// 需时间插值,归后续打磨)。
class _LyricsArea extends StatelessWidget {
  const _LyricsArea({required this.lyrics, required this.currentIndex});

  final List<PlayLyricEvent> lyrics;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (currentIndex < 0 || currentIndex >= lyrics.length) {
      return Center(
        child: Text('♪', style: TextStyle(color: scheme.outline, fontSize: 28)),
      );
    }
    final current = lyrics[currentIndex].line;
    // 歌词沉底(版式:弹奏提示在上、唱词在下);长歌词/大字超出可用
    // 高度时可滚(RenderFlex 溢出条纹在真机上就是内容被截断)。
    return Align(
      alignment: Alignment.bottomCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (currentIndex > 0)
              _ChordLyricLine(
                lyrics[currentIndex - 1].line,
                lyricStyle: TextStyle(
                  fontSize: 15,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                ),
                chordStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              ),
            const SizedBox(height: 10),
            _ChordLyricLine(
              current,
              key: const Key('lyric-current'),
              lyricStyle: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
                height: 1.3,
              ),
              chordStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            for (var ahead = 1; ahead <= 2; ahead++) ...[
              if (currentIndex + ahead < lyrics.length)
                _ChordLyricLine(
                  lyrics[currentIndex + ahead].line,
                  lyricStyle: TextStyle(
                    fontSize: 16,
                    color: scheme.onSurfaceVariant.withValues(
                      alpha: ahead == 1 ? 0.75 : 0.45,
                    ),
                  ),
                  chordStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant.withValues(
                      alpha: ahead == 1 ? 0.75 : 0.45,
                    ),
                  ),
                ),
              if (ahead < 2) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一行「和弦在歌词上方」的谱面行(GLOSSARY「文本谱」的可视化):
/// 和弦名按谱面偏移对齐到其后歌词块的上方,和弦与歌词块成对成列,
/// 超宽自动折行。和弦行恒占位(无和弦的块以空格占位),各列歌词基线对齐;
/// 和弦悬空(行尾和弦,如长音延续小节)即和弦名下无词,如实提示换和弦点。
class _ChordLyricLine extends StatelessWidget {
  const _ChordLyricLine(
    this.line, {
    super.key,
    required this.lyricStyle,
    required this.chordStyle,
  });

  final StrumLine line;
  final TextStyle lyricStyle;
  final TextStyle chordStyle;

  @override
  Widget build(BuildContext context) {
    // 按和弦偏移切块:(和弦名?, 歌词块);每块歌词自其和弦偏移处起。
    final chunks = <(String?, String)>[];
    var cursor = 0;
    for (var i = 0; i < line.chords.length; i++) {
      final mark = line.chords[i];
      if (mark.offset > cursor) {
        chunks.add((null, line.lyric.substring(cursor, mark.offset)));
      }
      final next = i + 1 < line.chords.length
          ? line.chords[i + 1].offset
          : line.lyric.length;
      chunks.add((mark.name, line.lyric.substring(mark.offset, next)));
      cursor = next;
    }
    if (cursor < line.lyric.length) {
      chunks.add((null, line.lyric.substring(cursor)));
    }
    if (chunks.isEmpty) {
      chunks.add((null, ' '));
    }

    return Wrap(
      spacing: 10,
      runSpacing: 2,
      children: [
        for (final (chord, text) in chunks)
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chord ?? ' ', style: chordStyle),
              Text(text.isEmpty ? ' ' : text, style: lyricStyle),
            ],
          ),
      ],
    );
  }
}

/// 当前和弦卡:和弦名 + 指法小图,主色容器突出(练习状态里「此刻按什么」)。
/// [chordName] 直接来自扫弦事件,不依赖查表;[chord] 查表成功才有指法小图
/// (和弦库缺位的降级路径下名字照走、小图缺席)。
class _ChordCard extends StatelessWidget {
  const _ChordCard({required this.chordName, required this.chord});

  final String? chordName;
  final Chord? chord;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onCard = scheme.onPrimaryContainer;
    return Container(
      key: const Key('chord-card'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chord != null) ...[
            ChordDiagram(
              key: const Key('chord-diagram'),
              fingering: chord!.primaryFingering,
              width: 76,
            ),
            const SizedBox(width: 14),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chordName ?? '—',
                key: const Key('chord-name'),
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: onCard,
                  height: 1.1,
                ),
              ),
              Text(
                '当前和弦',
                style: TextStyle(
                  fontSize: 12,
                  color: onCard.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一小节 8 槽一行均分(视觉语言与节奏型训练页一致):扫弦槽画 ↓/↑,
/// 空拍槽画圆点;当前动作主色点亮,本小节已扫淡出,未到描边待命。
class _ArrowStrip extends StatelessWidget {
  const _ArrowStrip({required this.pattern, required this.currentSlot});

  final StrumPattern pattern;
  final int? currentSlot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var slot = 0; slot < eighthsPerBar; slot++) ...[
          if (slot > 0) const SizedBox(width: 6),
          Expanded(child: _slotCell(slot, scheme)),
        ],
      ],
    );
  }

  Widget _slotCell(int slot, ColorScheme scheme) {
    final current = currentSlot;
    final isCurrent = current == slot;
    final isPlayed = current != null && slot < current;
    final stroke = pattern.slots[slot];
    final Color fill;
    final Color content;
    final Border? border;
    if (isCurrent) {
      fill = scheme.primary;
      content = scheme.onPrimary;
      border = null;
    } else if (isPlayed) {
      fill = scheme.surfaceContainerHighest;
      content = scheme.onSurfaceVariant;
      border = null;
    } else {
      fill = Colors.transparent;
      content = scheme.onSurface;
      border = Border.all(color: scheme.outlineVariant);
    }
    return Container(
      key: Key('play-slot-$slot'),
      height: 52,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: border,
      ),
      child: Center(
        child: stroke == null
            ? Text('·', style: TextStyle(color: content, height: 1))
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
}
