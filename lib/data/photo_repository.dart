import 'package:drift/drift.dart';

import '../domain/photos.dart';
import 'database.dart';

/// Progress photo rows. The image files are [PhotoStorage]'s business.
class PhotoRepository {
  PhotoRepository(this._db);
  final AppDatabase _db;

  $ProgressPhotosTable get _p => _db.progressPhotos;

  /// All photos, newest first.
  Stream<List<ProgressPhoto>> watchAll() => _newestFirst().watch();

  Future<List<ProgressPhoto>> all() => _newestFirst().get();

  SimpleSelectStatement<$ProgressPhotosTable, ProgressPhoto> _newestFirst() =>
      _db.select(_p)..orderBy([
        (p) => OrderingTerm.desc(p.takenAt),
        (p) => OrderingTerm.desc(p.id),
      ]);

  Future<ProgressPhoto> add({
    required DateTime takenAt,
    required String fileName,
    String? note,
  }) => _db
      .into(_p)
      .insertReturning(
        ProgressPhotosCompanion.insert(
          takenAt: takenAt,
          fileName: fileName,
          note: Value(cleanNote(note)),
        ),
      );

  /// Adds rows in one go, oldest first so ids follow the dates.
  Future<void> addAll(
    Iterable<({DateTime takenAt, String fileName, String? note})> rows,
  ) => _db.batch(
    (b) => b.insertAll(_p, [
      for (final r in rows)
        ProgressPhotosCompanion.insert(
          takenAt: r.takenAt,
          fileName: r.fileName,
          note: Value(cleanNote(r.note)),
        ),
    ]),
  );

  Future<void> setTakenAt(int id, DateTime takenAt) =>
      (_db.update(_p)..where((p) => p.id.equals(id))).write(
        ProgressPhotosCompanion(takenAt: Value(takenAt)),
      );

  Future<void> setNote(int id, String? note) =>
      (_db.update(_p)..where((p) => p.id.equals(id))).write(
        ProgressPhotosCompanion(note: Value(cleanNote(note))),
      );

  Future<void> delete(int id) =>
      (_db.delete(_p)..where((p) => p.id.equals(id))).go();

  Future<void> deleteAll() => _db.delete(_p).go();
}
