import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 音频调度 API 守卫(2026-11-08 声画错拍事故,流水谱真机实录):
/// flutter_soloud 的 `playClocked` 是**锚点相对**语义(「相对此前 clocked
/// 调用」的持久锚点+重锚守卫),喂绝对引擎时刻会在锚点漂移后整体提前/
/// 推迟出声——正是「声音领先时间线」的根因。全仓音频管线一律用
/// `playScheduled`(绝对引擎时刻,与 getEngineTime 同一时间基)。
/// 本闸锁死:lib/ 内不得出现任何 `.playClocked(` 调用(文档注释提及放行)。
void main() {
  test('lib/ 无 playClocked 调用(绝对调度纪律,见 audio_engine.dart 注释)', () {
    final offenders = <String>[];
    for (final dir in ['lib/core', 'lib/features', 'lib/data']) {
      final root = Directory(dir);
      if (!root.existsSync()) continue;
      for (final file in root
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        for (final line in file.readAsLinesSync()) {
          if (line.contains('.playClocked(')) offenders.add('${file.path}: $line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '发现 playClocked 调用(锚点相对语义,禁用):\n${offenders.join('\n')}');
  });
}
