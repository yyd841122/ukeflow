/// 混播编译内核(工单 39 测试缝②,GLOSSARY「双轨混播」):组合定义 →
/// 双轨逐音事件时间轴。做法是**合并谱**:伴奏轨原样 + 旋律轨播放侧移位,
/// 合成一份指弹谱交给既有逐音编译/示范管线(compileTabTimeline +
/// TabNoteScheduler)——单一播放头、单一调度器,零引擎侧改动(复用指弹
/// 示范管线,工单 13)。
///
/// 旋律轨移位只发生在**播放侧**:旋律层数据发声在 C 调、TAB 层在 E 调,
/// 不移则 G/G# 打架(ADR-0008);+4 半音 = 同弦整数品上移,TabNote 的
/// frequency 随品位自动正确。显示不受影响(简谱行只显度数),各谱卡
/// 单独跟练仍原调不动。
///
/// 扫弦/卷弦发声(用户真机反馈 2026-10-24:印张的扫弦被拍平成同拍逐弦
/// 拨,效果不对):组合定义 `strums` 事件表标注的同一拍和弦音组,按
/// [ScoreStrumKind] 逐弦错峰——卷弦(慢扫)70ms/弦 ④→①,下/上扫
/// (快扫)25ms/弦,上扫 ①→④。只作用于谱面视图的播放谱;四线谱跟练
/// 仍用原谱原速同拍(ADR-0003 模型分界不动)。
library;

import '../chart/score_sheet_defs.dart';
import '../model/tab_chart.dart';

/// 旋律轨播放侧移位(半音):C 调数据 → E 调合流。
const dualTrackSemitoneShift = 4;

/// 卷弦(慢扫)逐弦错峰(毫秒,④→①)。
const rollStaggerMs = 70.0;

/// 快扫(下/上扫)逐弦错峰(毫秒)。
const strumStaggerMs = 25.0;

/// 组合定义 → 谱面视图的播放谱:[melodyChart] 非 null = 双轨混播
/// (旋律轨 +20 拍对齐主轴、+4 半音合流 E 调);伴奏轨按扫弦事件表
/// 逐弦错峰。出谱过 [validateTabChart](旋律最高 ①12 → ①16 仍合法)。
TabChart buildScorePlaybackChart(
  ScoreSheetDef def,
  TabChart tabChart, {
  TabChart? melodyChart,
}) {
  final staggered = _staggerStrums(def, tabChart);
  return validateTabChart(
    TabChart(
      title: def.title,
      artist: def.artist,
      tempo: tabChart.tempo,
      notes: [
        ...staggered,
        if (melodyChart != null)
          for (final note in melodyChart.notes)
            TabNote(
              string: note.string,
              fret: note.fret + dualTrackSemitoneShift,
              beat: note.beat + def.melodyAlignBeats,
              lyric: note.lyric,
            ),
      ],
    ),
    context: melodyChart == null
        ? '单轨示范(${def.title})'
        : '双轨混播(${def.title})',
  );
}

/// 扫弦错峰:事件拍上的和弦音组(录入序 = 低弦→高弦)按种类错峰;
/// 上扫发声序 ①→④,故高弦先出、低弦殿后。
List<TabNote> _staggerStrums(ScoreSheetDef def, TabChart tabChart) {
  if (def.strums.isEmpty) return tabChart.notes;
  // 毫秒 → 拍(该曲 tempo 下),错峰量与播放速度无关(编译期一次定)。
  double msToBeats(double ms) => ms * tabChart.tempo / 60000;

  final byBeat = <double, List<TabNote>>{};
  for (final note in tabChart.notes) {
    byBeat.putIfAbsent(note.beat, () => []).add(note);
  }
  final out = <TabNote>[];
  for (final note in tabChart.notes) {
    final kind = def.strums
        .where((e) => e.beat == note.beat)
        .map((e) => e.kind)
        .firstOrNull;
    if (kind == null) {
      out.add(note);
      continue;
    }
    final group = byBeat[note.beat]!
      ..sort((a, b) => b.string.compareTo(a.string)); // 低弦(④)→高弦(①)
    final lowToHighIndex = group.indexOf(note);
    final staggerMs = switch (kind) {
      ScoreStrumKind.roll => rollStaggerMs,
      ScoreStrumKind.strumDown => strumStaggerMs,
      ScoreStrumKind.strumUp => strumStaggerMs,
    };
    final position = switch (kind) {
      // 卷弦/下扫:④ 先响(低弦 j=0 不移),① 殿后。
      ScoreStrumKind.roll ||
      ScoreStrumKind.strumDown => lowToHighIndex * staggerMs,
      // 上扫:① 先响(高弦先出),④ 殿后。
      ScoreStrumKind.strumUp =>
        (group.length - 1 - lowToHighIndex) * staggerMs,
    };
    out.add(
      position == 0
          ? note
          : TabNote(
              string: note.string,
              fret: note.fret,
              beat: note.beat + msToBeats(position),
              lyric: note.lyric,
            ),
    );
  }
  return out;
}
