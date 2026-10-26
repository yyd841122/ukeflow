// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CheckInsTable extends CheckIns with TableInfo<$CheckInsTable, CheckIn> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CheckInsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<int> day = GeneratedColumn<int>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<CheckInKind, int> kind =
      GeneratedColumn<int>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<CheckInKind>($CheckInsTable.$converterkind);
  static const VerificationMeta _checkedOnDayMeta = const VerificationMeta(
    'checkedOnDay',
  );
  @override
  late final GeneratedColumn<int> checkedOnDay = GeneratedColumn<int>(
    'checked_on_day',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [day, kind, checkedOnDay];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'check_ins';
  @override
  VerificationContext validateIntegrity(
    Insertable<CheckIn> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    }
    if (data.containsKey('checked_on_day')) {
      context.handle(
        _checkedOnDayMeta,
        checkedOnDay.isAcceptableOrUnknown(
          data['checked_on_day']!,
          _checkedOnDayMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_checkedOnDayMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {day};
  @override
  CheckIn map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CheckIn(
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day'],
      )!,
      kind: $CheckInsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}kind'],
        )!,
      ),
      checkedOnDay: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}checked_on_day'],
      )!,
    );
  }

  @override
  $CheckInsTable createAlias(String alias) {
    return $CheckInsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<CheckInKind, int, int> $converterkind =
      const EnumIndexConverter<CheckInKind>(CheckInKind.values);
}

class CheckIn extends DataClass implements Insertable<CheckIn> {
  /// 每日任务天数(1..30)。
  final int day;

  /// 完成/补卡(种类判定是域规则,见 core/model/checkin.dart)。
  final CheckInKind kind;

