import 'package:drift/drift.dart';

import '../domain/records.dart';
import 'database.dart';

class LiveWorkoutExistsException implements Exception {
  const LiveWorkoutExistsException(this.workoutId);
  final int workoutId;
}

class LoadedExercise {
  const LoadedExercise(this.row, this.exercise, this.sets);
  final WorkoutExercise row;
  final Exercise exercise;
  final List<WorkoutSet> sets;
}

class LoadedWorkout {
  const LoadedWorkout(this.workout, this.exercises);
  final Workout workout;
  final List<LoadedExercise> exercises;
}

class ExerciseSession {
  const ExerciseSession(this.workout, this.sets);
  final Workout workout;
  final List<WorkoutSet> sets;
}

class WorkoutRepository {
  WorkoutRepository(this._db);
  final AppDatabase _db;

  $WorkoutsTable get _w => _db.workouts;
  $WorkoutExercisesTable get _we => _db.workoutExercises;
  $WorkoutSetsTable get _s => _db.workoutSets;

  // ---------------------------------------------------------------- queries

  Stream<Workout?> watchLive() =>
      (_db.select(_w)
            ..where((w) => w.endedAt.isNull())
            ..limit(1))
          .watchSingleOrNull();

  Future<Workout?> getLive() =>
      (_db.select(_w)
            ..where((w) => w.endedAt.isNull())
            ..limit(1))
          .getSingleOrNull();

  Stream<List<Workout>> watchHistory() =>
      (_db.select(_w)
            ..where((w) => w.endedAt.isNotNull())
            ..orderBy([(w) => OrderingTerm.desc(w.startedAt)]))
          .watch();

  Future<LoadedWorkout?> load(int id) async {
    final workout = await (_db.select(
      _w,
    )..where((w) => w.id.equals(id))).getSingleOrNull();
    if (workout == null) return null;
    final e = _db.exercises;
    final rows =
        await (_db.select(_we).join([
                innerJoin(e, e.id.equalsExp(_we.exerciseId)),
              ])
              ..where(_we.workoutId.equals(id))
              ..orderBy([OrderingTerm.asc(_we.position)]))
            .get();
    final ids = [for (final r in rows) r.readTable(_we).id];
    final sets = ids.isEmpty
        ? const <WorkoutSet>[]
        : await (_db.select(_s)
                ..where((s) => s.workoutExerciseId.isIn(ids))
                ..orderBy([
                  (s) => OrderingTerm.asc(s.position),
                  (s) => OrderingTerm.asc(s.id),
                ]))
              .get();
    final byWe = <int, List<WorkoutSet>>{};
    for (final s in sets) {
      (byWe[s.workoutExerciseId] ??= []).add(s);
    }
    return LoadedWorkout(workout, [
      for (final r in rows)
        LoadedExercise(
          r.readTable(_we),
          r.readTable(e),
          byWe[r.readTable(_we).id] ?? const [],
        ),
    ]);
  }

