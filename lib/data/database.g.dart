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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CheckInsTable checkIns = $CheckInsTable(this);
  late final $CustomChartsTable customCharts = $CustomChartsTable(this);
  late final CheckInsDao checkInsDao = CheckInsDao(this as AppDatabase);
  late final CustomChartsDao customChartsDao = CustomChartsDao(
    this as AppDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [checkIns, customCharts];
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CheckInsTableTableManager get checkIns =>
      $$CheckInsTableTableManager(_db, _db.checkIns);
  $$CustomChartsTableTableManager get customCharts =>
      $$CustomChartsTableTableManager(_db, _db.customCharts);
}
