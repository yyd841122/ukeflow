import 'dart:convert';

import '../model/checkin.dart';

/// 备份文档编解码(工单 21,纯数据变换零 drift 依赖):数据库三表
/// (打卡/自建谱/设置)与单个 JSON 文档互转。
///
/// 格式契约(v2):顶层对象带 `version`(读取侧只认当前及更早,更新
/// 文件提示先升级),键名 `settings`/`checkins`/`custom_charts`/
/// `flowing_sessions`(v2 起;流水谱练琴记录,票65 WP-B),条目字段用
/// 数据库列名(`checked_on_day` 等)。未知键忽略(段内前向兼容)——
/// v1 备份里的 `image_charts` 段(已终止,ADR-0013)读取时静默丢弃;
/// v1 备份无 `flowing_sessions` 段 = 空段(导入即覆盖语义下,练琴记录
/// 按备份状态清空)。
///
/// 解析入口 [parseBackupJson]:任何非法形态抛 [BackupFormatException],
/// 消息为可读中文——导入坏文件给可读错误,不崩溃(工单 21 验收)。
final class BackupDoc {
  /// 当前写入的格式版本。读取侧只认 [formatVersion] 及更早;
  /// 更高的版本号 = 文件来自更新的 App,提示升级而非硬解析。
  static const int formatVersion = 2;

  /// 设置键值全量(键即数据库行,原样搬运,未来新设置免费随行)。
  final Map<String, String> settings;

  final List<BackupCheckIn> checkIns;
  final List<BackupCustomChart> customCharts;
  final List<BackupFlowingSession> flowingSessions;

  const BackupDoc({
    required this.settings,
    required this.checkIns,
    required this.customCharts,
    required this.flowingSessions,
  });

  @override
  bool operator ==(Object other) =>
      other is BackupDoc &&
      _mapsEqual(settings, other.settings) &&
      _listsEqual(checkIns, other.checkIns) &&
      _listsEqual(customCharts, other.customCharts) &&
      _listsEqual(flowingSessions, other.flowingSessions);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      settings.keys.map((key) => Object.hash(key, settings[key])),
    ),
    Object.hashAll(checkIns),
    Object.hashAll(customCharts),
    Object.hashAll(flowingSessions),
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
    'flowing_sessions': [
      for (final e in flowingSessions)
        {
          'id': e.id,
          'started_at_ms': e.startedAtMs,
          'duration_ms': e.durationMs,
          'end_position_seconds': e.endPositionSeconds,
          'speed': e.speed,
          'rating': e.rating,
        },
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

/// 流水谱练琴记录备份条目(对应 FlowingSessions 表行;票65 WP-B)。
final class BackupFlowingSession {
  final int id;
  final int startedAtMs;
  final int durationMs;
  final double endPositionSeconds;
  final double speed;
  final int? rating;

  const BackupFlowingSession({
    required this.id,
    required this.startedAtMs,
    required this.durationMs,
    required this.endPositionSeconds,
    required this.speed,
    required this.rating,
  });

  @override
  bool operator ==(Object other) =>
      other is BackupFlowingSession &&
      id == other.id &&
      startedAtMs == other.startedAtMs &&
      durationMs == other.durationMs &&
      endPositionSeconds == other.endPositionSeconds &&
      speed == other.speed &&
      rating == other.rating;

  @override
  int get hashCode =>
      Object.hash(id, startedAtMs, durationMs, endPositionSeconds, speed, rating);
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
  // flowing_sessions 段 v2 起携带;v1 备份无此键 = 空段(覆盖语义下
  // 练琴记录按备份状态清空,与 image_charts 丢弃同理)。
  final flowingSessionsRaw = root['flowing_sessions'];
  final flowingSessions = flowingSessionsRaw == null
      ? const <BackupFlowingSession>[]
      : _parseEach(
          flowingSessionsRaw as List<Object?>,
          '练琴记录',
          _parseFlowingSession,
        );
  final settings = _parseSettings(root['settings']);
  // 全空文档在这里拦下:真机导出的备份至少有设置行,四段全空只可能是
  // 挑错的文件——而导入即覆盖的语义下,放它过去等于一键清库(评审 2026-10-17)。
  if (settings.isEmpty &&
      checkIns.isEmpty &&
      customCharts.isEmpty &&
      flowingSessions.isEmpty) {
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
    flowingSessions,
    (e) => e.id,
    (n) => '练琴记录有重复的编号 $n',
  );

  return BackupDoc(
    settings: settings,
    checkIns: checkIns,
    customCharts: customCharts,
    flowingSessions: flowingSessions,
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

BackupFlowingSession _parseFlowingSession(Map<String, Object?> map, int index) {
  final where = '练琴记录第${index + 1}条';
  final ratingValue = map['rating'];
  if (ratingValue != null && ratingValue is! int) {
    throw BackupFormatException('$where的「rating」格式不对');
  }
  return BackupFlowingSession(
    id: _intField(map, 'id', where),
    startedAtMs: _intField(map, 'started_at_ms', where),
    durationMs: _intField(map, 'duration_ms', where),
    endPositionSeconds: _doubleField(map, 'end_position_seconds', where),
    speed: _doubleField(map, 'speed', where),
    rating: ratingValue as int?,
  );
}

double _doubleField(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is! num) {
    throw BackupFormatException('$where缺少「$key」或格式不对');
  }
  return value.toDouble();
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
