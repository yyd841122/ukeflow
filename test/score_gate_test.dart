import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/score/reference_score.dart';
import 'package:ukeflow/core/score/score_gate.dart';

/// 票08 换歌体检:变异电池锁定「体检与守门同源」。
///
/// 对真实一手数据(《天空之城》)每条规则注入一处违例:转换器必须拒绝
/// 且体检必须标出同一条规则;守门抛出的消息 = 体检首条违例的消息
/// (同一趟 walk,顺序一致)。好谱两边都放行,清点真值逐项锁定。
void main() {
  final raw = File('assets/scores/sky-city-guistudy.json').readAsStringSync();
  final source = jsonDecode(raw);

  /// 深拷贝后注入一处违例。
  Object mutated(void Function(Map src) mutate) {
    final copy = jsonDecode(jsonEncode(source)) as Map;
    mutate(copy);
    return copy;
  }

  Map masterOf(Map src, int measureNo) =>
      (src['masterBars'] as List)[measureNo - 1] as Map;

  Map? beatAt(Map src, int measureNo, bool withNotes) {
    final bar =
        ((src['tracks'] as List)[0]['staves'] as List)[0]['bars'][measureNo - 1]
            as Map;
    for (final voice in bar['voices'] as List) {
      for (final beat in (voice as Map)['beats'] as List) {
        if (beat is! Map || beat['isEmpty'] == true) continue;
        final hasNotes =
            beat['notes'] is List && (beat['notes'] as List).isNotEmpty;
        if (!withNotes || hasNotes) return beat;
      }
    }
    return null;
  }

  /// 指定小节(1 起)第一个非空节拍(休止也算,供节拍级变异)。
  Map beatAny(Map src, int measureNo) {
    final beat = beatAt(src, measureNo, false);
    if (beat == null) fail('第 $measureNo 小节无非空节拍');
    return beat;
  }

  /// 指定小节第一个带音的节拍(供音符级变异)。
  Map beatWithNote(Map src, int measureNo) {
    final beat = beatAt(src, measureNo, true);
    if (beat == null) fail('第 $measureNo 小节无带音节拍');
    return beat;
  }

  Map noteOf(Map src, int measureNo) =>
      (beatWithNote(src, measureNo)['notes'] as List).first as Map;

  /// 同源锁定主断言:体检标出该规则(期望三态/小节/消息关键词),且
  /// 转换器守门抛出的消息 = 体检首条违例消息。
  void expectViolation(
    Object src, {
    required String ruleId,
    required ScoreHealthVerdict verdict,
    int? measure,
    String? messageContains,
  }) {
    final report = checkScoreHealth(src, pageTempoBpm: 80);
    expect(
      report.violations.map((v) => v.ruleId),
      contains(ruleId),
      reason: '体检应标出 $ruleId,实得 ${report.violations.map((v) => v.ruleId)}',
    );
    expect(report.verdict, verdict, reason: '$ruleId 应判 $verdict');
    final hit = report.violations.firstWhere((v) => v.ruleId == ruleId);
    if (measure != null) {
      expect(hit.measure, measure, reason: '$ruleId 应定位第 $measure 小节');
    }
    if (messageContains != null) {
      expect(hit.message, contains(messageContains));
    }
    if (verdict == ScoreHealthVerdict.ready) {
      expect(() => buildReferenceScore(src, pageTempoBpm: 80), returnsNormally);
    } else {
      expect(
        () => buildReferenceScore(src, pageTempoBpm: 80),
        throwsA(isA<ScoreImportException>()
            .having((e) => e.message, 'message', report.firstMessage)),
      );
    }
  }

  group('好谱:体检放行且清点真值锁定', () {
    late ScoreHealthReport report;
    setUpAll(() {
      report = checkScoreHealth(source, pageTempoBpm: 80);
    });

    test('三态 = 可练,零违例,带转换产物', () {
      expect(report.verdict, ScoreHealthVerdict.ready);
      expect(report.violations, isEmpty);
      expect(report.ok, isTrue);
      expect(report.score, isNotNull);
      expect(report.score!.durationSeconds, report.durationSeconds);
    });

    test('谱面概览:标题/调弦/拍号/规模/曲长', () {
      expect(report.title, '天空之城');
      expect(report.artist, '久石让');
      expect(report.tuning1to4, [69, 64, 60, 67]);
      expect(report.capo, 0);
      expect(report.timeSignatures, {'4/4'});
      expect(report.measureCount, 51);
      expect(report.eventCount, 317);
      expect(report.noteCount, 557);
      expect(report.durationSeconds, closeTo(152.8536585, 1e-6));
    });

    test('支持记号清点:扫弦/泛音/滑出/延音/段落/变速', () {
      expect(report.featureNotes, [
        '扫弦/琶音 ×85',
        '自然泛音 ×4',
        '滑出 ×1',
        '延音 ×13',
        '段落标记 ×5',
        '第 50 小节起 80→82 BPM',
      ]);
    });
  });

  group('变异电池·能力类(缺规则待补,资料仍可信)', () {
    test('反复:反复起点', () {
      expectViolation(mutated((s) => masterOf(s, 6)['isRepeatStart'] = true),
          ruleId: 'repeat-start',
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6,
          messageContains: '反复');
    });
    test('反复:反复次数', () {
      expectViolation(mutated((s) => masterOf(s, 6)['repeatCount'] = 2),
          ruleId: 'repeat-count',
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6,
          messageContains: '反复');
    });
    test('反复:反复结尾替换', () {
      expectViolation(mutated((s) => masterOf(s, 6)['alternateEndings'] = [1]),
          ruleId: 'repeat-endings',
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6,
          messageContains: '反复');
    });
    test('反复:跳转记号', () {
      expectViolation(mutated((s) => masterOf(s, 6)['directions'] = [{}]),
          ruleId: 'directions',
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6,
          messageContains: '跳转');
    });
    test('其他记号:弱起小节', () {
      expectViolation(mutated((s) => masterOf(s, 1)['isAnacrusis'] = true),
          ruleId: 'anacrusis',
          verdict: ScoreHealthVerdict.needsRules,
          measure: 1,
          messageContains: '弱起');
    });
    test('其他记号:摇摆节奏', () {
      expectViolation(mutated((s) => masterOf(s, 6)['tripletFeel'] = 1),
          ruleId: 'triplet-feel',
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6);
    });
    test('效果记号:延长记号', () {
      expectViolation(mutated((s) => masterOf(s, 6)['fermata'] = {'x': 1}),
          ruleId: 'fermata',
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6);
    });
    test('变速:渐变变速', () {
      expectViolation(
          mutated((s) =>
              masterOf(s, 6)['tempoAutomation'] = {'isLinear': true}),
          ruleId: 'tempo-linear',
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6,
          messageContains: '变速');
    });
    test('变速:非拍头变速点', () {
      expectViolation(
          mutated((s) => masterOf(s, 6)['tempoAutomation'] =
              {'isLinear': false, 'ratioPosition': 0.5, 'value': 80}),
          ruleId: 'tempo-ratio',
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6,
          messageContains: '变速');
    });
    test('拍号:分母不在支持集', () {
      expectViolation(mutated((s) => masterOf(s, 6)['timeSignatureDenominator'] = 3),
          ruleId: 'time-signature',
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6,
          messageContains: '拍号');
    });
    test('声部:多轨', () {
      expectViolation(
          mutated((s) =>
              (s['tracks'] as List).add(jsonDecode(jsonEncode(s['tracks'][0])))),
          ruleId: 'multi-track',
          verdict: ScoreHealthVerdict.needsRules,
          messageContains: '曲轨');
    });
    test('声部:多谱表', () {
      expectViolation(
          mutated((s) => ((s['tracks'] as List)[0]['staves'] as List)
              .add(jsonDecode(jsonEncode(s['tracks'][0]['staves'][0])))),
          ruleId: 'multi-track',
          verdict: ScoreHealthVerdict.needsRules,
          messageContains: '多谱表');
    });
    test('声部:同小节多声部', () {
      expectViolation(
          mutated((s) {
            final bar = ((s['tracks'] as List)[0]['staves'] as List)[0]['bars'][5]
                as Map;
            (bar['voices'] as List)
                .add(jsonDecode(jsonEncode((bar['voices'] as List).first)));
          }),
          ruleId: 'multi-voice',
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6,
          messageContains: '声部');
    });

    void expectBeatEffect(String field, Object value, String ruleId) {
      expectViolation(
          mutated((s) => beatAny(s, 6)[field] = value),
          ruleId: ruleId,
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6);
    }

    test('变速:小节中途变速', () {
      expectBeatEffect('automations', [
        {'type': 0}
      ], 'tempo-mid');
    });
    test('效果记号:装饰音', () {
      expectBeatEffect('graceType', 1, 'grace');
    });
    test('连音/时值:不支持的时值', () {
      expectBeatEffect('duration', 3, 'duration-value');
    });
    test('连音/时值:附点超界', () {
      expectBeatEffect('dots', 4, 'dots');
    });
    test('连音/时值:三连音', () {
      expectViolation(
          mutated((s) {
            final beat = beatAny(s, 6);
            beat['tupletNumerator'] = 3;
            beat['tupletDenominator'] = 2;
          }),
          ruleId: 'tuplet',
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6,
          messageContains: '连音');
    });
    test('效果记号:显式符杠分组', () {
      expectBeatEffect('beamingMode', 1, 'beaming');
    });
    test('效果记号:渐入', () {
      expectBeatEffect('fadeIn', true, 'fade-in');
    });
    test('效果记号:Rasgueado', () {
      expectBeatEffect('hasRasgueado', true, 'rasgueado');
    });
    test('效果记号:Pop', () {
      expectBeatEffect('pop', true, 'pop');
    });
    test('效果记号:Slap', () {
      expectBeatEffect('slap', true, 'slap');
    });
    test('效果记号:点弦', () {
      expectBeatEffect('tap', true, 'tap');
    });
    test('效果记号:摇把', () {
      expectBeatEffect('whammyBarType', 1, 'whammy-bar');
    });
    test('效果记号:扫弦类型无效', () {
      expectBeatEffect('brushType', 9, 'brush-type');
    });
    test('效果记号:揉弦', () {
      expectBeatEffect('vibrato', 1, 'beat-vibrato');
    });
    test('效果记号:拨弦方向', () {
      expectBeatEffect('pickStroke', 1, 'pick-stroke');
    });
    test('效果记号:震音', () {
      expectBeatEffect('tremoloSpeed', 1, 'tremolo');
    });
    test('效果记号:渐强渐弱', () {
      expectBeatEffect('crescendo', 1, 'crescendo');
    });

    void expectNoteEffect(String field, Object value, String ruleId) {
      expectViolation(
          mutated((s) => noteOf(s, 6)[field] = value),
          ruleId: ruleId,
          verdict: ScoreHealthVerdict.needsRules,
          measure: 6);
    }

    test('音符效果:推弦', () {
      expectNoteEffect('bendType', 1, 'note-bend');
    });
    test('音符效果:滑入', () {
      expectNoteEffect('slideInType', 1, 'note-slide-in');
    });
    test('音符效果:滑出类型无效', () {
      expectNoteEffect('slideOutType', 1, 'note-slide-out');
    });
    test('音符效果:揉弦', () {
      expectNoteEffect('vibrato', 1, 'note-vibrato');
    });
    test('音符效果:击勾音', () {
      expectNoteEffect('isHammerPullOrigin', true, 'note-hammer-pull');
    });
    test('音符效果:连音线 slur', () {
      expectNoteEffect('isSlurDestination', true, 'note-slur');
    });
    test('音符效果:闷音', () {
      expectNoteEffect('isDead', true, 'note-dead');
    });
    test('音符效果:幽灵音', () {
      expectNoteEffect('isGhost', true, 'note-ghost');
    });
    test('音符效果:掌闷音', () {
      expectNoteEffect('isPalmMute', true, 'note-palm-mute');
    });
    test('音符效果:延音记号 letRing', () {
      expectNoteEffect('isLetRing', true, 'note-let-ring');
    });
    test('音符效果:断音', () {
      expectNoteEffect('isStaccato', true, 'note-staccato');
    });
    test('音符效果:左手点弦', () {
      expectNoteEffect('isLeftHandTapped', true, 'note-left-tap');
    });
    test('音符效果:重音', () {
      expectNoteEffect('accentuated', 1, 'note-accent');
    });
    test('音符效果:泛音类型无效', () {
      expectNoteEffect('harmonicType', 2, 'note-harmonic');
    });
  });

  group('变异电池·结构类(资料不够,当场中止)', () {
    test('源头不是映射', () {
      expectViolation('not-a-map',
          ruleId: 'data-format', verdict: ScoreHealthVerdict.insufficient);
    });
    test('缺 masterBars', () {
      expectViolation(mutated((s) => s.remove('masterBars')),
          ruleId: 'missing-bars',
          verdict: ScoreHealthVerdict.insufficient,
          messageContains: '缺少小节');
    });
    test('小节数量不一致', () {
      expectViolation(
          mutated((s) => (s['masterBars'] as List).removeLast()),
          ruleId: 'bar-count',
          verdict: ScoreHealthVerdict.insufficient,
          messageContains: '小节数量不一致');
    });
    test('谱表数据坏', () {
      expectViolation(mutated((s) => (s['tracks'] as List)[0]['staves'] = [5]),
          ruleId: 'data-format', verdict: ScoreHealthVerdict.insufficient);
    });
    test('调弦:非映射', () {
      expectViolation(
          mutated((s) =>
              ((s['tracks'] as List)[0]['staves'] as List)[0]['stringTuning'] =
                  'x'),
          ruleId: 'tuning',
          verdict: ScoreHealthVerdict.insufficient,
          messageContains: '调弦');
    });
    test('调弦:不是四弦谱', () {
      expectViolation(
          mutated((s) => ((s['tracks'] as List)[0]['staves'] as List)[0]
                    ['stringTuning']['tunings'] = [69, 64, 60, 67, 55, 48]),
          ruleId: 'tuning',
          verdict: ScoreHealthVerdict.insufficient,
          messageContains: '调弦');
    });
    test('调弦:变调夹负数', () {
      expectViolation(
          mutated((s) =>
              ((s['tracks'] as List)[0]['staves'] as List)[0]['capo'] = -1),
          ruleId: 'tuning',
          verdict: ScoreHealthVerdict.insufficient);
    });
    test('调弦:变调夹缺失', () {
      expectViolation(
          mutated((s) =>
              ((s['tracks'] as List)[0]['staves'] as List)[0].remove('capo')),
          ruleId: 'tuning',
          verdict: ScoreHealthVerdict.insufficient);
    });
    test('拍号数据缺失', () {
      expectViolation(
          mutated((s) => masterOf(s, 6).remove('timeSignatureNumerator')),
          ruleId: 'time-signature-missing',
          verdict: ScoreHealthVerdict.insufficient,
          measure: 6,
          messageContains: '拍号数据缺失');
    });
    test('速度:起始速度 0(调用方元数据坏)', () {
      final report = checkScoreHealth(source, pageTempoBpm: 0);
      expect(report.verdict, ScoreHealthVerdict.insufficient);
      expect(report.firstMessage, '起始速度无效');
      expect(
        () => buildReferenceScore(source, pageTempoBpm: 0),
        throwsA(isA<ScoreImportException>()
            .having((e) => e.message, 'message', '起始速度无效')),
      );
    });
    test('速度:页速 0.4 舍入为 0', () {
      final report = checkScoreHealth(source, pageTempoBpm: 0.4);
      expect(report.verdict, ScoreHealthVerdict.insufficient);
      expect(report.firstMessage, '速度变化数据无效');
      expect(
        () => buildReferenceScore(source, pageTempoBpm: 0.4),
        throwsA(isA<ScoreImportException>()
            .having((e) => e.message, 'message', report.firstMessage)),
      );
    });
    test('速度:变速值无效', () {
      expectViolation(
          mutated((s) => masterOf(s, 50)['tempoAutomation'] =
              {'isLinear': false, 'ratioPosition': 0, 'value': 0}),
          ruleId: 'tempo-invalid',
          verdict: ScoreHealthVerdict.insufficient,
          measure: 50,
          messageContains: '速度变化数据无效');
    });
    test('小节缺失:末小节 bars 少一条', () {
      expectViolation(
          mutated((s) =>
              ((s['tracks'] as List)[0]['staves'] as List)[0]['bars']
                  .removeLast()),
          ruleId: 'missing-bar',
          verdict: ScoreHealthVerdict.insufficient,
          measure: 51,
          messageContains: '小节数据缺失');
    });
    test('时值数据无效', () {
      expectViolation(mutated((s) => beatAny(s, 6)['duration'] = 'x'),
          ruleId: 'duration-invalid',
          verdict: ScoreHealthVerdict.insufficient,
          measure: 6,
          messageContains: '时值数据无效');
    });
    test('弦号越界', () {
      expectViolation(mutated((s) => noteOf(s, 6)['string'] = 5),
          ruleId: 'string-fret',
          verdict: ScoreHealthVerdict.insufficient,
          measure: 6,
          messageContains: '弦号或品位');
    });
    test('品位负数', () {
      expectViolation(mutated((s) => noteOf(s, 6)['fret'] = -1),
          ruleId: 'string-fret',
          verdict: ScoreHealthVerdict.insufficient,
          measure: 6);
    });
    test('一致性:谱面时值与播放时长不一致', () {
      expectViolation(
          mutated((s) =>
              beatWithNote(s, 6)['playbackDuration'] =
                  (beatWithNote(s, 6)['playbackDuration'] as num) + 960),
          ruleId: 'timing-mismatch',
          verdict: ScoreHealthVerdict.insufficient,
          measure: 6,
          messageContains: '播放时间不一致');
    });
    test('一致性:显示位置与播放位置不一致', () {
      expectViolation(
          mutated((s) =>
              beatWithNote(s, 6)['displayStart'] =
                  (beatWithNote(s, 6)['playbackStart'] as num) + 480),
          ruleId: 'timing-mismatch',
          verdict: ScoreHealthVerdict.insufficient,
          measure: 6);
    });
    test('一致性:音符时间超出小节', () {
      expectViolation(
          mutated((s) {
            final beat = beatWithNote(s, 6);
            beat['playbackStart'] = (beat['playbackStart'] as num) + 38400;
            beat['displayStart'] = beat['playbackStart'];
          }),
          ruleId: 'timing-overflow',
          verdict: ScoreHealthVerdict.insufficient,
          measure: 6,
          messageContains: '超出小节');
    });
    test('曲级标称速度字段坏(末段兜底)', () {
      expectViolation(mutated((s) => s.remove('tempo')),
          ruleId: 'data-format',
          verdict: ScoreHealthVerdict.insufficient,
          messageContains: '曲谱数据格式无效');
    });
  });

  group('多违例与清点行为', () {
    test('同一节拍两个能力违例都标出,按 walk 序', () {
      final report = checkScoreHealth(
        mutated((s) {
          final beat = beatAny(s, 6);
          beat['tupletNumerator'] = 3;
          beat['tupletDenominator'] = 2;
          beat['vibrato'] = 1;
        }),
        pageTempoBpm: 80,
      );
      expect(report.verdict, ScoreHealthVerdict.needsRules);
      final rules = report.violations.map((v) => v.ruleId).toList();
      expect(rules, containsAll(<String>['tuplet', 'beat-vibrato']));
      expect(rules.indexOf('tuplet'), lessThan(rules.indexOf('beat-vibrato')),
          reason: '连音检查在演奏效果之前(与原守门顺序一致)');
    });

    test('能力违例 + 结构违例:结构类主导三态', () {
      final report = checkScoreHealth(
        mutated((s) {
          masterOf(s, 6)['isRepeatStart'] = true;
          ((s['tracks'] as List)[0]['staves'] as List)[0]['bars'].removeLast();
        }),
        pageTempoBpm: 80,
      );
      expect(report.verdict, ScoreHealthVerdict.insufficient);
      final rules = report.violations.map((v) => v.ruleId).toList();
      expect(rules, containsAll(<String>['repeat-start', 'missing-bar']));
      expect(report.firstMessage, contains('反复'),
          reason: '守门抛首条(walk 序),即使三态由结构类主导');
    });

    test('能力违例不毁清点:拍号/规模/支持记号照常', () {
      final report = checkScoreHealth(
        mutated((s) {
          final beat = beatAny(s, 6);
          beat['tupletNumerator'] = 3;
          beat['tupletDenominator'] = 2;
        }),
        pageTempoBpm: 80,
      );
      expect(report.verdict, ScoreHealthVerdict.needsRules);
      expect(report.timeSignatures, {'4/4'});
      expect(report.measureCount, 51);
      expect(report.eventCount, 317);
      expect(report.noteCount, 557);
      expect(report.featureNotes.first, '扫弦/琶音 ×85');
    });

    test('结构中止后的清点只采信中止前:eventCount 置空', () {
      final report = checkScoreHealth(
        mutated((s) =>
            ((s['tracks'] as List)[0]['staves'] as List)[0]['bars']
                .removeLast()),
        pageTempoBpm: 80,
      );
      expect(report.verdict, ScoreHealthVerdict.insufficient);
      expect(report.eventCount, isNull);
      expect(report.measureCount, 51);
      expect(report.timeSignatures, {'4/4'}, reason: '中止前走过的小节清点保留');
    });
  });

  group('坏谱自检样例(assets/scores/selftest-broken.json)', () {
    test('四类违例逐条标出,判缺规则待补,不产谱', () {
      final bad =
          jsonDecode(File('assets/scores/selftest-broken.json').readAsStringSync());
      final report = checkScoreHealth(bad, pageTempoBpm: 80);
      expect(report.verdict, ScoreHealthVerdict.needsRules);
      expect(report.violations, hasLength(4));
      expect(report.violations.map((v) => v.ruleId).toList(), [
        'repeat-start',
        'fermata',
        'tuplet',
        'note-let-ring',
      ]);
      expect(
        report.violations.map((v) => v.measure).toList(),
        [5, 9, 13, 17],
      );
      expect(report.score, isNull);
      expect(report.featureNotes.first, '扫弦/琶音 ×85',
          reason: '能力违例不清空支持记号清点');
    });
  });
}
