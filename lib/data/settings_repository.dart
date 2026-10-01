import 'package:drift/drift.dart';

import 'database.dart';

class SettingsRepository {
  SettingsRepository(this._db);
  final AppDatabase _db;

  Future<UserSettings> get() =>
      (_db.select(_db.appSettings)..where((s) => s.id.equals(1))).getSingle();

  Future<void> write(AppSettingsCompanion changes) => (_db.update(
    _db.appSettings,
  )..where((s) => s.id.equals(1))).write(changes);
}

class RestRepository {
  RestRepository(this._db);
  final AppDatabase _db;

  Future<RestStateRow?> get() => _db.select(_db.restState).getSingleOrNull();

  Future<void> save(DateTime endsAt, int totalSeconds) => _db
      .into(_db.restState)
      .insertOnConflictUpdate(
        RestStateCompanion.insert(
          id: const Value(1),
          endsAt: endsAt,
          totalSeconds: totalSeconds,
        ),
      );

  Future<void> clear() => _db.delete(_db.restState).go();
}
