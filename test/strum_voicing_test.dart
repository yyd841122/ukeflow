import 'package:flutter_test/flutter_test.dart';
import 'package:ukeflow/core/audio/fake_audio_engine.dart';
import 'package:ukeflow/core/audio/pluck_player.dart';
import 'package:ukeflow/core/model/chord.dart';
import 'package:ukeflow/core/model/strum_pattern.dart' show StrumDirection;
import 'package:ukeflow/features/play/strum_voicing.dart';

import 'helpers/chord_fixtures.dart';

/// 扫弦定声接线(工单 10 参考音 与 工单 11 示范试听 共用):方向定声
/// 的选择在 PluckPlayer,这里锁接线的形状——缺和弦降级、闷音占位、
/// 方向变体、预注入两套。
void main() {
  late FakeAudioEngine engine;
  late PluckPlayer player;
  late StrumVoicer voicer;

  /// 合成指法:4 弦闷音(全库无 -1 品位,闷音形状只能合成,工单 05 同款)。
  final muteChord = Chord(
    root: 'X',
    suffix: 'major',
    fingerings: const [
      ChordFingering(
        frets: [-1, 0, 1, 0],
        fingers: [0, 0, 1, 0],
        baseFret: 1,
        barres: [],
      ),
    ],
  );

  setUp(() {
    engine = FakeAudioEngine();
    player = PluckPlayer(engine: engine);
    voicer = StrumVoicer(
      chords: {for (final chord in uiFixtureLibrary.chords) chord.label: chord},
      player: player,
    );
  });

  test('voice:方向定声(下/上各取各的衰减变体),同和弦两套并存', () async {
    await voicer.preload();
    final amDown = voicer.voice('Am', StrumDirection.down)!;
    final amUp = voicer.voice('Am', StrumDirection.up)!;
    expect(amDown.every((s) => s!.key.endsWith('_1500')), isTrue);
    expect(amUp.every((s) => s!.key.endsWith('_700')), isTrue);
  });

  test('voice:缺和弦返回 null(静默降级);未预注入的弦位无声占位', () {
    expect(voicer.voice('F#m7', StrumDirection.down), isNull, reason: '库缺位降级');

    final before = voicer.voice('Am', StrumDirection.down)!;
    expect(before.every((s) => s == null), isTrue, reason: '未注入无半成品');
  });

  test('voice:闷音弦 null 占时位,弦表形状透传不改写', () async {
    final voicer2 = StrumVoicer(chords: {'X': muteChord}, player: player);
    await voicer2.preload(); // 闷音弦不计入注入音高集
    final strings = voicer2.voice('X', StrumDirection.down)!;
    expect(strings, hasLength(4));
    expect(strings.first, isNull, reason: '闷音 -1 → null 占位不发声');
    expect(strings.where((s) => s != null), hasLength(3));
    // 3 根有声弦 × 下/上两套衰减变体。
    expect(engine.loadedKeys, hasLength(6));
  });

  test('preload:两方向变体各一套;同音重调不重注入', () async {
    await voicer.preload();
    final keys = engine.loadedKeys.toSet();
    expect(keys.where((k) => k.endsWith('_1500')), isNotEmpty);
    expect(keys.where((k) => k.endsWith('_700')), isNotEmpty);

    final count = engine.loadedKeys.length;
    await voicer.preload();
    expect(engine.loadedKeys, hasLength(count), reason: '缓存兜底');
  });
}
