import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/wav_pcm16.dart';
import 'package:ukeflow/core/scoring/strum_scorer.dart';
import 'package:ukeflow/features/play/scoring/chroma_debug_probe.dart';

import 'helpers/chroma_probe_fixtures.dart';

/// [DEBUG-chroma] 探针(工单 54):取证 JSON 的机器可读契约(meta.json
/// 是离线回灌的输入,字段名漂移=回灌工具静默坏)+ logcat 块格式 +
/// 测试宿主默认关(保护控制器测试零 IO)。
void main() {
  late List<String> logs;
  late Directory tmp;

  setUp(() {
    final armed = armChromaDebugProbe();
    logs = armed.logs;
    tmp = armed.dir;
  });

  /// 一份典型取证:C/G/G7 会话,3 槽(C 错、C 准、G 漏)+ 1 个未配对
  /// onset(oi=2,双触发旁证)。
  ChromaDebugDump sampleDump() {
    final bins = Float64List(12)..[0] = 0.6..[4] = 0.5..[7] = 0.4;
    ChromaDebugChromaRec chroma(int onset, bool paired) => ChromaDebugChromaRec(
      onsetIndex: onset,
      paired: paired,
      startSec: 10.0 + onset,
      endSec: 10.3 + onset,
      sampleCount: 13230,
      rms: 0.042,
      bins: bins,
      scores: const {'C': 0.54, 'G': 0.31, 'G7': 0.29},
      bestLabel: 'C',
      bestScore: 0.54,
    );
    return ChromaDebugDump(
      anchorSec: 10.0,
      periodMs: 1500,
      sampleRate: 44100,
      bufferStartSec: 9.8,
      bufferEndSec: 15.2,
      latencySec: 0.091,
      latencySource: 'calibrated',
      prepPairErrSec: const [-0.088, -0.095],
      chordsMidi: {
        'C': const [67, 60, 64, 72],
        'G': const [55, 62, 67, 71],
        'G7': const [55, 62, 65, 71],
      },
      threshold: 0.6,
      slots: const [
        ChromaDebugSlotRec(barIndex: 0, slotInBar: 0, beat: 4, chord: 'C'),
        ChromaDebugSlotRec(barIndex: 0, slotInBar: 2, beat: 5, chord: 'C'),
        ChromaDebugSlotRec(barIndex: 1, slotInBar: 0, beat: 8, chord: 'G'),
      ],
      verdicts: const [
        (judgment: StrumJudgment.wrong, errSec: -0.091),
        (judgment: StrumJudgment.onTime, errSec: 0.01),
        (judgment: StrumJudgment.missed, errSec: 0),
      ],
      onsets: const [
        ChromaDebugOnsetRec(engineSec: 10.5, beat: 4.02, periodMs: 1500),
        ChromaDebugOnsetRec(engineSec: 12.1, beat: 5.03, periodMs: 1500),
        ChromaDebugOnsetRec(engineSec: 13.9, beat: 6.9, periodMs: 1500),
      ],
      pairs: const [
        (targetIndex: 0, onsetIndex: 0, errSec: -0.091),
        (targetIndex: 1, onsetIndex: 1, errSec: 0.01),
      ],
      chroma: [chroma(0, true), chroma(1, true), chroma(2, false)],
      wav: wrapPcm16MonoWav(sampleRate: 44100, pcm16: Uint8List(44)),
    );
  }

  test('测试宿主默认关(探针不进控制器测试;强开可翻)', () {
    ChromaDebugProbe.forceEnabled = null;
    expect(
      ChromaDebugProbe.enabled,
      isFalse,
      reason: 'flutter test 宿主带 FLUTTER_TEST,探针默认关',
    );
  });

  test('dump:meta.json 落盘且机器可读(字段契约),wav 落盘', () async {
    await ChromaDebugProbe().dump(sampleDump());
    final sessions = Directory(
      '${tmp.path}/ukulele-chroma-dump',
    ).listSync().whereType<Directory>().toList();
    expect(sessions, hasLength(1), reason: '一次 dump 一个会话目录');
    final meta = File('${sessions.first.path}/meta.json');
    final wav = File('${sessions.first.path}/session.wav');
    final logTxt = File('${sessions.first.path}/log.txt');
    expect(meta.existsSync(), isTrue);
    expect(wav.existsSync(), isTrue);
    expect(
      logTxt.existsSync(),
      isTrue,
      reason: 'logcat 块同文落样张(环冲不丢头部行,工单54 retro)',
    );
    expect(
      logTxt.readAsStringSync(),
      contains('latency=91ms'),
      reason: 'log.txt 含延迟行',
    );

    final j = jsonDecode(meta.readAsStringSync()) as Map<String, Object?>;
    expect(j['schema'], 'chroma-debug-probe/1');
    expect(j['micSampleRate'], 44100);
    expect(j['threshold'], 0.6);
    expect(j['latencySource'], 'calibrated');
    expect(j['wav'], 'session.wav');
    expect(j['bufferStartSec'], closeTo(9.8, 1e-9)); // WAV 秒→样本换算锚点
    expect((j['chordsMidi'] as Map)['C'], [67, 60, 64, 72]);
    expect(j['slots'], hasLength(3));
    expect(
      (j['onsets'] as List).first,
      containsPair('beat', closeTo(4.02, 1e-9)),
    );
    expect(j['pairs'], hasLength(2));
    final chroma0 = (j['chroma'] as List).first as Map<String, Object?>;
    expect(chroma0['paired'], isTrue);
    expect((chroma0['bins'] as List), hasLength(12));
    expect((chroma0['scores'] as Map)['C'], closeTo(0.54, 1e-9));
    expect(j['verdicts'], hasLength(3));
  });

  test('dump:logcat 块含延迟行/逐槽行/未配对行/按和弦聚合行', () async {
    await ChromaDebugProbe().dump(sampleDump());
    expect(
      logs.any(
        (l) => l.contains('latency=91ms src=calibrated') && l.contains('threshold=0.6'),
      ),
      isTrue,
      reason: '延迟行:logs=$logs',
    );
    expect(
      logs.any(
        (l) =>
            l.contains('slot i=0 bar=0.0 chord=C') &&
            l.contains('verdict=wrong') &&
            l.contains('best=C 540'),
      ),
      isTrue,
      reason: '槽行带全模板分(×1000):logs=$logs',
    );
    expect(
      logs.any((l) => l.contains('slot i=2 bar=1.0 chord=G') && l.contains('verdict=missed')),
      isTrue,
      reason: '漏槽行无色度段:logs=$logs',
    );
    expect(
      logs.any((l) => l.contains('unpaired oi=2') && l.contains('rms=0.042')),
      isTrue,
    );
    expect(
      logs.any(
        (l) => l.contains('byChord C: match=2/2 wrong=1, G: match=0/1 wrong=0'),
      ),
      isTrue,
      reason: '按和弦聚合(漏槽计入总数不计 match):logs=$logs',
    );
    expect(
      logs.any((l) => l.contains('dump -> ') && l.contains('meta.json=')),
      isTrue,
      reason: '收尾行带落盘路径:logs=$logs',
    );
  });

  test('dump:落盘失败不抛、logcat 块先吐(取证不拦报告)', () async {
    ChromaDebugProbe.outputDirOverride = Directory('/proc/definitely-not-writable');
    await ChromaDebugProbe().dump(sampleDump()); // 落盘必败
    expect(
      logs.any((l) => l.contains('dump FAILED')),
      isTrue,
      reason: '失败行落 logcat:logs=$logs',
    );
    // logcat 块(判定现场)先于落盘,已完整。
    expect(logs.any((l) => l.contains('summary total=3')), isTrue);
  });

  test('passStart 行带封闭集与拍格', () {
    ChromaDebugProbe().passStart(
      chordsMidi: {
        'C': const [67, 60, 64, 72],
      },
      periodMs: 1500,
      targetCount: 24,
    );
    expect(
      logs.single,
      contains('chords={C:[67,60,64,72]} periodMs=1500.0 targets=24'),
    );
  });
}
