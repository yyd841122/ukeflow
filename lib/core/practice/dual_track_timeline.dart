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
library;

import '../chart/score_sheet_defs.dart';
import '../model/tab_chart.dart';

/// 旋律轨播放侧移位(半音):C 调数据 → E 调合流。
const dualTrackSemitoneShift = 4;

/// 组合定义 + 两层谱卡 → 双轨合并谱(单轨示范直接用伴奏谱,不走这里)。
/// 出谱过 [validateTabChart](旋律最高 ①12 → ①16 仍合法),坏数据当场报错。
TabChart buildDualTrackChart(
  ScoreSheetDef def,
  TabChart tabChart,
  TabChart melodyChart,
) {
  return validateTabChart(
    TabChart(
      title: def.title,
      artist: def.artist,
      tempo: tabChart.tempo,
      notes: [
        // 伴奏轨:主轴原样。
        ...tabChart.notes,
        // 旋律轨:+20 拍对齐主轴(组合定义唯一记录处),+4 半音合流 E 调;
        // 歌词缀字随行(双轨播放的歌词高亮查谱面布局,不查时间轴)。
        for (final note in melodyChart.notes)
          TabNote(
            string: note.string,
            fret: note.fret + dualTrackSemitoneShift,
            beat: note.beat + def.melodyAlignBeats,
            lyric: note.lyric,
          ),
      ],
    ),
    context: '双轨混播(${def.title})',
  );
}
