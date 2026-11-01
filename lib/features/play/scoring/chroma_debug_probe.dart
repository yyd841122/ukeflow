/// [DEBUG-chroma] 插桩(工单 54):「错」判定与和弦类型强相关(C 槽
/// 密集错、G7 全过)的真机定案探针。评分会话 finish 时一次性吐出:
/// - logcat 块:延迟校准、逐槽(槽位/和弦/时机/窗长/色度 top 类/全模板
///   分/bestMatch)、未配对 onset、按和弦聚合;
/// - cache 目录样张:`meta.json`(全量元数据,机器可读)+ `session.wav`
///   (整遍滤前 PCM,离线回灌重放任意窗策略/归一/模板/阈值候选)。
///
/// debug 限定:release(kDebugMode=false)与测试宿主(FLUTTER_TEST)
/// 恒关,控制器内为 null 桩,零开销零 IO。测试经 [forceEnabled] +
/// [outputDirOverride] + [logOverride] 强开(探针自测与控制器级端到端)。
///
/// 样张自含:logcat 块同文落 `log.txt` 进样张目录(工单54 retro:logcat
/// 环形缓冲分钟级即冲掉头部行,两次真机拔取都丢过 passStart/延迟行——
/// 回灌只拉目录即可,logcat 降级为便利通道)。
///
/// 定案纪律(票面):探针只取证不修改——窗策略/归一/模板/阈值候选全部
/// 留给数据回来后的修复票,这里不预设方向。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/scoring/strum_scorer.dart' show StrumJudgment;

/// 逐槽记录:谱面定位(小节/槽位,与报告轨道对得上)+ 拍位与目标和弦。
final class ChromaDebugSlotRec {
  const ChromaDebugSlotRec({
    required this.barIndex,
    required this.slotInBar,
    required this.beat,
    required this.chord,
  });

  final int barIndex;
  final int slotInBar;
  final double beat;
  final String? chord;
}

/// 逐 onset 记录:检出时刻与拍位(拍域换算审计用)。
final class ChromaDebugOnsetRec {
  const ChromaDebugOnsetRec({
    required this.engineSec,
    required this.beat,
    required this.periodMs,
  });

  final double engineSec;
  final double beat;
  final double periodMs;
}

/// 逐 onset 色度证据:窗 + 量化证据(与判定同算式重算,窗口单源)。
final class ChromaDebugChromaRec {
  const ChromaDebugChromaRec({
    required this.onsetIndex,
    required this.paired,
    required this.startSec,
    required this.endSec,
    required this.sampleCount,
    required this.rms,
    required this.bins,
    required this.scores,
    required this.bestLabel,
    required this.bestScore,
  });

  final int onsetIndex;

  /// 是否配上了某扫弦槽(未配对 onset 的色度照样取证:双触发/跟丢
  /// 手位滞留的旁证)。
  final bool paired;

  final double startSec;
  final double endSec;
  final int sampleCount;
  final double rms;

  /// 12 维 L2 归一色度(下标 = 音高类,C=0)。
  final Float64List bins;

  /// 全模板余弦得分(键 = 会话和弦名)。
  final Map<String, double> scores;
  final String? bestLabel;
  final double bestScore;
}

/// 一次 finish 的全量取证(控制器抽取,探针只管序列化与落盘)。
final class ChromaDebugDump {
  const ChromaDebugDump({
    required this.anchorSec,
    required this.periodMs,
    required this.sampleRate,
    required this.bufferStartSec,
    required this.bufferEndSec,
    required this.latencySec,
    required this.latencySource,
    required this.prepPairErrSec,
    required this.chordsMidi,
    required this.threshold,
    required this.slots,
    required this.verdicts,
    required this.onsets,
    required this.pairs,
    required this.chroma,
    required this.wav,
  });

  final double anchorSec;
  final double periodMs;

  /// 麦采样率(meta 的秒↔样本换算锚,单源 [micSampleRate] 常量)。
  final int sampleRate;

  /// 整遍缓冲的引擎秒端点:WAV 样本 0 = [bufferStartSec]
  /// (离线回灌的秒→样本换算:sampleIndex = (t − start) × rate)。
  final double? bufferStartSec;
  final double? bufferEndSec;

