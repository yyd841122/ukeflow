import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/chart/builtin_charts.dart';
import '../core/chart/builtin_image_charts.dart';
import '../core/chart/builtin_tab_charts.dart';
import '../core/chart/custom_charts.dart';
import '../core/chart/score_sheet_defs.dart';
import '../core/import/imported_solo_charts.dart';
import '../core/model/tab_chart.dart';
import '../core/model/strum_chart.dart';
import 'chord_library.dart';
import 'database.dart';
import 'providers.dart';
import 'settings_dao.dart';

export '../core/chart/builtin_charts.dart'
    show BuiltInChart, builtinChartCatalog;
export '../core/chart/builtin_image_charts.dart'
    show BuiltinImageChart, builtinImageChartCatalog;
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
  List<ImageChartEntry> imageCharts,
  List<ImportedSoloEntry> importedSolos,
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

/// 曲库里的导入独奏谱条目(工单 43,GLOSSARY「识谱源」):
/// id = 数据库自增主键(卡片 key 与隐藏集用),title = 入库命名
/// (展示名以它为准,自建谱同一纪律)。
sealed class ImportedSoloEntry {
  const ImportedSoloEntry({required this.id, required this.title});

  final int id;
  final String title;
}

/// 读出管线(解码→解析→校验→物化)通过:与内置独奏谱同等跟练待遇
/// (spec 故事 61/62),弹练三源在此齐备。
class ReadyImportedSolo extends ImportedSoloEntry {
  const ReadyImportedSolo({
    required super.id,
    required super.title,
    required this.def,
    required this.accompaniment,
    required this.melody,
  });

  /// 组合定义(谱面视图/双轨混播的绑定源;id 照录识谱源)。
  final ScoreSheetDef def;

  /// TAB 伴奏层(主轴)。
  final TabChart accompaniment;

  /// 简谱旋律层(层内本地拍位,主轴定位在 [def].melodyAlignBeats)。
  final TabChart melody;
}

/// 读出管线任一环失败(源 JSON 坏损/schemaVersion 不符/校验阻塞):
/// 条目保留在列、标记「已损坏」不可跟练——源保留在库可重试(修源
/// 重导入/物化管线演进后重读),不静默消失也不牵连整库(spec 故事 65)。
/// 原始报错走 debugPrint(logcat 可见)。
class BrokenImportedSolo extends ImportedSoloEntry {
  const BrokenImportedSolo({
    required super.id,
    required super.title,
    required this.error,
  });

  final Object error;
}

/// 导入独奏谱流(工单 43):数据库行读出即过解码→解析→校验→物化管线,
/// 导入写入即推送。逐行降级——任一环失败的行变 [BrokenImportedSolo]
/// (可见、不可跟练),不让一份坏源把整库顶成错误页。弦库无关:
/// 和弦锚自带指形,无白名单漂移面(与自建弹唱谱的差异点)。
final importedSoloChartsProvider = StreamProvider<List<ImportedSoloEntry>>((
  ref,
) {
  return ref.watch(importedSoloChartsDaoProvider).watchAll().map(
    (rows) => [for (final row in rows) _parseImportedSoloEntry(row)],
  );
});

/// 单行读出管线:失败降级为损坏条目(缺陷可见,不静默缺曲目)。
ImportedSoloEntry _parseImportedSoloEntry(ImportedSoloChart row) {
  try {
    final m = materializeImportedSoloChart(
      sourceJson: row.sourceJson,
      title: row.title,
    );
    return ReadyImportedSolo(
      id: row.id,
      title: row.title,
      def: m.def,
      accompaniment: m.accompaniment,
      melody: m.melody,
    );
  } catch (error) {
    debugPrint('UkeFlow: 导入独奏谱「${row.title}」读出校验失败 $error');
    return BrokenImportedSolo(id: row.id, title: row.title, error: error);
  }
}

/// 图片谱条目(工单 18,GLOSSARY「图片谱」):只读——无解析、无
/// 降级,能解码就展示(入库前已验真,见 core/chart/image_ingest.dart)。
sealed class ImageChartEntry {
  const ImageChartEntry({required this.title});

  final String title;

  /// 查看器用图片源。
  ImageProvider get imageProvider;

  /// 曲库卡片 key。
  String get cardKey;
}

/// 内置图片谱:资产随 App 交付。
class BuiltinImageChartEntry extends ImageChartEntry {
  const BuiltinImageChartEntry({
    required super.title,
    required this.id,
    required this.assetPath,
  });

  final String id;
  final String assetPath;

  @override
  ImageProvider get imageProvider => AssetImage(assetPath);

  @override
  String get cardKey => 'builtin-image-$id';
}

/// 相册入库图片谱(GLOSSARY「用户图片谱」):字节整块落库(BLOB),
/// 备份天然携带。命名取 User,不碰「自建谱(Custom Chart)」——
/// GLOSSARY 把自建谱限定为文本谱。
class UserImageChartEntry extends ImageChartEntry {
  const UserImageChartEntry({
    required super.title,
    required this.id,
    required this.bytes,
  });

  final int id;
  final Uint8List bytes;

