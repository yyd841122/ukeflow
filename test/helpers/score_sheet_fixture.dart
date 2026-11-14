import 'package:ukeflow/core/chart/score_sheet_defs.dart';
import 'package:ukeflow/core/model/chord.dart';
import 'package:ukeflow/core/model/tab_chart.dart';

/// 合成组合夹具(ADR-0013 内置曲删除后,谱面内核测试的固定入参):
/// 2 小节 8 拍——C 锚@4、卷弦@4(第2小节扫弦段 → 连音柱@6)、休止 6.5
/// 起 0.5 拍、滑音 4.5→5、震音@7、@7 堆(无扫弦,× 保留)。
///
/// 夹具刻意小而全:每个符号记号(锚/卷弦/休止/滑音/震音/堆/滑音对/
/// 长音组)各出现一次,断言逐符号可锁定,不依赖任何真实歌曲数据。
final sheetFixtureShape = ChordFingering(
  frets: [0, 1, 0, 3], // ④③②①;C 第一把位,baseFret 1 = 绝对品位。
  fingers: [0, 1, 2, 3],
  baseFret: 1,
  barres: const [],
);

final sheetFixtureDef = ScoreSheetDef(
  id: 'sheet-fixture',
  title: '夹具曲',
  artist: '测试',
  tabChartId: 'sheet-fixture-tab',
  melodyChartId: 'sheet-fixture-melody',
  melodyAlignBeats: 4,
  keySignature: '1=C',
  chords: [
    ScoreChordAnchor(beat: 4, label: 'C', fingering: sheetFixtureShape),
  ],
  strums: [ScoreStrumEvent(4, ScoreStrumKind.roll)],
  rests: [ScoreRestEvent(6.5, 0.5)],
  slides: [ScoreSlideEvent(4.5, 5)],
  tremolos: const [ScoreTremoloEvent(7)],
);

final sheetFixtureTab = TabChart(
  title: '夹具TAB',
  artist: '测试',
  tempo: 78,
  notes: [
    // C 堆@4:全落指形 → ×;卷弦拍 → 遮蔽。
    const TabNote(string: 4, fret: 0, beat: 4),
    const TabNote(string: 3, fret: 1, beat: 4),
    const TabNote(string: 2, fret: 0, beat: 4),
    const TabNote(string: 1, fret: 3, beat: 4),
    // 滑音对@4.5→5:品位不落 C 形(①=3)→ 数字保留。
    const TabNote(string: 1, fret: 7, beat: 4.5),
    const TabNote(string: 1, fret: 5, beat: 5),
    // @7 堆:无扫弦事件 → × 保留;震音记号同拍。
    const TabNote(string: 4, fret: 0, beat: 7),
    const TabNote(string: 3, fret: 1, beat: 7),
    const TabNote(string: 2, fret: 0, beat: 7),
    const TabNote(string: 1, fret: 3, beat: 7),
  ],
);

final sheetFixtureMelody = TabChart(
  title: '夹具旋律',
  artist: '测试',
  tempo: 78,
  notes: const [
    // 对齐 +4 后:@4「你」、@7「末」。
    TabNote(string: 2, fret: 3, beat: 0, lyric: '你'),
    TabNote(string: 1, fret: 2, beat: 3, lyric: '末'),
  ],
);