  /// 链路延迟与本遍取值来源(calibrated = 预备中位数,persisted = 回退)。
  final double latencySec;
  final String latencySource;
  final List<double> prepPairErrSec;

  /// 会话封闭集:和弦名 → 主指法发声 midi(模板从它构造,离线可重建)。
  final Map<String, List<int>> chordsMidi;
  final double threshold;

  /// 谱序槽位([ChromaDebugSlotRec])与逐槽判定(枚举过探针,序列化
  /// 边缘才转字符串;聚合走枚举穷尽 switch,新判定值漏计即编译红)。
  final List<ChromaDebugSlotRec> slots;
  final List<({StrumJudgment judgment, double errSec})> verdicts;

  final List<ChromaDebugOnsetRec> onsets;

  /// 配对(槽下标, onset 下标, 时机误差秒)。
  final List<({int targetIndex, int onsetIndex, double errSec})> pairs;

  final List<ChromaDebugChromaRec> chroma;

  /// 整遍缓冲的 WAV(PCM16 mono);缓冲空为 null。
  final Uint8List? wav;
}

/// 色度调试探针(工单 54)。生命周期:每遍 onPassStart 时 [passStart]
/// 打头,finishSession 时 [dump] 一次性取证落盘。无实例状态,测试缝全走
/// 静态覆盖([forceEnabled]/[outputDirOverride]/[logOverride])。
class ChromaDebugProbe {
  ChromaDebugProbe();

  /// 强开开关(测试缝):非 null 时无视 kDebugMode/FLUTTER_TEST 判定。
  @visibleForTesting
  static bool? forceEnabled;

  /// 落盘根目录覆盖(测试缝):缺省为应用 cache 目录。
  @visibleForTesting
  static Directory? outputDirOverride;

  /// 日志出口覆盖(测试缝):缺省 debugPrint(logcat flutter tag)。
  @visibleForTesting
  static void Function(String line)? logOverride;

  /// debug 构建且非测试宿主才启用:控制器侧 null 桩,release/测试零开销。
  static bool get enabled =>
      forceEnabled ?? (kDebugMode && !Platform.environment.containsKey('FLUTTER_TEST'));

  void _log(String line) =>
      (logOverride ?? debugPrint)('[DEBUG-chroma] $line');

  /// 遍开始(logcat 打头:封闭集与拍格便于对齐多次会话的日志)。
  void passStart({
    required Map<String, List<int>> chordsMidi,
    required double periodMs,
    required int targetCount,
  }) {
    _log('pass start: chords=${_chordsRepr(chordsMidi)} periodMs=$periodMs targets=$targetCount');
  }

  /// finish 一次性取证:先吐 logcat 块(即便落盘失败,判定现场也已在
  /// 日志里,且同文将随 log.txt 落盘),再落 meta.json + session.wav +
  /// log.txt 到 cache 子目录。
  Future<void> dump(ChromaDebugDump d) async {
    final lines = <String>[];
    void log(String line) {
      (logOverride ?? debugPrint)('[DEBUG-chroma] $line');
      lines.add(line);
    }

    _dumpLogcat(d, log);
    final String dirPath;
    try {
      dirPath = await _writeSample(d, lines);
      final meta = File('$dirPath/meta.json');
      final wav = File('$dirPath/session.wav');
      log(
        'dump -> $dirPath '
        '(meta.json=${meta.existsSync() ? _kb(meta.lengthSync()) : "-"} '
        'wav=${wav.existsSync() ? _kb(wav.lengthSync()) : "-"})',
      );
    } on Object catch (e) {
      log('dump FAILED:$e');
    }
  }

  // ── logcat 块 ────────────────────────────────────────────────────

