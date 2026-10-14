// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custom_charts_dao.dart';

// ignore_for_file: type=lint
mixin _$CustomChartsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CustomChartsTable get customCharts => attachedDatabase.customCharts;
  CustomChartsDaoManager get managers => CustomChartsDaoManager(this);
}

class CustomChartsDaoManager {
  final _$CustomChartsDaoMixin _db;
  CustomChartsDaoManager(this._db);
  $$CustomChartsTableTableManager get customCharts =>
      $$CustomChartsTableTableManager(_db.attachedDatabase, _db.customCharts);
}
