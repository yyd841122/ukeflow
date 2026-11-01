import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/features/play/scoring/chroma_debug_probe.dart';

/// [DEBUG-chroma] 探针测试缝(工单54):强开 + 落盘/日志覆盖一次就位,
/// tearDown 自动复位。三处用例(practice_scoring_controller_test 的
/// 端到端/封闭集回归、chroma_debug_probe_test)共用,漏复位不再可能。
({List<String> logs, Directory dir}) armChromaDebugProbe() {
  final logs = <String>[];
  final dir = Directory.systemTemp.createTempSync('chroma-probe');
  ChromaDebugProbe.forceEnabled = true;
  ChromaDebugProbe.outputDirOverride = dir;
  ChromaDebugProbe.logOverride = logs.add;
  addTearDown(() {
    ChromaDebugProbe.forceEnabled = null;
    ChromaDebugProbe.outputDirOverride = null;
    ChromaDebugProbe.logOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return (logs: logs, dir: dir);
}