  @override
  ImageProvider get imageProvider => MemoryImage(bytes);

  @override
  String get cardKey => 'user-image-$id';
}

/// 相册图片谱流(工单 18):数据库行直映条目,选图入库即自动入列。
final imageChartsProvider = StreamProvider<List<UserImageChartEntry>>((ref) {
  return ref.watch(imageChartsDaoProvider).watchAll().map(
        (rows) => [
          for (final row in rows)
            UserImageChartEntry(
              id: row.id,
              title: row.title,
              bytes: row.image,
            ),
        ],
      );
});

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

/// 隐藏内置图片谱 id 集(工单 32)。
final hiddenBuiltinImagesProvider = StreamProvider<Set<String>>(
  (ref) => ref
      .watch(settingsDaoProvider)
      .watchString(SettingsKeys.hiddenBuiltinImages)
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

/// 隐藏导入独奏谱 id 集(工单 43):行 id 十进制串逗号并,流驱动——
/// 隐藏/恢复写库即推送,曲库页与设置页同源刷新。
final hiddenImportedSolosProvider = StreamProvider<Set<String>>(
  (ref) => ref
      .watch(settingsDaoProvider)
      .watchString(SettingsKeys.hiddenImportedSoloIds)
      .map(parseHiddenIds),
);

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
  Future<void> hideImage(String id) =>
      _change(SettingsKeys.hiddenBuiltinImages, id, true);

  /// 恢复(设置页管理区):从对应集合移除。
  Future<void> restoreStrum(String id) =>
      _change(SettingsKeys.hiddenBuiltinStrums, id, false);
  Future<void> restoreTab(String id) =>
      _change(SettingsKeys.hiddenBuiltinTabs, id, false);
  Future<void> restoreImage(String id) =>
      _change(SettingsKeys.hiddenBuiltinImages, id, false);
}

final builtinChartVisibilityProvider = Provider<BuiltinChartVisibility>(
  (ref) => BuiltinChartVisibility(ref.watch(settingsDaoProvider)),
);

/// 导入独奏谱隐藏/恢复的写入口(工单 43):与内置谱同型(设置集合
/// 模式,spec 实施决策),集合键为行 id 十进制串;恢复口同在设置页
/// 管理区。删除语义在 UI 层确认后走这里。
class ImportedSoloVisibility {
  ImportedSoloVisibility(this._dao);

  final SettingsDao _dao;

  Future<void> _change(int rowId, bool add) =>
      toggleHiddenId(_dao, SettingsKeys.hiddenImportedSoloIds, '$rowId', add);

  /// 隐藏导入独奏谱(按数据库行 id)。
  Future<void> hide(int rowId) => _change(rowId, true);

  /// 恢复(设置页管理区):从集合移除,下次读出照过物化管线。
  Future<void> restore(int rowId) => _change(rowId, false);
}

final importedSoloVisibilityProvider = Provider<ImportedSoloVisibility>(
  (ref) => ImportedSoloVisibility(ref.watch(settingsDaoProvider)),
);

/// 曲库数据源(工单 15):五路曲目合流为一处 AsyncValue,曲库页
/// 统一呈现加载/错误/数据。自建谱、用户图片谱与导入独奏谱走流,导入
/// 后本 provider 自动重建,新谱即出现在列表(「同一列表」验收的数据面)。
final libraryProvider = FutureProvider<LibraryContent>((ref) async {
  final builtinStrum = await ref.watch(builtinChartsProvider.future);
  final customStrum = await ref.watch(customStrumChartsProvider.future);
  final tab = await ref.watch(builtinTabChartsProvider.future);
  final customImages = await ref.watch(imageChartsProvider.future);
  final importedSolos = await ref.watch(importedSoloChartsProvider.future);
  if (!ref.mounted) {
    throw StateError('libraryProvider 在启动中被回收');
  }
  // 隐藏集过滤(工单 32/43):内置谱三类与导入独奏谱按 settings id 集
  // 出列,自建谱与用户图片谱走真删不经此(数据库行删了流即少一行)。
  final hiddenStrums = await ref.watch(hiddenBuiltinStrumsProvider.future);
  final hiddenTabs = await ref.watch(hiddenBuiltinTabsProvider.future);
  final hiddenImages = await ref.watch(hiddenBuiltinImagesProvider.future);
  final hiddenImported = await ref.watch(hiddenImportedSolosProvider.future);
  final imageCharts = [
    for (final chart in builtinImageChartCatalog)
      if (!hiddenImages.contains(chart.id))
        BuiltinImageChartEntry(
          id: chart.id,
          title: chart.title,
          assetPath: chart.assetPath,
        ),
    ...customImages,
  ];
  return (
    builtinStrum: [
      for (final chart in builtinStrum)
        if (!hiddenStrums.contains(chart.id)) chart,
    ],
    customStrum: customStrum,
    tab: [for (final t in tab) if (!hiddenTabs.contains(t.id)) t],
    imageCharts: imageCharts,
    importedSolos: [
      for (final entry in importedSolos)
        if (!hiddenImported.contains('${entry.id}')) entry,
    ],
  );
});
