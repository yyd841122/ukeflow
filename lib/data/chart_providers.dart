import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/chart/builtin_charts.dart';
import '../core/chart/builtin_tab_charts.dart';
import '../core/chart/custom_charts.dart';
import '../core/model/strum_chart.dart';
import 'chord_library.dart';
import 'database.dart';
import 'providers.dart';
import 'settings_dao.dart';

export '../core/chart/builtin_charts.dart'
    show BuiltInChart, builtinChartCatalog;
export '../core/chart/builtin_tab_charts.dart'
    show BuiltInTabChart, builtinTabChartCatalog;

/// 曲库里的自建弹唱谱条目(工单 15):id = 数据库自增主键(卡片 key 用),
/// title = 入库命名(展示名以它为准)。
sealed class CustomStrumEntry {
  const CustomStrumEntry({required this.id, required this.title});

  final int id;
  final String title;
}

/// 解析通过:与内置谱同一待遇,点按直达跟练。
class ReadyCustomStrum extends CustomStrumEntry {
  const ReadyCustomStrum({
    required super.id,
    required super.title,
    required this.chart,
  });

  final StrumChart chart;
}

/// 读出校验未过(存储损坏/白名单漂移):条目保留在列、标记不可跟练——
/// 用户数据的坏谱不牵连整库可用性(内置谱照常可达),也不静默缺曲目;
/// 自救路径(重导入/删除)归工单 16。原始报错走 debugPrint(logcat 可见)。
class BrokenCustomStrum extends CustomStrumEntry {
  const BrokenCustomStrum({
    required super.id,
    required super.title,
    required this.error,
  });

  final Object error;
}

/// 曲库内容(工单 15):弹唱谱 = 内置 + 自建(尾随),指弹谱 = 内置,
/// 图片谱(工单 18)= 内置资产 + 相册入库(尾随),独奏谱(工单 43)=
/// 内置组合 + 导入源(尾随,见 importedSolos)。
typedef LibraryContent = ({
  List<BuiltInChart> builtinStrum,
  List<CustomStrumEntry> customStrum,
  List<BuiltInTabChart> tab,
});

/// 内置曲库（GLOSSARY「内置曲库」）：5 首目标曲，随 App 交付、开箱即练。
/// 白名单来自和弦库数据；任何内置谱坏损当场抛错（缺陷可见，不静默缺曲目）。
final builtinChartsProvider = FutureProvider<List<BuiltInChart>>((ref) async {
  final library = await ref.watch(chordLibraryProvider.future);
  return BuiltInCharts.load(
    readAsset: rootBundle.loadString,
    allowedChords: library.labels,
  );
});

/// 内置指弹曲（ADR-0003：v1 指弹仅限内置手工录入，Dart 常量直接入库）：
/// 加载期逐份校验，坏谱当场抛错。数据非异步，仍走 FutureProvider——
/// 曲库页对两类曲目用同一套 AsyncValue 错误呈现。
final builtinTabChartsProvider = FutureProvider<List<BuiltInTabChart>>((
  ref,
) async {
  return loadBuiltinTabCharts();
});

/// 自建弹唱谱流(GLOSSARY「自建谱」):数据库行读出即时解析,
/// 导入/录入写入即推送。逐行降级——读出校验失败的行变 [BrokenCustomStrum]
/// (可见、不可跟练),不让一条用户数据的坏谱把整库顶成错误页。
final customStrumChartsProvider = StreamProvider<List<CustomStrumEntry>>((
  ref,
) async* {
  final library = await ref.watch(chordLibraryProvider.future);
  // 初载竞速期容器被回收:不再订阅,否则弃用 Ref 上 watch 即抛
  // (工单 32 测试拆容器时暴露;与设置控制器的 mounted 纪律同源)。
  if (!ref.mounted) return;
  yield* ref.watch(customChartsDaoProvider).watchAll().map(
    (rows) => [
      for (final row in rows) _parseCustomEntry(row, library.labels),
    ],
  );
});

/// 单行读出解析:失败降级为损坏条目(缺陷可见——debugPrint 原始报错,
/// 曲库卡片标记「谱面读不出」,不静默缺曲目)。
CustomStrumEntry _parseCustomEntry(CustomChart row, Set<String> allowedChords) {
  try {
    return ReadyCustomStrum(
      id: row.id,
      title: row.title,
      chart: parseCustomChart(
        source: row.source,
        title: row.title,
        allowedChords: allowedChords,
      ),
    );
  } catch (error) {
    debugPrint('UkeFlow: 自建谱「${row.title}」读出校验失败 $error');
    return BrokenCustomStrum(id: row.id, title: row.title, error: error);
  }
}


