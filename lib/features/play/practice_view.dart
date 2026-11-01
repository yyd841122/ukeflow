import 'package:flutter/material.dart';

import '../../core/audio/beat_scheduling.dart' show beatsPerBar;
import '../../core/model/strum_chart.dart';
import '../../core/model/strum_pattern.dart';
import '../../core/practice/play_timeline.dart';
import '../../core/practice/practice_state.dart';
import '../../core/scoring/strum_scorer.dart';
import '../../core/ui/arrow_strip.dart';
import '../../data/chord_library.dart' show Chord;
import '../chords/chord_diagram.dart';

/// 跟练运行视图(GLOSSARY「跟练」的显示层):给定练习状态画全部视觉。
/// 版式:右手要看的在**上**——当前和弦指法卡(旁挂小号「下一和弦」预告)、
/// 扫弦箭头条、拍号;中段是唱词——段落标签与歌词提词(顶锚,进度条
/// 紧随其下,留白全部落在页面最底)。薄渲染(ADR-0005):无时钟无动画,
/// 一切信息读 [practice],由跟练页以 ~16ms 轮询重灌;本组件自己不产生
/// 任何时间。
class PracticeView extends StatelessWidget {
  const PracticeView({
    super.key,
    required this.timeline,
    required this.practice,
    required this.pattern,
    required this.chords,
    this.liveVerdicts,
  });

  final PlayTimeline timeline;
  final PracticeState practice;

  /// 时间轴编译所用的节奏型(箭头条槽位排布来源)。
  final StrumPattern pattern;

  /// 和弦名 → 和弦(指法图数据)。谱面和弦已过白名单校验,恒可查。
  final Map<String, Chord> chords;

