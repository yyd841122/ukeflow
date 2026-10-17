// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_charts_dao.dart';

// ignore_for_file: type=lint
mixin _$ImageChartsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ImageChartsTable get imageCharts => attachedDatabase.imageCharts;
  ImageChartsDaoManager get managers => ImageChartsDaoManager(this);
}

class ImageChartsDaoManager {
  final _$ImageChartsDaoMixin _db;
  ImageChartsDaoManager(this._db);
  $$ImageChartsTableTableManager get imageCharts =>
      $$ImageChartsTableTableManager(_db.attachedDatabase, _db.imageCharts);
}
