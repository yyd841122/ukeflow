// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'flowing_sessions_dao.dart';

// ignore_for_file: type=lint
mixin _$FlowingSessionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $FlowingSessionsTable get flowingSessions => attachedDatabase.flowingSessions;
  FlowingSessionsDaoManager get managers => FlowingSessionsDaoManager(this);
}

class FlowingSessionsDaoManager {
  final _$FlowingSessionsDaoMixin _db;
  FlowingSessionsDaoManager(this._db);
  $$FlowingSessionsTableTableManager get flowingSessions =>
      $$FlowingSessionsTableTableManager(
        _db.attachedDatabase,
        _db.flowingSessions,
      );
}