  /// 打卡发生的本地日历日(epoch 天数):连续天数按它算;
  /// 补卡时它就是「补练日期」(spec 故事 36)。
  final int checkedOnDay;
  const CheckIn({
    required this.day,
    required this.kind,
    required this.checkedOnDay,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day'] = Variable<int>(day);
    {
      map['kind'] = Variable<int>($CheckInsTable.$converterkind.toSql(kind));
    }
    map['checked_on_day'] = Variable<int>(checkedOnDay);
    return map;
  }

  CheckInsCompanion toCompanion(bool nullToAbsent) {
    return CheckInsCompanion(
      day: Value(day),
      kind: Value(kind),
      checkedOnDay: Value(checkedOnDay),
    );
  }

  factory CheckIn.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CheckIn(
      day: serializer.fromJson<int>(json['day']),
      kind: $CheckInsTable.$converterkind.fromJson(
        serializer.fromJson<int>(json['kind']),
      ),
      checkedOnDay: serializer.fromJson<int>(json['checkedOnDay']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'day': serializer.toJson<int>(day),
      'kind': serializer.toJson<int>(
        $CheckInsTable.$converterkind.toJson(kind),
      ),
      'checkedOnDay': serializer.toJson<int>(checkedOnDay),
    };
  }

  CheckIn copyWith({int? day, CheckInKind? kind, int? checkedOnDay}) => CheckIn(
    day: day ?? this.day,
    kind: kind ?? this.kind,
    checkedOnDay: checkedOnDay ?? this.checkedOnDay,
  );
  CheckIn copyWithCompanion(CheckInsCompanion data) {
    return CheckIn(
      day: data.day.present ? data.day.value : this.day,
      kind: data.kind.present ? data.kind.value : this.kind,
      checkedOnDay: data.checkedOnDay.present
          ? data.checkedOnDay.value
          : this.checkedOnDay,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CheckIn(')
          ..write('day: $day, ')
          ..write('kind: $kind, ')
          ..write('checkedOnDay: $checkedOnDay')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(day, kind, checkedOnDay);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CheckIn &&
          other.day == this.day &&
          other.kind == this.kind &&
          other.checkedOnDay == this.checkedOnDay);
}

class CheckInsCompanion extends UpdateCompanion<CheckIn> {
  final Value<int> day;
  final Value<CheckInKind> kind;
  final Value<int> checkedOnDay;
  const CheckInsCompanion({
    this.day = const Value.absent(),
    this.kind = const Value.absent(),
    this.checkedOnDay = const Value.absent(),
  });
  CheckInsCompanion.insert({
    this.day = const Value.absent(),
    required CheckInKind kind,
    required int checkedOnDay,
  }) : kind = Value(kind),
       checkedOnDay = Value(checkedOnDay);
  static Insertable<CheckIn> custom({
    Expression<int>? day,
    Expression<int>? kind,
    Expression<int>? checkedOnDay,
  }) {
    return RawValuesInsertable({
      if (day != null) 'day': day,
      if (kind != null) 'kind': kind,
      if (checkedOnDay != null) 'checked_on_day': checkedOnDay,
    });
  }

  CheckInsCompanion copyWith({
    Value<int>? day,
    Value<CheckInKind>? kind,
    Value<int>? checkedOnDay,
  }) {
    return CheckInsCompanion(
      day: day ?? this.day,
      kind: kind ?? this.kind,
      checkedOnDay: checkedOnDay ?? this.checkedOnDay,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (day.present) {
      map['day'] = Variable<int>(day.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(
        $CheckInsTable.$converterkind.toSql(kind.value),
      );
    }
    if (checkedOnDay.present) {
      map['checked_on_day'] = Variable<int>(checkedOnDay.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CheckInsCompanion(')
          ..write('day: $day, ')
          ..write('kind: $kind, ')
          ..write('checkedOnDay: $checkedOnDay')
          ..write(')'))
        .toString();
  }
}

class $CustomChartsTable extends CustomCharts
    with TableInfo<$CustomChartsTable, CustomChart> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomChartsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, title, source];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'custom_charts';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomChart> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomChart map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomChart(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
    );
  }

  @override
  $CustomChartsTable createAlias(String alias) {
    return $CustomChartsTable(attachedDatabase, alias);
  }
}

class CustomChart extends DataClass implements Insertable<CustomChart> {
  /// 自增主键:入库序即曲库展示序,亦是曲目稳定标识。
  final int id;

  /// 入库时的命名(工单 16 命名入库)——展示名以它为准,
  /// 可与源文本内嵌的 {title} 不同。
  final String title;

  /// ChordPro 源文本全文。
  final String source;
  const CustomChart({
    required this.id,
    required this.title,
    required this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['source'] = Variable<String>(source);
    return map;
  }

  CustomChartsCompanion toCompanion(bool nullToAbsent) {
    return CustomChartsCompanion(
      id: Value(id),
      title: Value(title),
      source: Value(source),
    );
  }

  factory CustomChart.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomChart(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'source': serializer.toJson<String>(source),
    };
  }

  CustomChart copyWith({int? id, String? title, String? source}) => CustomChart(
    id: id ?? this.id,
    title: title ?? this.title,
    source: source ?? this.source,
  );
  CustomChart copyWithCompanion(CustomChartsCompanion data) {
    return CustomChart(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomChart(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, source);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomChart &&
          other.id == this.id &&
          other.title == this.title &&
          other.source == this.source);
}

class CustomChartsCompanion extends UpdateCompanion<CustomChart> {
  final Value<int> id;
  final Value<String> title;
  final Value<String> source;
  const CustomChartsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.source = const Value.absent(),
  });
  CustomChartsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required String source,
  }) : title = Value(title),
       source = Value(source);
  static Insertable<CustomChart> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? source,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (source != null) 'source': source,
    });
  }

  CustomChartsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String>? source,
  }) {
    return CustomChartsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      source: source ?? this.source,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomChartsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }
}

class $ImageChartsTable extends ImageCharts
    with TableInfo<$ImageChartsTable, ImageChart> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImageChartsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageMeta = const VerificationMeta('image');
  @override
  late final GeneratedColumn<Uint8List> image = GeneratedColumn<Uint8List>(
    'image',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, title, image];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'image_charts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImageChart> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('image')) {
      context.handle(
        _imageMeta,
        image.isAcceptableOrUnknown(data['image']!, _imageMeta),
      );
    } else if (isInserting) {
      context.missing(_imageMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImageChart map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImageChart(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      image: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}image'],
      )!,
    );
  }

  @override
  $ImageChartsTable createAlias(String alias) {
    return $ImageChartsTable(attachedDatabase, alias);
  }
}

class ImageChart extends DataClass implements Insertable<ImageChart> {
  /// 自增主键:入库序即曲库展示序。
  final int id;

  /// 入库时的命名。
  final String title;

