import 'dart:convert';
import 'dart:typed_data';

import '../model/checkin.dart';

/// 备份文档编解码(工单 21,纯数据变换零 drift 依赖):数据库四表
/// (打卡/自建谱/用户图片谱/设置)与单个 JSON 文档互转。
///
/// 格式契约(v1):顶层对象带 `version`(将来格式演进升版本留门,
/// 票面「导出文件带版本号」),四段键名 `settings`/`checkins`/
/// `custom_charts`/`image_charts`,条目字段用数据库列名
/// (`checked_on_day` 等);图片字节 base64。未知键忽略(段内前向兼容)。
///
/// 解析入口 [parseBackupJson]:任何非法形态抛 [BackupFormatException],
/// 消息为可读中文——导入坏文件给可读错误,不崩溃(工单 21 验收)。
final class BackupDoc {
  /// 当前写入的格式版本。读取侧只认 [formatVersion] 及更早;
  /// 更高的版本号 = 文件来自更新的 App,提示升级而非硬解析。
  static const int formatVersion = 1;

  /// 设置键值全量(键即数据库行,原样搬运,未来新设置免费随行)。
  final Map<String, String> settings;

  final List<BackupCheckIn> checkIns;
  final List<BackupCustomChart> customCharts;
  final List<BackupImageChart> imageCharts;

  const BackupDoc({
    required this.settings,
    required this.checkIns,
    required this.customCharts,
    required this.imageCharts,
  });

  @override
  bool operator ==(Object other) =>
      other is BackupDoc &&
      _mapsEqual(settings, other.settings) &&
      _listsEqual(checkIns, other.checkIns) &&
      _listsEqual(customCharts, other.customCharts) &&
      _listsEqual(imageCharts, other.imageCharts);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      settings.keys.map((key) => Object.hash(key, settings[key])),
    ),
    Object.hashAll(checkIns),
    Object.hashAll(customCharts),
    Object.hashAll(imageCharts),
  );

  Map<String, Object?> toJsonMap() => {
    'version': formatVersion,
    'settings': settings,
    'checkins': [
      for (final e in checkIns)
        {'day': e.day, 'kind': e.kind.index, 'checked_on_day': e.checkedOnDay},
    ],
    'custom_charts': [
      for (final e in customCharts)
        {'id': e.id, 'title': e.title, 'source': e.source},
    ],
    'image_charts': [
      for (final e in imageCharts)
        {'id': e.id, 'title': e.title, 'image': base64Encode(e.image)},
    ],
  };
}

/// 打卡备份条目(对应 CheckIns 表行)。
final class BackupCheckIn {
  final int day;
  final CheckInKind kind;
  final int checkedOnDay;

  const BackupCheckIn({
    required this.day,
    required this.kind,
    required this.checkedOnDay,
  });

  @override
  bool operator ==(Object other) =>
      other is BackupCheckIn &&
      day == other.day &&
      kind == other.kind &&
      checkedOnDay == other.checkedOnDay;

  @override
  int get hashCode => Object.hash(day, kind, checkedOnDay);
}

/// 自建谱备份条目(对应 CustomCharts 表行;id 保留=曲库入库序保留)。
final class BackupCustomChart {
  final int id;
  final String title;
  final String source;

  const BackupCustomChart({
    required this.id,
    required this.title,
    required this.source,
  });

  @override
  bool operator ==(Object other) =>
      other is BackupCustomChart &&
      id == other.id &&
      title == other.title &&
      source == other.source;

  @override
  int get hashCode => Object.hash(id, title, source);
}

/// 用户图片谱备份条目(对应 ImageCharts 表行,字节 base64 进文档)。
final class BackupImageChart {
  final int id;
  final String title;
  final Uint8List image;

  const BackupImageChart({
    required this.id,
    required this.title,
    required this.image,
  });

  @override
  bool operator ==(Object other) =>
      other is BackupImageChart &&
      id == other.id &&
      title == other.title &&
      _listsEqual<int>(image, other.image);

  @override
  int get hashCode => Object.hash(id, title, Object.hashAll(image));
}

bool _listsEqual<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// 备份文件非法:message 为可直接展示给用户的中文(定位到段/条目)。
class BackupFormatException implements Exception {
  final String message;

  BackupFormatException(this.message);

  @override
  String toString() => message;
}

