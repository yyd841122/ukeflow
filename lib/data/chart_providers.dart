import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/chart/builtin_charts.dart';
import '../core/chart/builtin_image_charts.dart';
import '../core/chart/builtin_tab_charts.dart';
import '../core/chart/custom_charts.dart';
import '../core/model/strum_chart.dart';
import 'chord_library.dart';
import 'database.dart';
import 'providers.dart';

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
/// 图片谱(工单 18)= 内置资产 + 相册入库(尾随)。
typedef LibraryContent = ({
  List<BuiltInChart> builtinStrum,
  List<CustomStrumEntry> customStrum,
  List<BuiltInTabChart> tab,
  List<ImageChartEntry> imageCharts,
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

/// 曲库数据源(工单 15):四类曲目合流为一处 AsyncValue,曲库页
/// 统一呈现加载/错误/数据。自建谱与用户图片谱走流,导入后本 provider
/// 自动重建,新谱即出现在列表(「同一列表」验收的数据面)。
final libraryProvider = FutureProvider<LibraryContent>((ref) async {
  final builtinStrum = await ref.watch(builtinChartsProvider.future);
  final customStrum = await ref.watch(customStrumChartsProvider.future);
  final tab = await ref.watch(builtinTabChartsProvider.future);
  final customImages = await ref.watch(imageChartsProvider.future);
  final imageCharts = [
    for (final chart in builtinImageChartCatalog)
      BuiltinImageChartEntry(
        id: chart.id,
        title: chart.title,
        assetPath: chart.assetPath,
      ),
    ...customImages,
  ];
  return (
    builtinStrum: builtinStrum,
    customStrum: customStrum,
    tab: tab,
    imageCharts: imageCharts,
  );
});
