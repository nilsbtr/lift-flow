import 'package:drift/drift.dart';

import '../domain/records.dart';
import 'database.dart';

class DuplicateNameException implements Exception {
  const DuplicateNameException(this.name);
  final String name;
  @override
  String toString() => 'An exercise named "$name" already exists.';
}

class ExerciseInUseException implements Exception {
  const ExerciseInUseException();
  @override
  String toString() => 'This exercise has logged workouts. Archive it instead.';
}

class ExerciseRepository {
  ExerciseRepository(this._db);
  final AppDatabase _db;

  $ExercisesTable get _t => _db.exercises;

  Stream<List<Exercise>> watchActive() {
    final q = _db.select(_t)
      ..where((e) => e.isArchived.equals(false))
      ..orderBy([
        (e) => OrderingTerm(expression: e.name.collate(Collate.noCase)),
      ]);
    return q.watch();
  }

  Stream<List<Exercise>> watchArchived() {
    final q = _db.select(_t)
      ..where((e) => e.isArchived.equals(true))
      ..orderBy([
        (e) => OrderingTerm(expression: e.name.collate(Collate.noCase)),
      ]);
    return q.watch();
  }

  Stream<Exercise?> watchById(int id) =>
      (_db.select(_t)..where((e) => e.id.equals(id))).watchSingleOrNull();

