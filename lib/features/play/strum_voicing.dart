import '../../core/audio/audio_engine.dart';
import '../../core/audio/pluck_player.dart';
import '../../core/model/strum_pattern.dart';
import '../../data/chord_library.dart' show Chord;

/// 扫弦定声接线(工单 10 参考音=扫弦 与 工单 11 示范试听 共用,评审
/// 收敛去重):持一张和弦表+拨弦播放器,把「和弦名+扫弦方向」接到逐弦
/// 音源,并预注入全曲音源。下/上扫音色的选择在 PluckPlayer(方向定声
/// 单一来源),本类只接线——换音源(采样,ADR-0004)动 PluckPlayer/
/// 本类,调度引擎(StrumScheduler)只认音源不感知音色。
class StrumVoicer {
  StrumVoicer({required this.chords, required this.player});

  /// 和弦名 → 和弦(谱面和弦已过白名单;库缺位等降级路径查不到)。
  final Map<String, Chord> chords;
  final PluckPlayer player;

  /// 和弦名+方向 → 弦音表(4 弦→1 弦序,闷音弦 null 占时位,下/上扫
  /// 各取各的衰减变体)。查不到返回 null(该事件静默越过);音源未就绪
  /// 的弦位无声占位——预注入([preload])未完成/失败的降级路径,与和弦
  /// 示范音同一物理语义。过窗调度同步调用,免 await。
  List<EngineSound?>? voice(String chordName, StrumDirection direction) {
    final chord = chords[chordName];
    if (chord == null) return null;
    return [
      for (final freq in chord.primaryFingering.stringFrequencies)
        freq == null ? null : player.loadedStrumSound(freq, direction),
    ];
  }

  /// 预注入全曲扫弦音源(两个方向的衰减变体各一套,调度期免 await)。
  /// 错误原样上抛由调用方定呈现(跟练静默降级、试听可见报错)。
  Future<void> preload() {
    return player.preloadStrumSounds(<double>{
      for (final chord in chords.values)
        ...chord.primaryFingering.stringFrequencies.whereType<double>(),
    });
  }
}
