import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'settings_dao.dart';

/// A4 参考音可调范围 Hz(常见调音器域:巴洛克 415 到偏高 466;步进 1Hz)。
const int minReferenceA4 = 415;
const int maxReferenceA4 = 466;

/// 默认 BPM 可调范围(与节拍器/跟练页内钳制域一致)。
const int minDefaultBpm = 40;
const int maxDefaultBpm = 208;

/// 「默认 BPM」缺省值:与节奏型训练器/跟练慢练起步同源;
/// 节拍器原独立缺省 120 收拢归一(工单 20)。
const int settingsDefaultBpm = 80;

/// 设置状态(工单 20):内存当前值。启动为缺省,异步加载落库值后替换,
/// setter 即时换状态并写透 DAO。
class AppSettings {
  const AppSettings({required this.referenceA4, required this.defaultBpm});

  /// 缺省:A4=440(pitch_math 全库换算常量,测试双源锚定)、
  /// 默认 BPM=[settingsDefaultBpm]。
  const AppSettings.defaults()
    : referenceA4 = 440,
      defaultBpm = settingsDefaultBpm;

  /// A4 参考音 Hz(调音器消费,GLOSSARY「参考音」)。
  final int referenceA4;

  /// 默认 BPM(节拍器初始值/跟练无 tempo 谱的回退值)。
  final int defaultBpm;
}

final settingsProvider = NotifierProvider<AppSettingsController, AppSettings>(
  AppSettingsController.new,
);

/// A4 参考音 Hz(调音器目标/试音/音名标注消费)。消费方测试 override
/// 本 provider 即可隔离,不触真库。
final referenceA4Provider = Provider<double>(
  (ref) => ref.watch(settingsProvider).referenceA4.toDouble(),
);

/// 默认 BPM(节拍器初始值/跟练无 tempo 谱回退)。同上,测试 override 隔离。
final defaultBpmProvider = Provider<int>(
  (ref) => ref.watch(settingsProvider).defaultBpm,
);

/// 设置控制器(工单 20):一次异步加载 + 写透。
///
/// 加载竞态契约:setter 先 `await [ready]` 再动状态——初载未落地时的
/// 写透不得被迟到的加载结果覆盖(否则设置页秒改会被启动加载回滚)。
/// 加载失败保留缺省并记日志(与 databaseWarmupProvider 同口径:
/// 不阻塞壳,问题在 logcat 暴露)。
class AppSettingsController extends Notifier<AppSettings> {
  Future<void>? _loading;

  /// 初载完成(或失败降级)的 Future;setter 依赖它定序。
  Future<void> get ready => _loading ?? Future.value();

  @override
  AppSettings build() {
    _loading = _load();
    return const AppSettings.defaults();
  }

  Future<void> _load() async {
    try {
      final dao = ref.read(settingsDaoProvider);
      final a4 = await dao.getInt(SettingsKeys.referenceA4);
      final bpm = await dao.getInt(SettingsKeys.defaultBpm);
      if (!ref.mounted) return;
      state = AppSettings(
        referenceA4: a4 ?? state.referenceA4,
        defaultBpm: bpm ?? state.defaultBpm,
      );
    } catch (error, stackTrace) {
      debugPrint('UkeFlow: 设置加载失败,用缺省 $error\n$stackTrace');
    }
  }

  /// 设 A4 参考音(钳制 [minReferenceA4]..[maxReferenceA4]):状态即时换,
  /// 写透 DAO(滑动连发即多次写,单行 upsert 量级无害;重启仍在是票面验收)。
  Future<void> setReferenceA4(int hz) async {
    await ready;
    if (!ref.mounted) return; // 容器已释放:状态无可落盘(与 _load 同纪律)。
    state = AppSettings(
      referenceA4: hz.clamp(minReferenceA4, maxReferenceA4),
      defaultBpm: state.defaultBpm,
    );
    await _persist(SettingsKeys.referenceA4, state.referenceA4);
  }

  /// 设默认 BPM(钳制 [minDefaultBpm]..[maxDefaultBpm])。
  Future<void> setDefaultBpm(int bpm) async {
    await ready;
    if (!ref.mounted) return;
    state = AppSettings(
      referenceA4: state.referenceA4,
      defaultBpm: bpm.clamp(minDefaultBpm, maxDefaultBpm),
    );
    await _persist(SettingsKeys.defaultBpm, state.defaultBpm);
  }

  /// 重读落库值(工单 21:导入备份把设置行整表换掉,内存状态须跟着
  /// 重读)。与初载同一竞态契约:先 `await ready` 定序再读。
  Future<void> reload() async {
    await ready;
    await _load();
  }

  /// 写透失败不回滚状态(UI 已呈现新值);采集侧失败重试由再改一次覆盖。
  Future<void> _persist(String key, int value) async {
    try {
      await ref.read(settingsDaoProvider).setInt(key, value);
    } catch (error, stackTrace) {
      debugPrint('UkeFlow: 设置写库失败 $error\n$stackTrace');
    }
  }
}