  Future<Exercise?> getById(int id) =>
      (_db.select(_t)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<bool> _nameTaken(String name, {int? exceptId}) async {
    final q = _db.select(_t)
      ..where((e) {
        Expression<bool> c = e.name.lower().equals(name.toLowerCase());
        if (exceptId != null) c = c & e.id.equals(exceptId).not();
        return c;
      })
      ..limit(1);
    return (await q.getSingleOrNull()) != null;
  }

  static String normalizeName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<Exercise> create({
    required String name,
    required MuscleGroup muscleGroup,
    required TrackingType trackingType,
    LoadMode loadMode = LoadMode.none,
    String? notes,
    Equipment equipment = Equipment.none,
    bool perSide = false,
    bool perDumbbell = false,
    List<MuscleGroup> secondaryMuscles = const [],
  }) async {
    final n = normalizeName(name);
    if (n.isEmpty || n.length > 60) {
      throw ArgumentError.value(name, 'name');
    }
    if (await _nameTaken(n)) throw DuplicateNameException(n);
    return _db
        .into(_t)
        .insertReturning(
          ExercisesCompanion.insert(
            name: n,
            muscleGroup: muscleGroup,
            trackingType: trackingType,
            loadMode: Value(
              trackingType == TrackingType.weights ? LoadMode.none : loadMode,
            ),
            notes: Value(_cleanNotes(notes)),
            createdAt: DateTime.now(),
            equipment: Value(equipment),
            perSide: Value(perSide),
            perDumbbell: Value(perDumbbell),
            secondaryMuscles: Value(_secondary(secondaryMuscles, muscleGroup)),
          ),
        );
  }

  /// Null [equipment], [perSide], [perDumbbell] and [secondaryMuscles] keep
  /// the stored values. Changing [perSide] or [perDumbbell] recalculates the
  /// volume of the finished workouts that contain the exercise.
  Future<void> update(
    int id, {
    required String name,
    required MuscleGroup muscleGroup,
    required TrackingType trackingType,
    required LoadMode loadMode,
    String? notes,
    Equipment? equipment,
    bool? perSide,
    bool? perDumbbell,
    List<MuscleGroup>? secondaryMuscles,
  }) async {
    final n = normalizeName(name);
    if (n.isEmpty || n.length > 60) {
      throw ArgumentError.value(name, 'name');
    }
    return _db.transaction(() async {
      if (await _nameTaken(n, exceptId: id)) throw DuplicateNameException(n);
      final current = await getById(id);
      if (current == null) return;
      var type = trackingType;
      if (type != current.trackingType && await hasLoggedSets(id)) {
        type = current.trackingType;
      }
      await (_db.update(_t)..where((e) => e.id.equals(id))).write(
        ExercisesCompanion(
          name: Value(n),
          muscleGroup: Value(muscleGroup),
          trackingType: Value(type),
          loadMode: Value(
            type == TrackingType.weights ? LoadMode.none : loadMode,
          ),
          notes: Value(_cleanNotes(notes)),
          equipment: Value.absentIfNull(equipment),
          perSide: Value.absentIfNull(perSide),
          perDumbbell: Value.absentIfNull(perDumbbell),
          secondaryMuscles: Value(
            _secondary(
              secondaryMuscles ?? current.secondaryMuscles,
              muscleGroup,
            ),
          ),
        ),
      );
      if ((perSide ?? current.perSide) != current.perSide ||
          (perDumbbell ?? current.perDumbbell) != current.perDumbbell) {
        await _recomputeVolumes(id);
      }
    });
  }

  /// Rewrites [Workouts.totalVolumeKg] of the finished workouts containing
  /// [exerciseId] from their completed working sets.
  Future<void> _recomputeVolumes(int exerciseId) async {
    final w = _db.workouts;
    final we = _db.workoutExercises;
    final s = _db.workoutSets;
    final ids =
        await (_db.selectOnly(we)
              ..addColumns([we.workoutId])
              ..where(we.exerciseId.equals(exerciseId)))
            .map((r) => r.read(we.workoutId)!)
            .get();
    final workouts = await (_db.select(
      w,
    )..where((x) => x.id.isIn(ids) & x.endedAt.isNotNull())).get();
    for (final workout in workouts) {
      final rows =
          await (_db.select(s).join([
                innerJoin(we, we.id.equalsExp(s.workoutExerciseId)),
                innerJoin(_t, _t.id.equalsExp(we.exerciseId)),
              ])..where(
                we.workoutId.equals(workout.id) &
                    s.isCompleted &
                    s.setType.equalsValue(SetType.warmup).not(),
              ))
              .get();
      var volume = 0.0;
      for (final r in rows) {
        final e = r.readTable(_t);
        final set = r.readTable(s);
        volume += setVolume(
          type: e.trackingType,
          loadKg: set.loadKg,
          reps: set.reps,
          bodyweightKg: workout.bodyweightKg,
          perSide: e.perSide,
          perDumbbell: e.perDumbbell,
        );
      }
      await (_db.update(w)..where((x) => x.id.equals(workout.id))).write(
        WorkoutsCompanion(totalVolumeKg: Value(volume)),
      );
    }
  }

  Future<bool> hasLoggedSets(int exerciseId) async {
    final we = _db.workoutExercises;
    final q = _db.selectOnly(we)
      ..addColumns([we.id])
      ..where(we.exerciseId.equals(exerciseId))
      ..limit(1);
    return (await q.getSingleOrNull()) != null;
  }

  Future<void> setArchived(int id, bool archived) =>
      (_db.update(_t)..where((e) => e.id.equals(id))).write(
        ExercisesCompanion(isArchived: Value(archived)),
      );

  /// Deletes an exercise that has never been used in a workout. Also removes
  /// it from any templates.
  Future<void> delete(int id) => _db.transaction(() async {
    if (await hasLoggedSets(id)) throw const ExerciseInUseException();
    await (_db.delete(
      _db.templateExercises,
    )..where((t) => t.exerciseId.equals(id))).go();
    await (_db.delete(_t)..where((e) => e.id.equals(id))).go();
  });

  /// Distinct secondary groups without the primary one.
  static List<MuscleGroup> _secondary(
    List<MuscleGroup> groups,
    MuscleGroup primary,
  ) => [
    for (final g in groups.toSet())
      if (g != primary) g,
  ];

  static String? _cleanNotes(String? notes) {
    final t = notes?.trim();
    return t == null || t.isEmpty ? null : t;
  }
}