/// 逗号并 id 集解析(工单 32 隐藏集的存放格式):空/缺行 = 空集。
Set<String> parseHiddenIds(String? raw) =>
    raw == null || raw.isEmpty ? <String>{} : raw.split(',').toSet();

/// 隐藏内置谱 id 集(工单 32,GLOSSARY「隐藏内置谱」):每类一个
/// settings 键,流驱动——隐藏/恢复写库即推送,曲库页与设置页同源刷新。
final hiddenBuiltinStrumsProvider = StreamProvider<Set<String>>(
  (ref) => ref
      .watch(settingsDaoProvider)
      .watchString(SettingsKeys.hiddenBuiltinStrums)
      .map(parseHiddenIds),
);

/// 隐藏内置指弹谱 id 集(工单 32)。
final hiddenBuiltinTabsProvider = StreamProvider<Set<String>>(
  (ref) => ref
      .watch(settingsDaoProvider)
      .watchString(SettingsKeys.hiddenBuiltinTabs)
      .map(parseHiddenIds),
);

/// 隐藏集读改写(工单 32/43 各隐藏集合共用):幂等——已在集内再藏
/// 不重写;集变化写回逗号并串,流订阅端自动跟进。
Future<void> toggleHiddenId(
  SettingsDao dao,
  String key,
  String id,
  bool add,
) async {
  final current = parseHiddenIds(await dao.getString(key));
  final next = {...current};
  add ? next.add(id) : next.remove(id);
  if (next.length == current.length && add) return; // 已在集内,免写。
  await dao.setString(key, next.join(','));
}

/// 内置谱隐藏/恢复的写入口(工单 32):读改写对应 settings 单行,
/// 流订阅端(曲库/设置页)自动跟进。删除语义在 UI 层确认后走这里。
class BuiltinChartVisibility {
  BuiltinChartVisibility(this._dao);

  final SettingsDao _dao;

  Future<void> _change(
    String key,
    String id,
    bool add,
  ) =>
      toggleHiddenId(_dao, key, id, add);

  /// 隐藏内置弹唱谱/指弹谱/图片谱(按曲库目录 id)。
  Future<void> hideStrum(String id) =>
      _change(SettingsKeys.hiddenBuiltinStrums, id, true);
  Future<void> hideTab(String id) =>
      _change(SettingsKeys.hiddenBuiltinTabs, id, true);

  /// 恢复(设置页管理区):从对应集合移除。
  Future<void> restoreStrum(String id) =>
      _change(SettingsKeys.hiddenBuiltinStrums, id, false);
  Future<void> restoreTab(String id) =>
      _change(SettingsKeys.hiddenBuiltinTabs, id, false);
}

final builtinChartVisibilityProvider = Provider<BuiltinChartVisibility>(
  (ref) => BuiltinChartVisibility(ref.watch(settingsDaoProvider)),
);

/// 曲库数据源(工单 15):三路曲目合流为一处 AsyncValue,曲库页
/// 统一呈现加载/错误/数据。自建谱走流,导入
/// 后本 provider 自动重建,新谱即出现在列表(「同一列表」验收的数据面)。
final libraryProvider = FutureProvider<LibraryContent>((ref) async {
  final builtinStrum = await ref.watch(builtinChartsProvider.future);
  final customStrum = await ref.watch(customStrumChartsProvider.future);
  final tab = await ref.watch(builtinTabChartsProvider.future);
  if (!ref.mounted) {
    throw StateError('libraryProvider 在启动中被回收');
  }
  // 隐藏集过滤(工单 32/43):内置谱两类与导入独奏谱按 settings id 集
  // 出列,自建谱走真删不经此(数据库行删了流即少一行)。
  final hiddenStrums = await ref.watch(hiddenBuiltinStrumsProvider.future);
  final hiddenTabs = await ref.watch(hiddenBuiltinTabsProvider.future);
  return (
    builtinStrum: [
      for (final chart in builtinStrum)
        if (!hiddenStrums.contains(chart.id)) chart,
    ],
    customStrum: customStrum,
    tab: [for (final t in tab) if (!hiddenTabs.contains(t.id)) t],
  );
});