  void _dumpLogcat(ChromaDebugDump d, void Function(String line) log) {
    final errs = [
      for (final e in d.prepPairErrSec) _ms(e),
    ].join(',');
    log(
      'latency=${_ms(d.latencySec)}ms src=${d.latencySource} '
      'prepPairs=${d.prepPairErrSec.length} errs=[$errs]ms threshold=${d.threshold}',
    );
    final judgmentByTarget = <int, ({StrumJudgment judgment, double errSec})>{
      for (var i = 0; i < d.verdicts.length; i++) i: d.verdicts[i],
    };
    final onsetByTarget = {for (final p in d.pairs) p.targetIndex: p};
    final chromaByOnset = {for (final c in d.chroma) c.onsetIndex: c};
    for (var i = 0; i < d.slots.length; i++) {
      final slot = d.slots[i];
      final verdict = judgmentByTarget[i];
      final pair = onsetByTarget[i];
      log(
        'slot i=$i bar=${slot.barIndex}.${slot.slotInBar} '
        'chord=${slot.chord ?? "-"} tgtBeat=${slot.beat.toStringAsFixed(2)} '
        'onset=${pair?.onsetIndex ?? "-"} err=${verdict == null ? "-" : '${_ms(verdict.errSec)}ms'} '
        'verdict=${verdict?.judgment.name ?? "-"}${_chromaTail(chromaByOnset, pair?.onsetIndex)}',
      );
    }
    final pairedOnsets = {for (final p in d.pairs) p.onsetIndex};
    for (final c in d.chroma) {
      if (pairedOnsets.contains(c.onsetIndex)) continue;
      log(
        'unpaired oi=${c.onsetIndex} beat=${d.onsets[c.onsetIndex].beat.toStringAsFixed(2)} '
        'win=${_ms(c.endSec - c.startSec)}ms n=${c.sampleCount} rms=${c.rms.toStringAsFixed(3)} '
        '${_topClasses(c)} best=${c.bestLabel ?? "-"} ${c.bestScore.toStringAsFixed(3)}',
      );
    }
    log(_summaryLine(d, judgmentByTarget));
  }

  /// 槽行尾的色度段(配对了才有窗):窗长/样本/RMS/top 类/全模板分/best。
  String _chromaTail(Map<int, ChromaDebugChromaRec> chromaByOnset, int? onsetIndex) {
    if (onsetIndex == null) return '';
    final c = chromaByOnset[onsetIndex];
    if (c == null) return '';
    final scores = [
      for (final e in c.scores.entries) '${e.key}:${(e.value * 1000).round()}',
    ].join(' ');
    return ' | win=${_ms(c.endSec - c.startSec)}ms n=${c.sampleCount} '
        'rms=${c.rms.toStringAsFixed(3)} ${_topClasses(c)} | $scores '
        'best=${c.bestLabel ?? "-"} ${(c.bestScore * 1000).round()}';
  }

