import 'package:drift/drift.dart';

import 'database.dart';

class BodyweightRepository {
  BodyweightRepository(this._db);
  final AppDatabase _db;

  $BodyweightEntriesTable get _b => _db.bodyweightEntries;

  /// All entries, oldest first.
  Stream<List<BodyweightEntry>> watchAll() =>
      (_db.select(_b)..orderBy([(b) => OrderingTerm.asc(b.date)])).watch();

  Future<BodyweightEntry?> latest() =>
      (_db.select(_b)
            ..orderBy([(b) => OrderingTerm.desc(b.date)])
            ..limit(1))
          .getSingleOrNull();

  /// Stores [kg] for the local day of [at], replacing that day's entry.
  Future<void> upsertDay(DateTime at, double kg) => _db
      .into(_b)
      .insertOnConflictUpdate(
        BodyweightEntriesCompanion.insert(
          date: DateTime(at.year, at.month, at.day),
          kg: kg,
        ),
      );

  Future<void> delete(DateTime date) =>
      (_db.delete(_b)..where((b) => b.date.equals(date))).go();
}
