// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'checkins_dao.dart';

// ignore_for_file: type=lint
mixin _$CheckInsDaoMixin on DatabaseAccessor<AppDatabase> {
  $CheckInsTable get checkIns => attachedDatabase.checkIns;
  CheckInsDaoManager get managers => CheckInsDaoManager(this);
}

class CheckInsDaoManager {
  final _$CheckInsDaoMixin _db;
  CheckInsDaoManager(this._db);
  $$CheckInsTableTableManager get checkIns =>
      $$CheckInsTableTableManager(_db.attachedDatabase, _db.checkIns);
}