  /// 图片文件全字节(PNG/JPEG 由解码器自动识别)。
  final Uint8List image;
  const ImageChart({
    required this.id,
    required this.title,
    required this.image,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['image'] = Variable<Uint8List>(image);
    return map;
  }

  ImageChartsCompanion toCompanion(bool nullToAbsent) {
    return ImageChartsCompanion(
      id: Value(id),
      title: Value(title),
      image: Value(image),
    );
  }

  factory ImageChart.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImageChart(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      image: serializer.fromJson<Uint8List>(json['image']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'image': serializer.toJson<Uint8List>(image),
    };
  }

  ImageChart copyWith({int? id, String? title, Uint8List? image}) => ImageChart(
    id: id ?? this.id,
    title: title ?? this.title,
    image: image ?? this.image,
  );
  ImageChart copyWithCompanion(ImageChartsCompanion data) {
    return ImageChart(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      image: data.image.present ? data.image.value : this.image,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImageChart(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('image: $image')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, $driftBlobEquality.hash(image));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImageChart &&
          other.id == this.id &&
          other.title == this.title &&
          $driftBlobEquality.equals(other.image, this.image));
}

class ImageChartsCompanion extends UpdateCompanion<ImageChart> {
  final Value<int> id;
  final Value<String> title;
  final Value<Uint8List> image;
  const ImageChartsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.image = const Value.absent(),
  });
  ImageChartsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required Uint8List image,
  }) : title = Value(title),
       image = Value(image);
  static Insertable<ImageChart> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<Uint8List>? image,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (image != null) 'image': image,
    });
  }

  ImageChartsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<Uint8List>? image,
  }) {
    return ImageChartsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      image: image ?? this.image,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (image.present) {
      map['image'] = Variable<Uint8List>(image.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImageChartsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('image: $image')
          ..write(')'))
        .toString();
  }
}

