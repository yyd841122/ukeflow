import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/score/flowing_engraving.dart';
import 'package:ukeflow/core/score/reference_score.dart';

/// 原谱机比对导出工具(全量核对用):把渲染模型导出 JSON 到 /tmp/our_render.json,
/// 配合原谱 HTML(beat-id 同源)逐项机比。新歌核对、排版改动回归时复用。
void main() {
  test('导出渲染模型', () {
    final raw = File('assets/scores/sky-city-guistudy.json').readAsStringSync();
    final score = buildReferenceScore(jsonDecode(raw), pageTempoBpm: 80);
    final plan = buildEngravingPlan(score);
    final out = {
      'events': [
        for (final e in score.events)
          {
            'id': e.id,
            'measure': e.measureIndex + 1,
            'startTick': e.startTick,
            'rest': e.isRest,
            'durationValue': e.durationValue,
            'dots': e.dots,
            'topString': e.notes.isEmpty
                ? null
                : e.notes.map((n) => n.stringNo).reduce((a, b) => a < b ? a : b),
            'digits': [
              for (final n in e.notes)
                if (!n.isTieDestination) {'string': n.stringNo, 'fret': n.fret},
            ],
            'tieChord': e.notes.isNotEmpty && e.notes.every((n) => n.isTieDestination),
            'brushType': e.brushType,
          },
      ],
      'beams': [
        for (final b in plan.beams) [b.$1, b.$2],
      ],
      'brushes': [
        for (final b in plan.brushes)
          {'event': b.eventId, 'arpeggio': b.isArpeggio, 'up': b.up},
      ],
      'chords': [
        for (final e in score.events)
          if (e.chord != null) {'measure': e.measureIndex + 1, 'name': e.chord!.name},
      ],
      'sections': [
        for (final m in score.measures)
          if (m.section != null) {'measure': m.index + 1, 'name': m.section},
      ],
      'rests': [
        for (final e in score.events)
          if (e.isRest) {'id': e.id, 'measure': e.measureIndex + 1, 'cp': plan.rhythmOf(e.id)!.restCodePoint},
      ],
      'slides': [
        for (final e in score.events)
          for (final n in e.notes)
            if (n.hasSlideOut) {'event': e.id, 'string': n.stringNo},
      ],
    };
    File('/tmp/our_render.json').writeAsStringSync(jsonEncode(out));
    // ignore: avoid_print
    print('events=${score.events.length} beams=${plan.beams.length} brushes=${plan.brushes.length}');
  });
}