  /// 色度 top 3 音高类(归一权重 ×1000)。
  String _topClasses(ChromaDebugChromaRec c) {
    final order = List<int>.generate(12, (i) => i)
      ..sort((a, b) => c.bins[b].compareTo(c.bins[a]));
    return 'top=${[
      for (final i in order.take(3))
        '${_pcName(i)}:${(c.bins[i] * 1000).round()}',
    ].join(' ')}';
  }

  String _summaryLine(
    ChromaDebugDump d,
    Map<int, ({StrumJudgment judgment, double errSec})> judgmentByTarget,
  ) {
    // 枚举穷尽 switch 计数:StrumJudgment 增值即编译红,不静默漏计。
    var onTime = 0, early = 0, late = 0, wrong = 0, missed = 0;
    for (final v in d.verdicts) {
      switch (v.judgment) {
        case StrumJudgment.onTime:
          onTime++;
        case StrumJudgment.early:
          early++;
        case StrumJudgment.late:
          late++;
        case StrumJudgment.wrong:
          wrong++;
        case StrumJudgment.missed:
          missed++;
      }
    }
    final byChord = <String, List<int>>{}; // chord → [matched, wrong, total]
    for (var i = 0; i < d.slots.length; i++) {
      final chord = d.slots[i].chord;
      if (chord == null) continue;
      final agg = byChord.putIfAbsent(chord, () => [0, 0, 0]);
      final judgment = judgmentByTarget[i]?.judgment;
      if (judgment == null) continue;
      agg[2]++;
      if (judgment != StrumJudgment.missed) agg[0]++;
      if (judgment == StrumJudgment.wrong) agg[1]++;
    }
    final byChordRepr = [
      for (final e in byChord.entries)
        '${e.key}: match=${e.value[0]}/${e.value[2]} wrong=${e.value[1]}',
    ].join(', ');
    final matched = onTime + early + late + wrong;
    return 'summary total=${d.slots.length} matched=$matched '
        '(onTime=$onTime early=$early late=$late wrong=$wrong) '
        'missed=$missed | byChord $byChordRepr';
  }

  // ── 样张落盘 ─────────────────────────────────────────────────────

  Future<String> _writeSample(ChromaDebugDump d, List<String> logLines) async {
    final root = outputDirOverride ?? await getApplicationCacheDirectory();
    final now = DateTime.now();
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}ukulele-chroma-dump'
      '${Platform.pathSeparator}'
      '${now.year}${_p2(now.month)}${_p2(now.day)}-${_p2(now.hour)}${_p2(now.minute)}${_p2(now.second)}',
    );
    await dir.create(recursive: true);
    // WAV 先落、meta.json 收尾当「完成」标记:见到 meta 即样张齐全;
    // log.txt = logcat 块同文(logcat 环会冲头部行,样张自含)。
    final wav = d.wav;
    if (wav != null) {
      await File('${dir.path}${Platform.pathSeparator}session.wav').writeAsBytes(wav);
    }
    if (logLines.isNotEmpty) {
      await File('${dir.path}${Platform.pathSeparator}log.txt')
          .writeAsString('${logLines.join('\n')}\n');
    }
    await File(
      '${dir.path}${Platform.pathSeparator}meta.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(_metaMap(d, now)));
    return dir.path;
  }

  Map<String, Object?> _metaMap(ChromaDebugDump d, DateTime now) => {
    'schema': 'chroma-debug-probe/1',
    'capturedAt': now.toIso8601String(),
    'micSampleRate': d.sampleRate,
    'threshold': d.threshold,
    'anchorSec': d.anchorSec,
    'periodMs': d.periodMs,
    'bufferStartSec': d.bufferStartSec,
    'bufferEndSec': d.bufferEndSec,
    'latencySec': d.latencySec,
    'latencySource': d.latencySource,
    'prepPairErrSec': d.prepPairErrSec,
    'chordsMidi': d.chordsMidi,
    'slots': [
      for (var i = 0; i < d.slots.length; i++)
        {
          'i': i,
          'bar': d.slots[i].barIndex,
          'slotInBar': d.slots[i].slotInBar,
          'beat': d.slots[i].beat,
          'chord': d.slots[i].chord,
        },
    ],
    'verdicts': [
      for (var i = 0; i < d.verdicts.length; i++)
        {
          'i': i,
          'judgment': d.verdicts[i].judgment.name,
          'errSec': d.verdicts[i].errSec,
        },
    ],
    'onsets': [
      for (var i = 0; i < d.onsets.length; i++)
        {
          'i': i,
          'engineSec': d.onsets[i].engineSec,
          'beat': d.onsets[i].beat,
          'periodMs': d.onsets[i].periodMs,
        },
    ],
    'pairs': [
      for (final p in d.pairs)
        {'target': p.targetIndex, 'onset': p.onsetIndex, 'errSec': p.errSec},
    ],
    'chroma': [
      for (final c in d.chroma)
        {
          'onset': c.onsetIndex,
          'paired': c.paired,
          'startSec': c.startSec,
          'endSec': c.endSec,
          'nSamples': c.sampleCount,
          'rms': c.rms,
          'bins': c.bins.toList(),
          'scores': c.scores,
          'best': c.bestLabel,
          'bestScore': c.bestScore,
        },
    ],
    'wav': d.wav == null ? null : 'session.wav',
  };

  // ── 小工具 ───────────────────────────────────────────────────────

  String _chordsRepr(Map<String, List<int>> chordsMidi) => '{'
      '${chordsMidi.entries.map((e) => '${e.key}:[${e.value.join(",")}]').join(', ')}'
      '}';

  static const _pcNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

  String _pcName(int pc) => _pcNames[pc % 12];

  String _ms(double sec) => (sec * 1000).round().toString();

  String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)}KB';

  String _p2(int v) => v.toString().padLeft(2, '0');
}