/// 解析备份 JSON 串;非法形态抛 [BackupFormatException]。
BackupDoc parseBackupJson(String source) {
  final Object? root;
  try {
    root = jsonDecode(source);
  } on FormatException {
    throw BackupFormatException('文件内容不是有效的 JSON 文本');
  }
  if (root is! Map<String, Object?>) {
    throw BackupFormatException('文件内容不是 UkeFlow 备份格式(应为 JSON 对象)');
  }
  final version = root['version'];
  if (version is! int || version < 1) {
    throw BackupFormatException('格式版本号不对——这不是 UkeFlow 备份文件');
  }
  if (version > BackupDoc.formatVersion) {
    throw BackupFormatException(
      '备份文件版本较新(v$version)——请先把 App 升级到对应版本再导入',
    );
  }

  final checkIns = _parseEach(
    _listOrComplain(root['checkins'], '打卡记录'),
    '打卡记录',
    _parseCheckIn,
  );
  final customCharts = _parseEach(
    _listOrComplain(root['custom_charts'], '自建谱'),
    '自建谱',
    _parseCustomChart,
  );
  final imageCharts = _parseEach(
    _listOrComplain(root['image_charts'], '图片谱'),
    '图片谱',
    _parseImageChart,
  );
  final settings = _parseSettings(root['settings']);
  // 全空文档在这里拦下:真机导出的备份至少有设置行,四段全空只可能是
  // 挑错的文件——而导入即覆盖的语义下,放它过去等于一键清库(评审 2026-10-17)。
  if (settings.isEmpty &&
      checkIns.isEmpty &&
      customCharts.isEmpty &&
      imageCharts.isEmpty) {
    throw BackupFormatException('备份文件里没有数据——请选择 UkeFlow 导出的备份文件');
  }
  // 主键重复在这里拦下(而不是留给还原时撞库):day/编号是各表主键,
  // 重复条目意味着文件被手工改坏,导入必撞库。
  _rejectDuplicate(checkIns, (e) => e.day, (n) => '打卡记录有重复的天数 $n');
  _rejectDuplicate(
    customCharts,
    (e) => e.id,
    (n) => '自建谱有重复的编号 $n',
  );
  _rejectDuplicate(
    imageCharts,
    (e) => e.id,
    (n) => '图片谱有重复的编号 $n',
  );

  return BackupDoc(
    settings: settings,
    checkIns: checkIns,
    customCharts: customCharts,
    imageCharts: imageCharts,
  );
}

void _rejectDuplicate<T, K>(
  List<T> entries,
  K Function(T entry) keyOf,
  String Function(K key) message,
) {
  final seen = <K>{};
  for (final entry in entries) {
    final key = keyOf(entry);
    if (!seen.add(key)) {
      throw BackupFormatException(message(key));
    }
  }
}

Map<String, String> _parseSettings(Object? value) {
  if (value == null) return {};
  if (value is! Map<String, Object?>) {
    throw BackupFormatException('设置段的格式不对');
  }
  for (final entry in value.entries) {
    if (entry.value is! String) {
      throw BackupFormatException('设置段「${entry.key}」的值格式不对');
    }
  }
  return value.cast<String, String>();
}

List<Object?> _listOrComplain(Object? value, String label) {
  if (value == null) return const [];
  if (value is! List<Object?>) {
    throw BackupFormatException('$label段的格式不对');
  }
  return value;
}

List<T> _parseEach<T>(
  List<Object?> raw,
  String label,
  T Function(Map<String, Object?>, int index) parseEntry,
) {
  return [
    for (var i = 0; i < raw.length; i++)
      if (raw[i] is! Map<String, Object?>)
        throw BackupFormatException('$label第${i + 1}条的格式不对')
      else
        parseEntry(raw[i] as Map<String, Object?>, i),
  ];
}

BackupCheckIn _parseCheckIn(Map<String, Object?> map, int index) {
  final where = '打卡记录第${index + 1}条';
  final day = _intField(map, 'day', where);
  final kindIndex = _intField(map, 'kind', where);
  if (kindIndex < 0 || kindIndex >= CheckInKind.values.length) {
    throw BackupFormatException('$where的打卡种类不对');
  }
  return BackupCheckIn(
    day: day,
    kind: CheckInKind.values[kindIndex],
    checkedOnDay: _intField(map, 'checked_on_day', where),
  );
}

BackupCustomChart _parseCustomChart(Map<String, Object?> map, int index) {
  final where = '自建谱第${index + 1}条';
  return BackupCustomChart(
    id: _intField(map, 'id', where),
    title: _stringField(map, 'title', where),
    source: _stringField(map, 'source', where),
  );
}

BackupImageChart _parseImageChart(Map<String, Object?> map, int index) {
  final where = '图片谱第${index + 1}条';
  final encoded = _stringField(map, 'image', where);
  final Uint8List bytes;
  try {
    bytes = base64Decode(encoded);
  } on FormatException {
    throw BackupFormatException('$where的图片数据无法解码');
  }
  return BackupImageChart(
    id: _intField(map, 'id', where),
    title: _stringField(map, 'title', where),
    image: bytes,
  );
}

int _intField(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is! int) {
    throw BackupFormatException('$where缺少「$key」或格式不对');
  }
  return value;
}

String _stringField(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is! String) {
    throw BackupFormatException('$where缺少「$key」或格式不对');
  }
  return value;
}