  Stream<LoadedWorkout?> watchLoaded(int id) async* {
    yield await load(id);
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([_w, _we, _s, _db.exercises]),
    )) {
      yield await load(id);
    }
  }

  /// Completed sets of the most recent finished session of [exerciseId]
  /// that started before [before], excluding [excludeWorkoutId].
  Future<List<WorkoutSet>> previousSets(
    int exerciseId, {
    required int excludeWorkoutId,
    required DateTime before,
  }) async {
    final row =
        await (_db.select(_we).join([
                innerJoin(_w, _w.id.equalsExp(_we.workoutId)),
              ])
              ..where(
                _we.exerciseId.equals(exerciseId) &
                    _w.endedAt.isNotNull() &
                    _w.id.equals(excludeWorkoutId).not() &
                    _w.startedAt.isSmallerOrEqualValue(before),
              )
              ..orderBy([OrderingTerm.desc(_w.startedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return const [];
    final weId = row.readTable(_we).id;
    return (_db.select(_s)
          ..where((s) => s.workoutExerciseId.equals(weId) & s.isCompleted)
          ..orderBy([(s) => OrderingTerm.asc(s.position)]))
        .get();
  }

  /// All finished sessions of an exercise, newest first.
  Stream<List<ExerciseSession>> watchExerciseSessions(int exerciseId) {
    final q =
        _db.select(_s).join([
            innerJoin(_we, _we.id.equalsExp(_s.workoutExerciseId)),
            innerJoin(_w, _w.id.equalsExp(_we.workoutId)),
          ])
          ..where(
            _we.exerciseId.equals(exerciseId) &
                _w.endedAt.isNotNull() &
                _s.isCompleted,
          )
          ..orderBy([
            OrderingTerm.desc(_w.startedAt),
            OrderingTerm.asc(_we.position),
            OrderingTerm.asc(_s.position),
          ]);
    return q.watch().map((rows) {
      final byWorkout = <int, (Workout, List<WorkoutSet>)>{};
      for (final r in rows) {
        final w = r.readTable(_w);
        byWorkout.putIfAbsent(w.id, () => (w, [])).$2.add(r.readTable(_s));
      }
      return [for (final v in byWorkout.values) ExerciseSession(v.$1, v.$2)];
    });
  }

  /// Completed working sets from finished workouts for the given exercises.
  Future<List<SetFact>> setFacts(Iterable<int> exerciseIds) async {
    final ids = exerciseIds.toSet().toList();
    if (ids.isEmpty) return const [];
    return _factsQuery(_we.exerciseId.isIn(ids)).map(_fact).get();
  }

  /// Completed working sets of finished workouts started at or after [since].
  Stream<List<SetFact>> watchStatFacts(DateTime since) => _factsQuery(
    _w.startedAt.isBiggerOrEqualValue(since),
  ).map(_fact).watch();

  JoinedSelectStatement<HasResultSet, dynamic> _factsQuery(
    Expression<bool> filter,
  ) {
    final e = _db.exercises;
    return _db.select(_s).join([
      innerJoin(_we, _we.id.equalsExp(_s.workoutExerciseId)),
      innerJoin(_w, _w.id.equalsExp(_we.workoutId)),
      innerJoin(e, e.id.equalsExp(_we.exerciseId)),
    ])..where(
      filter &
          _w.endedAt.isNotNull() &
          _s.isCompleted &
          _s.isWarmup.not(),
    );
  }

  SetFact _fact(TypedResult r) {
    final w = r.readTable(_w);
    final e = r.readTable(_db.exercises);
    final s = r.readTable(_s);
    return SetFact(
      workoutId: w.id,
      startedAt: w.startedAt,
      exerciseId: e.id,
      type: e.trackingType,
      mode: e.loadMode,
      loadKg: s.loadKg,
      reps: s.reps,
      bodyweightKg: w.bodyweightKg,
      muscleGroup: e.muscleGroup,
    );
  }

  Future<Map<int, Set<PrKind>>> prsFor(int workoutId) async {
    final ids =
        await (_db.selectOnly(_we)
              ..addColumns([_we.exerciseId])
              ..where(_we.workoutId.equals(workoutId)))
            .map((r) => r.read(_we.exerciseId)!)
            .get();
    return computePrs(await setFacts(ids), workoutId);
  }

  // ---------------------------------------------------------------- commands

  /// Starts a workout, optionally from a template. Throws if one is already live.
  Future<int> start({int? templateId}) => _db.transaction(() async {
    final live = await getLive();
    if (live != null) throw LiveWorkoutExistsException(live.id);

    String name = 'Workout';
    List<TemplateExercise> items = const [];
    if (templateId != null) {
      final tpl = await (_db.select(
        _db.workoutTemplates,
      )..where((t) => t.id.equals(templateId))).getSingleOrNull();
      if (tpl != null) {
        name = tpl.name;
        items =
            await (_db.select(_db.templateExercises)
                  ..where((t) => t.templateId.equals(templateId))
                  ..orderBy([(t) => OrderingTerm.asc(t.position)]))
                .get();
      }
    }
    final id = await _db
        .into(_w)
        .insert(
          WorkoutsCompanion.insert(
            name: name,
            startedAt: DateTime.now(),
            templateId: Value(templateId),
          ),
        );
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final weId = await _db
          .into(_we)
          .insert(
            WorkoutExercisesCompanion.insert(
              workoutId: id,
              exerciseId: it.exerciseId,
              position: i,
              targetRepsMin: Value(it.repsMin),
              targetRepsMax: Value(it.repsMax),
            ),
          );
      // Warm-ups mirror the last session so prefilled values line up.
      final prev = await previousSets(
        it.exerciseId,
        excludeWorkoutId: id,
        before: DateTime.now(),
      );
      await _db.batch((b) {
        for (var p = 0; p < it.targetSets; p++) {
          b.insert(
            _s,
            WorkoutSetsCompanion.insert(
              workoutExerciseId: weId,
              position: p,
              isWarmup: Value(p < prev.length && prev[p].isWarmup),
            ),
          );
        }
      });
    }
    return id;
  });

  Future<(WorkoutExercise, List<WorkoutSet>)> addExercise(
    int workoutId,
    int exerciseId, {
    required int position,
    int sets = 1,
  }) => _db.transaction(() async {
    final we = await _db
        .into(_we)
        .insertReturning(
          WorkoutExercisesCompanion.insert(
            workoutId: workoutId,
            exerciseId: exerciseId,
            position: position,
          ),
        );
    final created = <WorkoutSet>[];
    for (var p = 0; p < sets; p++) {
      created.add(
        await _db
            .into(_s)
            .insertReturning(
              WorkoutSetsCompanion.insert(
                workoutExerciseId: we.id,
                position: p,
              ),
            ),
      );
    }
    return (we, created);
  });

  Future<void> removeExercise(int workoutExerciseId) =>
      (_db.delete(_we)..where((w) => w.id.equals(workoutExerciseId))).go();

  Future<void> reorderExercises(List<int> workoutExerciseIds) => _db.batch((b) {
    for (var i = 0; i < workoutExerciseIds.length; i++) {
      b.update(
        _we,
        WorkoutExercisesCompanion(position: Value(i)),
        where: (w) => w.id.equals(workoutExerciseIds[i]),
      );
    }
  });

  Future<WorkoutSet> addSet(
    int workoutExerciseId, {
    required int position,
    double? loadKg,
    int? reps,
  }) => _db
      .into(_s)
      .insertReturning(
        WorkoutSetsCompanion.insert(
          workoutExerciseId: workoutExerciseId,
          position: position,
          loadKg: Value(loadKg),
          reps: Value(reps),
        ),
      );

  Future<void> deleteSet(int id) =>
      (_db.delete(_s)..where((s) => s.id.equals(id))).go();

  Future<void> writeSets(Iterable<WorkoutSet> sets) => _db.batch((b) {
    for (final s in sets) {
      b.update(
        _s,
        WorkoutSetsCompanion(
          position: Value(s.position),
          loadKg: Value(s.loadKg),
          reps: Value(s.reps),
          isCompleted: Value(s.isCompleted),
          completedAt: Value(s.completedAt),
          isWarmup: Value(s.isWarmup),
        ),
        where: (t) => t.id.equals(s.id),
      );
    }
  });

  Future<void> rename(int workoutId, String name) =>
      (_db.update(_w)..where((w) => w.id.equals(workoutId))).write(
        WorkoutsCompanion(name: Value(name.trim())),
      );

  Future<void> discard(int workoutId) =>
      (_db.delete(_w)..where((w) => w.id.equals(workoutId))).go();

  /// Finalizes a workout: drops unchecked sets and empty exercises, snapshots
  /// body weight and writes the summary from working sets. Keeps an existing
  /// [Workout.endedAt] when editing a past workout. Returns false if no set
  /// was completed (the workout is deleted in that case).
  Future<bool> finish(
    int workoutId, {
    required double? bodyweightKg,
    bool keepEndedAt = false,
  }) => _db.transaction(() async {
    final loaded = await load(workoutId);
    if (loaded == null) return false;

    var completed = 0;
    var totalSets = 0;
    var volume = 0.0;
    var exerciseCount = 0;
    var position = 0;
    for (final ex in loaded.exercises) {
      final kept = [
        for (final s in ex.sets)
          if (s.isCompleted) s,
      ];
      final dropped = [
        for (final s in ex.sets)
          if (!s.isCompleted) s.id,
      ];
      if (dropped.isNotEmpty) {
        await (_db.delete(_s)..where((s) => s.id.isIn(dropped))).go();
      }
      if (kept.isEmpty) {
        await removeExercise(ex.row.id);
        continue;
      }
      await (_db.update(_we)..where((w) => w.id.equals(ex.row.id))).write(
        WorkoutExercisesCompanion(position: Value(position++)),
      );
      for (var i = 0; i < kept.length; i++) {
        if (kept[i].position != i) {
          await (_db.update(_s)..where((s) => s.id.equals(kept[i].id))).write(
            WorkoutSetsCompanion(position: Value(i)),
          );
        }
      }
      exerciseCount++;
      completed += kept.length;
      for (final s in kept) {
        if (s.isWarmup) continue;
        totalSets++;
        volume += setVolume(
          type: ex.exercise.trackingType,
          loadKg: s.loadKg,
          reps: s.reps,
          bodyweightKg: bodyweightKg,
        );
      }
    }

    if (completed == 0) {
      await discard(workoutId);
      return false;
    }

    await (_db.update(_w)..where((w) => w.id.equals(workoutId))).write(
      WorkoutsCompanion(
        endedAt: keepEndedAt && loaded.workout.endedAt != null
            ? const Value.absent()
            : Value(DateTime.now()),
        bodyweightKg: Value(bodyweightKg),
        totalSets: Value(totalSets),
        totalVolumeKg: Value(volume),
        exerciseCount: Value(exerciseCount),
      ),
    );
    return true;
  });

  Future<void> deleteWorkout(int workoutId) => discard(workoutId);
}