  /// 实时判定(工单 36,谱序与 [timeline].strums 同序;null = 不在评分
  /// 会话)。按当前小节折到槽位传给箭头条染色。
  final List<StrumJudgment?>? liveVerdicts;

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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              ChordCard.current(
                chordName: practice.currentStrum?.chord,
                chord: _currentChord,
              ),
              if (_nextChordName case final nextName?)
                ChordCard.next(chordName: nextName, chord: chords[nextName]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ArrowStrip(
            pattern: pattern,
            currentSlot: _currentSlot,
            slotKeyPrefix: 'play-slot',
            verdicts: _slotVerdicts,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${practice.beatInBar + 1}',
          key: const Key('beat-number'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        // ── 中:唱词(顶锚,进度条紧随其后,留白不夹在中间) ──
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
          child: LayoutBuilder(
            builder: (context, box) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 歌词块收缩到内容实际高度(≤可用高度,给进度条留底线量);
                // 余高不足 24px(矮视口/横屏)钳到零——负 max 会直接
                // BoxConstraints 断言崩(审计 2026-10-16 #36)。
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: box.maxHeight < 24 ? 0 : box.maxHeight - 24,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: _lyricLines(scheme, lyricIndex),
                  ),
                ),
                // 下方余白 2:1(版式反馈):歌词侧更松、进度条下更紧。
                const Spacer(flex: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LinearProgressIndicator(
                    key: const Key('progress'),
                    value: timeline.totalBeats == 0
                        ? 0
                        : practice.beat / timeline.totalBeats,
                  ),
                ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _lyricLines(ColorScheme scheme, int lyricIndex) {
    if (lyricIndex < 0 || lyricIndex >= timeline.lyrics.length) {
      return Center(
        child: Text('♪', style: TextStyle(color: scheme.outline, fontSize: 28)),
      );
    }
    final current = timeline.lyrics[lyricIndex].line;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (lyricIndex > 0)
          _ChordLyricLine(
            timeline.lyrics[lyricIndex - 1].line,
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
          if (lyricIndex + ahead < timeline.lyrics.length)
            _ChordLyricLine(
              timeline.lyrics[lyricIndex + ahead].line,
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
    );
  }

  /// 当前和弦 = 当前扫弦动作携带的和弦(小节分配约定:换和弦即换小节)。
  Chord? get _currentChord {
    final name = practice.currentStrum?.chord;
    return name == null ? null : chords[name];
  }

  /// 下一和弦(俄罗斯方块预告的最小切片):自下一小节起,第一个与当前
  /// 和弦不同的和弦名;曲末/无名 → null。完整动作预告窗归工单 10。
  String? get _nextChordName {
    final currentName = practice.currentStrum?.chord;
    if (currentName == null) return null;
    final nextBar = practice.beat ~/ beatsPerBar + 1;
    for (final strum in timeline.strums) {
      if (strum.barIndex < nextBar) continue;
      if (strum.chord != null && strum.chord != currentName) {
        return strum.chord;
      }
    }
    return null;
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

  /// 当前小节各槽位的实时判定(工单 36):谱序判定折到当前小节的槽位,
  /// 与 `_currentSlot` 同一小节基准(beat ~/ beatsPerBar);无评分 null。
  List<StrumJudgment?>? get _slotVerdicts {
    final verdicts = liveVerdicts;
    if (verdicts == null) return null;
    final bar = practice.beat ~/ beatsPerBar;
    final slots = List<StrumJudgment?>.filled(eighthsPerBar, null);
    for (var i = 0; i < timeline.strums.length && i < verdicts.length; i++) {
      final strum = timeline.strums[i];
      if (strum.barIndex == bar) slots[strum.slotInBar] = verdicts[i];
    }
    return slots;
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

/// 和弦卡(三处共用形状,单一实现):指法小图 + 名字/题注一行。三个
/// 意图各配一套表皮——current(曲内当前和弦主卡,大图大字)/next(俄罗斯
/// 方块预告,弱化小卡)/prep(工单 53 预备数拍期的首小节预告:倒计数字旁
/// 的「进曲前把手摆到位」,数据是静态首小节和弦而非预告窗,仅随倒计
/// 面板存在,进曲即隐)。降级语义在此单一实现:名字直接来自扫弦事件/
/// 时间轴,不依赖查表;查表成功才有指法小图,和弦库缺位的降级路径下
/// 名字照走、小图缺席。
class ChordCard extends StatelessWidget {
  const ChordCard.current({super.key, required this.chordName, this.chord})
    : _intent = _CardIntent.current;

  const ChordCard.next({super.key, required this.chordName, this.chord})
    : _intent = _CardIntent.next;

  const ChordCard.prep({super.key, required this.chordName, this.chord})
    : _intent = _CardIntent.prep;

  final _CardIntent _intent;

  /// 和弦名:直接来自扫弦事件/时间轴,不依赖查表(库缺位时名字照走)。
  final String? chordName;

  /// 查表所得和弦(指法图数据);null = 小图缺席。
  final Chord? chord;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (
      cardKey,
      diagramKey,
      nameKey,
      containerColor,
      onCardColor,
      padding,
      gap,
      diagramWidth,
      nameFontSize,
      caption,
      captionFontSize,
    ) = switch (_intent) {
      _CardIntent.current => (
        const Key('chord-card'),
        const Key('chord-diagram'),
        const Key('chord-name'),
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        14.0,
        76.0,
        30.0,
        '当前和弦',
        12.0,
      ),
      _CardIntent.next => (
        const Key('next-chord-card'),
        const Key('next-chord-diagram'),
        const Key('next-chord-name'),
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        8.0,
        44.0,
        18.0,
        '下一和弦',
        10.0,
      ),
      _CardIntent.prep => (
        const Key('prep-first-chords'),
        const Key('prep-first-chord-diagram'),
        const Key('prep-first-chord-name'),
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        8.0,
        56.0,
        20.0,
        '第 1 小节',
        12.0,
      ),
    };
    return Container(
      key: cardKey,
      padding: padding,
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chord != null) ...[
            ChordDiagram(
              key: diagramKey,
              fingering: chord!.primaryFingering,
              width: diagramWidth,
            ),
            SizedBox(width: gap),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chordName ?? '—',
                key: nameKey,
                style: TextStyle(
                  fontSize: nameFontSize,
                  fontWeight: FontWeight.w700,
                  color: onCardColor,
                  height: 1.1,
                ),
              ),
              Text(
                caption,
                style: TextStyle(
                  fontSize: captionFontSize,
                  color: onCardColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 表皮意图(当前/下一/预备):形状同一,调色/尺寸/键/题注各配一套。
enum _CardIntent { current, next, prep }