class $ImportedSoloChartsTable extends ImportedSoloCharts
    with TableInfo<$ImportedSoloChartsTable, ImportedSoloChart> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportedSoloChartsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceJsonMeta = const VerificationMeta(
    'sourceJson',
  );
  @override
  late final GeneratedColumn<String> sourceJson = GeneratedColumn<String>(
    'source_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentShaMeta = const VerificationMeta(
    'contentSha',
  );
  @override
  late final GeneratedColumn<String> contentSha = GeneratedColumn<String>(
    'content_sha',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reviewedAtMeta = const VerificationMeta(
    'reviewedAt',
  );
  @override
  late final GeneratedColumn<String> reviewedAt = GeneratedColumn<String>(
    'reviewed_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    schemaVersion,
    sourceJson,
    contentSha,
    createdAt,
    updatedAt,
    reviewedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'imported_solo_charts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ImportedSoloChart> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_schemaVersionMeta);
    }
    if (data.containsKey('source_json')) {
      context.handle(
        _sourceJsonMeta,
        sourceJson.isAcceptableOrUnknown(data['source_json']!, _sourceJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceJsonMeta);
    }
    if (data.containsKey('content_sha')) {
      context.handle(
        _contentShaMeta,
        contentSha.isAcceptableOrUnknown(data['content_sha']!, _contentShaMeta),
      );
    } else if (isInserting) {
      context.missing(_contentShaMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('reviewed_at')) {
      context.handle(
        _reviewedAtMeta,
        reviewedAt.isAcceptableOrUnknown(data['reviewed_at']!, _reviewedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImportedSoloChart map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImportedSoloChart(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      sourceJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_json'],
      )!,
      contentSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_sha'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      reviewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reviewed_at'],
      ),
    );
  }

  @override
  $ImportedSoloChartsTable createAlias(String alias) {
    return $ImportedSoloChartsTable(attachedDatabase, alias);
  }
}

class ImportedSoloChart extends DataClass
    implements Insertable<ImportedSoloChart> {
  /// 自增主键:入库序即曲库展示序,亦是曲目稳定标识(隐藏集以此为准)。
  final int id;

  /// 入库时的命名——展示名以它为准(自建谱同一纪律,可覆盖源内曲名)。
  final String title;

  /// 源的识谱源格式版本(ScoreIr.schemaVersion 照录):格式演进时
  /// 按它识别陈年源,迁移/重导出的判定面。
  final int schemaVersion;

  /// 识谱源 JSON 全文。
  final String sourceJson;

  /// 源内容指纹(sha256,入库时现算):重导入去重/改源漂移检测的
  /// 判定面(导入 UI 工单 44、轻改工单 45 消费)。
  final String contentSha;

  /// 入库时刻。
  final DateTime createdAt;

  /// 最近一次源更新时刻(入库 = 创建;轻改随写随 bump,工单 45)。
  final DateTime updatedAt;

  /// 校对台全曲人工确认时刻(源 review.reviewedAt 照录,ISO 串原样
  /// 存放不转格式);null = 源未带复核状态。
  final String? reviewedAt;
  const ImportedSoloChart({
    required this.id,
    required this.title,
    required this.schemaVersion,
    required this.sourceJson,
    required this.contentSha,
    required this.createdAt,
    required this.updatedAt,
    this.reviewedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['source_json'] = Variable<String>(sourceJson);
    map['content_sha'] = Variable<String>(contentSha);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || reviewedAt != null) {
      map['reviewed_at'] = Variable<String>(reviewedAt);
    }
    return map;
  }

  ImportedSoloChartsCompanion toCompanion(bool nullToAbsent) {
    return ImportedSoloChartsCompanion(
      id: Value(id),
      title: Value(title),
      schemaVersion: Value(schemaVersion),
      sourceJson: Value(sourceJson),
      contentSha: Value(contentSha),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      reviewedAt: reviewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reviewedAt),
    );
  }

  factory ImportedSoloChart.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImportedSoloChart(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      sourceJson: serializer.fromJson<String>(json['sourceJson']),
      contentSha: serializer.fromJson<String>(json['contentSha']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      reviewedAt: serializer.fromJson<String?>(json['reviewedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'sourceJson': serializer.toJson<String>(sourceJson),
      'contentSha': serializer.toJson<String>(contentSha),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'reviewedAt': serializer.toJson<String?>(reviewedAt),
    };
  }

  ImportedSoloChart copyWith({
    int? id,
    String? title,
    int? schemaVersion,
    String? sourceJson,
    String? contentSha,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> reviewedAt = const Value.absent(),
  }) => ImportedSoloChart(
    id: id ?? this.id,
    title: title ?? this.title,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    sourceJson: sourceJson ?? this.sourceJson,
    contentSha: contentSha ?? this.contentSha,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    reviewedAt: reviewedAt.present ? reviewedAt.value : this.reviewedAt,
  );
  ImportedSoloChart copyWithCompanion(ImportedSoloChartsCompanion data) {
    return ImportedSoloChart(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      sourceJson: data.sourceJson.present
          ? data.sourceJson.value
          : this.sourceJson,
      contentSha: data.contentSha.present
          ? data.contentSha.value
          : this.contentSha,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      reviewedAt: data.reviewedAt.present
          ? data.reviewedAt.value
          : this.reviewedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImportedSoloChart(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('sourceJson: $sourceJson, ')
          ..write('contentSha: $contentSha, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('reviewedAt: $reviewedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    schemaVersion,
    sourceJson,
    contentSha,
    createdAt,
    updatedAt,
    reviewedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImportedSoloChart &&
          other.id == this.id &&
          other.title == this.title &&
          other.schemaVersion == this.schemaVersion &&
          other.sourceJson == this.sourceJson &&
          other.contentSha == this.contentSha &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.reviewedAt == this.reviewedAt);
}

class ImportedSoloChartsCompanion extends UpdateCompanion<ImportedSoloChart> {
  final Value<int> id;
  final Value<String> title;
  final Value<int> schemaVersion;
  final Value<String> sourceJson;
  final Value<String> contentSha;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> reviewedAt;
  const ImportedSoloChartsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.sourceJson = const Value.absent(),
    this.contentSha = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.reviewedAt = const Value.absent(),
  });
  ImportedSoloChartsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    required int schemaVersion,
    required String sourceJson,
    required String contentSha,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.reviewedAt = const Value.absent(),
  }) : title = Value(title),
       schemaVersion = Value(schemaVersion),
       sourceJson = Value(sourceJson),
       contentSha = Value(contentSha),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ImportedSoloChart> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<int>? schemaVersion,
    Expression<String>? sourceJson,
    Expression<String>? contentSha,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? reviewedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (sourceJson != null) 'source_json': sourceJson,
      if (contentSha != null) 'content_sha': contentSha,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (reviewedAt != null) 'reviewed_at': reviewedAt,
    });
  }

  ImportedSoloChartsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<int>? schemaVersion,
    Value<String>? sourceJson,
    Value<String>? contentSha,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? reviewedAt,
  }) {
    return ImportedSoloChartsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      sourceJson: sourceJson ?? this.sourceJson,
      contentSha: contentSha ?? this.contentSha,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (sourceJson.present) {
      map['source_json'] = Variable<String>(sourceJson.value);
    }
    if (contentSha.present) {
      map['content_sha'] = Variable<String>(contentSha.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (reviewedAt.present) {
      map['reviewed_at'] = Variable<String>(reviewedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportedSoloChartsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('sourceJson: $sourceJson, ')
          ..write('contentSha: $contentSha, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('reviewedAt: $reviewedAt')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  /// 设置键([SettingsKeys])。
  final String key;

  /// 设置值(整数以十进制串存放;读出侧按需解析,解析失败返回 null)。
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CheckInsTable checkIns = $CheckInsTable(this);
  late final $CustomChartsTable customCharts = $CustomChartsTable(this);
  late final $ImageChartsTable imageCharts = $ImageChartsTable(this);
  late final $ImportedSoloChartsTable importedSoloCharts =
      $ImportedSoloChartsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final CheckInsDao checkInsDao = CheckInsDao(this as AppDatabase);
  late final CustomChartsDao customChartsDao = CustomChartsDao(
    this as AppDatabase,
  );
  late final ImageChartsDao imageChartsDao = ImageChartsDao(
    this as AppDatabase,
  );
  late final ImportedSoloChartsDao importedSoloChartsDao =
      ImportedSoloChartsDao(this as AppDatabase);
  late final SettingsDao settingsDao = SettingsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    checkIns,
    customCharts,
    imageCharts,
    importedSoloCharts,
    settings,
  ];
}

typedef $$CheckInsTableCreateCompanionBuilder =
    CheckInsCompanion Function({
      Value<int> day,
      required CheckInKind kind,
      required int checkedOnDay,
    });
typedef $$CheckInsTableUpdateCompanionBuilder =
    CheckInsCompanion Function({
      Value<int> day,
      Value<CheckInKind> kind,
      Value<int> checkedOnDay,
    });

class $$CheckInsTableFilterComposer
    extends Composer<_$AppDatabase, $CheckInsTable> {
  $$CheckInsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<CheckInKind, CheckInKind, int> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get checkedOnDay => $composableBuilder(
    column: $table.checkedOnDay,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CheckInsTableOrderingComposer
    extends Composer<_$AppDatabase, $CheckInsTable> {
  $$CheckInsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get checkedOnDay => $composableBuilder(
    column: $table.checkedOnDay,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CheckInsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CheckInsTable> {
  $$CheckInsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumnWithTypeConverter<CheckInKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get checkedOnDay => $composableBuilder(
    column: $table.checkedOnDay,
    builder: (column) => column,
  );
}

class $$CheckInsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CheckInsTable,
          CheckIn,
          $$CheckInsTableFilterComposer,
          $$CheckInsTableOrderingComposer,
          $$CheckInsTableAnnotationComposer,
          $$CheckInsTableCreateCompanionBuilder,
          $$CheckInsTableUpdateCompanionBuilder,
          (CheckIn, BaseReferences<_$AppDatabase, $CheckInsTable, CheckIn>),
          CheckIn,
          PrefetchHooks Function()
        > {
  $$CheckInsTableTableManager(_$AppDatabase db, $CheckInsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CheckInsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CheckInsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CheckInsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> day = const Value.absent(),
                Value<CheckInKind> kind = const Value.absent(),
                Value<int> checkedOnDay = const Value.absent(),
              }) => CheckInsCompanion(
                day: day,
                kind: kind,
                checkedOnDay: checkedOnDay,
              ),
          createCompanionCallback:
              ({
                Value<int> day = const Value.absent(),
                required CheckInKind kind,
                required int checkedOnDay,
              }) => CheckInsCompanion.insert(
                day: day,
                kind: kind,
                checkedOnDay: checkedOnDay,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CheckInsTable, CheckIn>(table),
                  BaseReferences<_$AppDatabase, $CheckInsTable, CheckIn>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CheckInsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CheckInsTable,
      CheckIn,
      $$CheckInsTableFilterComposer,
      $$CheckInsTableOrderingComposer,
      $$CheckInsTableAnnotationComposer,
      $$CheckInsTableCreateCompanionBuilder,
      $$CheckInsTableUpdateCompanionBuilder,
      (CheckIn, BaseReferences<_$AppDatabase, $CheckInsTable, CheckIn>),
      CheckIn,
      PrefetchHooks Function()
    >;
typedef $$CustomChartsTableCreateCompanionBuilder =
    CustomChartsCompanion Function({
      Value<int> id,
      required String title,
      required String source,
    });
typedef $$CustomChartsTableUpdateCompanionBuilder =
    CustomChartsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String> source,
    });

class $$CustomChartsTableFilterComposer
    extends Composer<_$AppDatabase, $CustomChartsTable> {
  $$CustomChartsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CustomChartsTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomChartsTable> {
  $$CustomChartsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CustomChartsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomChartsTable> {
  $$CustomChartsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$CustomChartsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CustomChartsTable,
          CustomChart,
          $$CustomChartsTableFilterComposer,
          $$CustomChartsTableOrderingComposer,
          $$CustomChartsTableAnnotationComposer,
          $$CustomChartsTableCreateCompanionBuilder,
          $$CustomChartsTableUpdateCompanionBuilder,
          (
            CustomChart,
            BaseReferences<_$AppDatabase, $CustomChartsTable, CustomChart>,
          ),
          CustomChart,
          PrefetchHooks Function()
        > {
  $$CustomChartsTableTableManager(_$AppDatabase db, $CustomChartsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomChartsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomChartsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomChartsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> source = const Value.absent(),
              }) => CustomChartsCompanion(id: id, title: title, source: source),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                required String source,
              }) => CustomChartsCompanion.insert(
                id: id,
                title: title,
                source: source,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CustomChartsTable, CustomChart>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CustomChartsTable,
                    CustomChart
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CustomChartsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CustomChartsTable,
      CustomChart,
      $$CustomChartsTableFilterComposer,
      $$CustomChartsTableOrderingComposer,
      $$CustomChartsTableAnnotationComposer,
      $$CustomChartsTableCreateCompanionBuilder,
      $$CustomChartsTableUpdateCompanionBuilder,
      (
        CustomChart,
        BaseReferences<_$AppDatabase, $CustomChartsTable, CustomChart>,
      ),
      CustomChart,
      PrefetchHooks Function()
    >;
typedef $$ImageChartsTableCreateCompanionBuilder =
    ImageChartsCompanion Function({
      Value<int> id,
      required String title,
      required Uint8List image,
    });
typedef $$ImageChartsTableUpdateCompanionBuilder =
    ImageChartsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<Uint8List> image,
    });

class $$ImageChartsTableFilterComposer
    extends Composer<_$AppDatabase, $ImageChartsTable> {
  $$ImageChartsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get image => $composableBuilder(
    column: $table.image,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ImageChartsTableOrderingComposer
    extends Composer<_$AppDatabase, $ImageChartsTable> {
  $$ImageChartsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get image => $composableBuilder(
    column: $table.image,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImageChartsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ImageChartsTable> {
  $$ImageChartsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<Uint8List> get image =>
      $composableBuilder(column: $table.image, builder: (column) => column);
}

class $$ImageChartsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ImageChartsTable,
          ImageChart,
          $$ImageChartsTableFilterComposer,
          $$ImageChartsTableOrderingComposer,
          $$ImageChartsTableAnnotationComposer,
          $$ImageChartsTableCreateCompanionBuilder,
          $$ImageChartsTableUpdateCompanionBuilder,
          (
            ImageChart,
            BaseReferences<_$AppDatabase, $ImageChartsTable, ImageChart>,
          ),
          ImageChart,
          PrefetchHooks Function()
        > {
  $$ImageChartsTableTableManager(_$AppDatabase db, $ImageChartsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImageChartsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImageChartsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImageChartsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<Uint8List> image = const Value.absent(),
              }) => ImageChartsCompanion(id: id, title: title, image: image),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                required Uint8List image,
              }) => ImageChartsCompanion.insert(
                id: id,
                title: title,
                image: image,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ImageChartsTable, ImageChart>(table),
                  BaseReferences<_$AppDatabase, $ImageChartsTable, ImageChart>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ImageChartsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ImageChartsTable,
      ImageChart,
      $$ImageChartsTableFilterComposer,
      $$ImageChartsTableOrderingComposer,
      $$ImageChartsTableAnnotationComposer,
      $$ImageChartsTableCreateCompanionBuilder,
      $$ImageChartsTableUpdateCompanionBuilder,
      (
        ImageChart,
        BaseReferences<_$AppDatabase, $ImageChartsTable, ImageChart>,
      ),
      ImageChart,
      PrefetchHooks Function()
    >;
typedef $$ImportedSoloChartsTableCreateCompanionBuilder =
    ImportedSoloChartsCompanion Function({
      Value<int> id,
      required String title,
      required int schemaVersion,
      required String sourceJson,
      required String contentSha,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> reviewedAt,
    });
typedef $$ImportedSoloChartsTableUpdateCompanionBuilder =
    ImportedSoloChartsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<int> schemaVersion,
      Value<String> sourceJson,
      Value<String> contentSha,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> reviewedAt,
    });

class $$ImportedSoloChartsTableFilterComposer
    extends Composer<_$AppDatabase, $ImportedSoloChartsTable> {
  $$ImportedSoloChartsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceJson => $composableBuilder(
    column: $table.sourceJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentSha => $composableBuilder(
    column: $table.contentSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ImportedSoloChartsTableOrderingComposer
    extends Composer<_$AppDatabase, $ImportedSoloChartsTable> {
  $$ImportedSoloChartsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceJson => $composableBuilder(
    column: $table.sourceJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentSha => $composableBuilder(
    column: $table.contentSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImportedSoloChartsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ImportedSoloChartsTable> {
  $$ImportedSoloChartsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceJson => $composableBuilder(
    column: $table.sourceJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentSha => $composableBuilder(
    column: $table.contentSha,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => column,
  );
}

class $$ImportedSoloChartsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ImportedSoloChartsTable,
          ImportedSoloChart,
          $$ImportedSoloChartsTableFilterComposer,
          $$ImportedSoloChartsTableOrderingComposer,
          $$ImportedSoloChartsTableAnnotationComposer,
          $$ImportedSoloChartsTableCreateCompanionBuilder,
          $$ImportedSoloChartsTableUpdateCompanionBuilder,
          (
            ImportedSoloChart,
            BaseReferences<
              _$AppDatabase,
              $ImportedSoloChartsTable,
              ImportedSoloChart
            >,
          ),
          ImportedSoloChart,
          PrefetchHooks Function()
        > {
  $$ImportedSoloChartsTableTableManager(
    _$AppDatabase db,
    $ImportedSoloChartsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportedSoloChartsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImportedSoloChartsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImportedSoloChartsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<String> sourceJson = const Value.absent(),
                Value<String> contentSha = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> reviewedAt = const Value.absent(),
              }) => ImportedSoloChartsCompanion(
                id: id,
                title: title,
                schemaVersion: schemaVersion,
                sourceJson: sourceJson,
                contentSha: contentSha,
                createdAt: createdAt,
                updatedAt: updatedAt,
                reviewedAt: reviewedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                required int schemaVersion,
                required String sourceJson,
                required String contentSha,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> reviewedAt = const Value.absent(),
              }) => ImportedSoloChartsCompanion.insert(
                id: id,
                title: title,
                schemaVersion: schemaVersion,
                sourceJson: sourceJson,
                contentSha: contentSha,
                createdAt: createdAt,
                updatedAt: updatedAt,
                reviewedAt: reviewedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ImportedSoloChartsTable, ImportedSoloChart>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $ImportedSoloChartsTable,
                    ImportedSoloChart
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ImportedSoloChartsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ImportedSoloChartsTable,
      ImportedSoloChart,
      $$ImportedSoloChartsTableFilterComposer,
      $$ImportedSoloChartsTableOrderingComposer,
      $$ImportedSoloChartsTableAnnotationComposer,
      $$ImportedSoloChartsTableCreateCompanionBuilder,
      $$ImportedSoloChartsTableUpdateCompanionBuilder,
      (
        ImportedSoloChart,
        BaseReferences<
          _$AppDatabase,
          $ImportedSoloChartsTable,
          ImportedSoloChart
        >,
      ),
      ImportedSoloChart,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, Setting>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, Setting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CheckInsTableTableManager get checkIns =>
      $$CheckInsTableTableManager(_db, _db.checkIns);
  $$CustomChartsTableTableManager get customCharts =>
      $$CustomChartsTableTableManager(_db, _db.customCharts);
  $$ImageChartsTableTableManager get imageCharts =>
      $$ImageChartsTableTableManager(_db, _db.imageCharts);
  $$ImportedSoloChartsTableTableManager get importedSoloCharts =>
      $$ImportedSoloChartsTableTableManager(_db, _db.importedSoloCharts);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
