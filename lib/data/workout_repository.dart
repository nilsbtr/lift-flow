import 'package:drift/drift.dart';

import '../domain/exercise_search.dart';
import '../domain/finish.dart';
import '../domain/records.dart';
import '../domain/supersets.dart';
import '../domain/workout_name.dart';
import 'database.dart';
import 'template_repository.dart';

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
  const ExerciseSession(this.workout, this.sets, {this.note});
  final Workout workout;
  final List<WorkoutSet> sets;

  /// The exercise's note in this workout.
  final String? note;
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

  /// Ids of workouts that include [exerciseId].
  Future<Set<int>> workoutIdsWithExercise(int exerciseId) async {
    final rows =
        await (_db.selectOnly(_we, distinct: true)
              ..addColumns([_we.workoutId])
              ..where(_we.exerciseId.equals(exerciseId)))
            .map((r) => r.read(_we.workoutId)!)
            .get();
    return rows.toSet();
  }

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
      final notes = <int, Set<String>>{};
      for (final r in rows) {
        final w = r.readTable(_w);
        byWorkout.putIfAbsent(w.id, () => (w, [])).$2.add(r.readTable(_s));
        final note = r.readTable(_we).note;
        if (note != null) (notes[w.id] ??= {}).add(note);
      }
      return [
        for (final v in byWorkout.values)
          ExerciseSession(v.$1, v.$2, note: notes[v.$1.id]?.join('\n')),
      ];
    });
  }

  /// Finished sessions per exercise, for ranking the picker.
  Stream<Map<int, ExerciseUsage>> watchExerciseUsage() {
    final sessions = _w.id.count(distinct: true);
    final last = _w.startedAt.max();
    final q =
        _db.selectOnly(_we).join([
            innerJoin(_w, _w.id.equalsExp(_we.workoutId)),
          ])
          ..addColumns([_we.exerciseId, sessions, last])
          ..where(_w.endedAt.isNotNull())
          ..groupBy([_we.exerciseId]);
    return q.watch().map(
      (rows) => {
        for (final r in rows)
          r.read(_we.exerciseId)!: ExerciseUsage(
            r.read(sessions)!,
            r.read(last)!,
          ),
      },
    );
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
          _s.setType.equalsValue(SetType.warmup).not(),
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
      durationSeconds: s.durationSeconds,
      distanceM: s.distanceM,
      muscleGroup: e.muscleGroup,
      secondaryMuscles: e.secondaryMuscles,
      perSide: e.perSide,
      perDumbbell: e.perDumbbell,
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

  /// Starts a workout, optionally from a template or an explicit list of
  /// [items] (e.g. repeating a past workout). Throws if one is already live.
  Future<int> start({
    int? templateId,
    String? name,
    List<TemplateItem>? items,
  }) => _db.transaction(() async {
    final live = await getLive();
    if (live != null) throw LiveWorkoutExistsException(live.id);

    var title = name ?? kDefaultWorkoutName;
    var planned = items ?? const <TemplateItem>[];
    if (items == null && templateId != null) {
      final tpl = await TemplateRepository(_db).get(templateId);
      if (tpl != null) {
        title = tpl.template.name;
        planned = tpl.items;
      }
    }
    final id = await _db
        .into(_w)
        .insert(
          WorkoutsCompanion.insert(
            name: title,
            startedAt: DateTime.now(),
            templateId: Value(templateId),
          ),
        );
    for (var i = 0; i < planned.length; i++) {
      final it = planned[i];
      final weId = await _db
          .into(_we)
          .insert(
            WorkoutExercisesCompanion.insert(
              workoutId: id,
              exerciseId: it.exercise.id,
              position: i,
              targetRepsMin: Value(it.repsMin),
              targetRepsMax: Value(it.repsMax),
              restSeconds: Value(it.restSeconds),
              targetWeightKg: Value(it.targetWeightKg),
              supersetGroup: Value(it.supersetGroup),
            ),
          );
      // Set types mirror the last session so prefilled values line up.
      // Failure is an outcome, not a plan, so it isn't carried over.
      final prev = await previousSets(
        it.exercise.id,
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
              setType: Value(
                p < prev.length && prev[p].setType != SetType.failure
                    ? prev[p].setType
                    : SetType.normal,
              ),
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

  /// Writes exercise-level fields (note, rest, target weight, superset).
  Future<void> updateExercise(
    int workoutExerciseId,
    WorkoutExercisesCompanion changes,
  ) => (_db.update(
    _we,
  )..where((w) => w.id.equals(workoutExerciseId))).write(changes);

  /// Clears the superset group of the exercises among [linked] (ids) that no
  /// longer have a partner next to them.
  Future<void> _tidySupersets(int workoutId, Set<int> linked) async {
    if (linked.isEmpty) return;
    final rows =
        await (_db.select(_we)
              ..where((w) => w.workoutId.equals(workoutId))
              ..orderBy([(w) => OrderingTerm.asc(w.position)]))
            .get();
    final groups = dropLoneGroups([for (final r in rows) r.supersetGroup]);
    for (final (i, r) in rows.indexed) {
      if (r.supersetGroup == groups[i] || !linked.contains(r.id)) continue;
      await updateExercise(
        r.id,
        const WorkoutExercisesCompanion(supersetGroup: Value(null)),
      );
    }
  }

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
    SetType setType = SetType.normal,
  }) => _db
      .into(_s)
      .insertReturning(
        WorkoutSetsCompanion.insert(
          workoutExerciseId: workoutExerciseId,
          position: position,
          loadKg: Value(loadKg),
          reps: Value(reps),
          setType: Value(setType),
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
          setType: Value(s.setType),
          rpe: Value(s.rpe),
          note: Value(s.note),
          durationSeconds: Value(s.durationSeconds),
          distanceM: Value(s.distanceM),
        ),
        where: (t) => t.id.equals(s.id),
      );
    }
  });

  Future<void> rename(int workoutId, String name) =>
      (_db.update(_w)..where((w) => w.id.equals(workoutId))).write(
        WorkoutsCompanion(name: Value(name.trim())),
      );

  /// Moves a workout in time. Callers check the pair with `workoutTimesError`.
  Future<void> setTimes(int workoutId, DateTime start, DateTime end) =>
      (_db.update(_w)..where((w) => w.id.equals(workoutId))).write(
        WorkoutsCompanion(startedAt: Value(start), endedAt: Value(end)),
      );

  Future<void> setNote(int workoutId, String? note) {
    final n = note?.trim();
    return (_db.update(_w)..where((w) => w.id.equals(workoutId))).write(
      WorkoutsCompanion(note: Value(n == null || n.isEmpty ? null : n)),
    );
  }

  Future<void> discard(int workoutId) =>
      (_db.delete(_w)..where((w) => w.id.equals(workoutId))).go();

  /// Creates an empty finished workout to fill in afterwards. It never counts
  /// as live, so this works while a workout is running. It also clears out
  /// earlier ones that were abandoned without a set.
  Future<int> createPast(
    DateTime start,
    DateTime end, {
    double? bodyweightKg,
  }) => _db.transaction(() async {
    await purgeEmpty();
    return _db
        .into(_w)
        .insert(
          WorkoutsCompanion.insert(
            name: 'Workout',
            startedAt: start,
            endedAt: Value(end),
            bodyweightKg: Value(bodyweightKg),
          ),
        );
  });

  /// Deletes finished workouts that were never saved and have no completed
  /// set, which only exist when a past workout was abandoned. Returns how
  /// many were removed.
  Future<int> purgeEmpty() {
    final logged =
        _db.selectOnly(_we).join([
            innerJoin(_s, _s.workoutExerciseId.equalsExp(_we.id)),
          ])
          ..addColumns([_we.workoutId])
          ..where(_s.isCompleted);
    return (_db.delete(_w)..where(
          (w) =>
              w.endedAt.isNotNull() &
              w.exerciseCount.equals(0) &
              w.id.isNotInQuery(logged),
        ))
        .go();
  }

  /// Finalizes a workout: drops unchecked sets and empty exercises, snapshots
  /// body weight and writes the summary from working sets. Keeps an existing
  /// [Workout.endedAt] when editing a past workout. Returns false if no set
  /// was completed (the workout is deleted in that case).
  ///
  /// [endedAt] ends the workout then instead of now, kept between its start and
  /// now. [name] replaces the workout's name.
  Future<bool> finish(
    int workoutId, {
    required double? bodyweightKg,
    bool keepEndedAt = false,
    DateTime? endedAt,
    String? name,
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
        if (s.setType.isWarmup) continue;
        totalSets++;
        volume += setVolume(
          type: ex.exercise.trackingType,
          loadKg: s.loadKg,
          reps: s.reps,
          bodyweightKg: bodyweightKg,
          perSide: ex.exercise.perSide,
          perDumbbell: ex.exercise.perDumbbell,
        );
      }
    }

    if (completed == 0) {
      await discard(workoutId);
      return false;
    }
    // A superset whose partner was dropped above is no superset any more.
    final spans = supersetSpans([
      for (final ex in loaded.exercises) ex.row.supersetGroup,
    ]);
    await _tidySupersets(workoutId, {
      for (final (i, ex) in loaded.exercises.indexed)
        if (spans[i] != null) ex.row.id,
    });

    final now = DateTime.now();
    final keep =
        endedAt == null && keepEndedAt && loaded.workout.endedAt != null;
    await (_db.update(_w)..where((w) => w.id.equals(workoutId))).write(
      WorkoutsCompanion(
        endedAt: keep
            ? const Value.absent()
            : Value(
                endWithin(
                  endedAt ?? now,
                  start: loaded.workout.startedAt,
                  now: now,
                ),
              ),
        name: name == null ? const Value.absent() : Value(name.trim()),
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
