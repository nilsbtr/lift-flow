import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../../data/database.dart';
import '../../data/workout_repository.dart';
import '../../domain/loading.dart';
import '../../domain/records.dart';
import '../../domain/supersets.dart';
import '../../domain/workout_name.dart';
import '../../providers.dart';

@immutable
class DraftExercise {
  const DraftExercise({
    required this.id,
    required this.exercise,
    required this.sets,
    required this.previous,
    this.bests,
    this.repsMin,
    this.repsMax,
    this.restSeconds,
    this.note,
    this.supersetGroup,
    this.targetWeightKg,
    this.stepKg,
  });

  /// WorkoutExercise id.
  final int id;
  final Exercise exercise;
  final List<WorkoutSet> sets;

  /// Completed sets of the last session of this exercise.
  final List<WorkoutSet> previous;

  /// Bests from before this workout. Null without earlier history.
  final ExerciseBests? bests;
  final int? repsMin;
  final int? repsMax;

  /// Rest after a set. Null uses the default from settings.
  final int? restSeconds;

  /// Note for this exercise in this workout.
  final String? note;

  /// Neighbours sharing a value form a superset.
  final int? supersetGroup;

  /// Planned weight, the hint while there is no previous session.
  final double? targetWeightKg;

  /// Smallest step the load can go up by. Null turns off suggested increases
  /// and warm-up sets.
  final double? stepKg;

  DraftExercise copyWith({
    List<WorkoutSet>? sets,
    Exercise? exercise,
    List<WorkoutSet>? previous,
    ExerciseBests? Function()? bests,
    int? Function()? restSeconds,
    String? Function()? note,
    int? Function()? supersetGroup,
    double? Function()? targetWeightKg,
    double? Function()? stepKg,
  }) => DraftExercise(
    id: id,
    exercise: exercise ?? this.exercise,
    sets: sets ?? this.sets,
    previous: previous ?? this.previous,
    bests: bests != null ? bests() : this.bests,
    repsMin: repsMin,
    repsMax: repsMax,
    restSeconds: restSeconds != null ? restSeconds() : this.restSeconds,
    note: note != null ? note() : this.note,
    supersetGroup: supersetGroup != null ? supersetGroup() : this.supersetGroup,
    targetWeightKg: targetWeightKg != null
        ? targetWeightKg()
        : this.targetWeightKg,
    stepKg: stepKg != null ? stepKg() : this.stepKg,
  );

  TrackingType get type => exercise.trackingType;
  LoadMode get mode => exercise.loadMode;

  /// Whether this exercise has an editable load column.
  bool get hasLoad => type == TrackingType.weights || mode != LoadMode.none;

  bool _fits(double? load) {
    if (load == null) return false;
    if (type == TrackingType.weights) return load >= 0;
    return switch (mode) {
      LoadMode.none => false,
      LoadMode.added => load >= 0,
      LoadMode.assisted => load <= 0,
    };
  }

  /// The set of the last session that the set at [index] repeats: warm-ups
  /// line up with warm-ups and working sets with working sets, in order.
  WorkoutSet? previousFor(int index) {
    final warmup = sets[index].setType.isWarmup;
    var n = sets.take(index).where((s) => s.setType.isWarmup == warmup).length;
    for (final p in previous) {
      if (p.setType.isWarmup == warmup && n-- == 0) return p;
    }
    return null;
  }

  /// The step to go up by: set when the exercise has a rep range and every
  /// working set of the last session reached its top. Null otherwise.
  double? get increaseKg {
    final min = repsMin;
    final max = repsMax;
    final step = stepKg;
    if (min == null || max == null || max <= min || step == null) return null;
    switch (type) {
      case TrackingType.weights:
        final working = previous.where((s) => !s.setType.isWarmup);
        final topped = working.every(
          (s) => _fits(s.loadKg) && (s.reps ?? 0) >= max,
        );
        return working.isNotEmpty && topped ? step : null;
      case TrackingType.bodyweight:
      case TrackingType.duration:
      case TrackingType.distance:
        return null;
    }
  }

  /// The nearest set above [index] of the same kind: a working set doesn't
  /// copy a warm-up. -1 if there is none.
  int _above(int index) {
    final warmup = sets[index].setType.isWarmup;
    return sets
        .take(index)
        .toList()
        .lastIndexWhere((s) => s.setType.isWarmup == warmup);
  }

  /// Placeholder values for a set: previous session → set above → target.
  /// With [increaseKg], working sets get the last load plus that step and the
  /// bottom of the rep range instead, flagged as `increase`.
  ({double? load, int? reps, bool increase}) hintFor(int index) {
    final prev = previousFor(index);
    final warmup = sets[index].setType.isWarmup;
    double? load;
    int? reps;
    var increase = false;
    if (prev != null) {
      if (_fits(prev.loadKg)) load = prev.loadKg;
      reps = prev.reps;
      final step = warmup ? null : increaseKg;
      if (step != null && load != null) {
        load += step;
        reps = repsMin;
        increase = true;
      }
    }
    final up = _above(index);
    if (up >= 0 && (load == null || reps == null)) {
      final above = sets[up];
      final aboveHint = hintFor(up);
      if (hasLoad && load == null) {
        final l = above.loadKg ?? aboveHint.load;
        if (_fits(l)) {
          load = l;
          increase = above.loadKg == null && aboveHint.increase;
        }
      }
      reps ??= above.reps ?? aboveHint.reps;
    }
    if (!warmup && load == null && _fits(targetWeightKg)) load = targetWeightKg;
    reps = type.hasReps ? reps ?? repsMin : null;
    return hasLoad
        ? (load: load, reps: reps, increase: increase)
        : (load: null, reps: reps, increase: false);
  }

  /// Placeholder time or distance for a set: previous session → set above.
  /// Only what the type needs has one. The time of a distance set is
  /// optional, so it never takes a hint.
  ({int? seconds, double? metres}) timedHintFor(int index) {
    if (type.hasReps) return (seconds: null, metres: null);
    final distance = type == TrackingType.distance;
    final prev = previousFor(index);
    var seconds = distance ? null : prev?.durationSeconds;
    var metres = distance ? prev?.distanceM : null;
    final up = _above(index);
    if (up >= 0 && seconds == null && metres == null) {
      final above = sets[up];
      final hint = timedHintFor(up);
      if (distance) {
        metres = above.distanceM ?? hint.metres;
      } else {
        seconds = above.durationSeconds ?? hint.seconds;
      }
    }
    return (seconds: seconds, metres: metres);
  }

  /// Index of the first working set.
  int? get firstWorking {
    final i = sets.indexWhere((s) => !s.setType.isWarmup);
    return i < 0 ? null : i;
  }

  /// Warm-up sets to put before the first working set, ramping up to its
  /// weight (entered or hinted). [barKg] adds the empty bar for a barbell.
  /// Empty when the exercise has warm-ups, has started its working sets, or
  /// has no known working weight.
  List<({double loadKg, int reps})> warmups({required double barKg}) {
    final at = firstWorking;
    final step = stepKg;
    if (at == null ||
        step == null ||
        sets[at].isCompleted ||
        sets.any((s) => s.setType.isWarmup)) {
      return const [];
    }
    switch (type) {
      case TrackingType.weights:
        final work = sets[at].loadKg ?? hintFor(at).load;
        if (work == null) return const [];
        return warmupSets(
          work,
          step: step,
          barKg: exercise.equipment == Equipment.barbell ? barKg : null,
        );
      case TrackingType.bodyweight:
      case TrackingType.duration:
      case TrackingType.distance:
        return const [];
    }
  }

  /// Which working set the set at [index] is, from 0. Null for a warm-up.
  int? roundOf(int index) => sets[index].setType.isWarmup
      ? null
      : sets.take(index).where((s) => !s.setType.isWarmup).length;

  /// The working set of [round], if there is one.
  WorkoutSet? setOfRound(int round) =>
      sets.where((s) => !s.setType.isWarmup).elementAtOrNull(round);

  /// Records by set id: completed working sets that beat [bests] and the sets
  /// above them. [bodyweightKg] is the body weight of this workout.
  Map<int, Set<PrKind>> records(double? bodyweightKg) {
    final before = bests;
    if (before == null) return const {};
    final kinds = liveRecords(before, [
      for (final s in sets)
        s.isCompleted && !s.setType.isWarmup
            ? SetFact(
                workoutId: 0,
                startedAt: DateTime(0),
                exerciseId: exercise.id,
                type: type,
                mode: mode,
                loadKg: s.loadKg,
                reps: s.reps,
                bodyweightKg: bodyweightKg,
                durationSeconds: s.durationSeconds,
                distanceM: s.distanceM,
              )
            : null,
    ]);
    return {
      for (final (i, k) in kinds.indexed)
        if (k.isNotEmpty) sets[i].id: k,
    };
  }

  /// What ✓ stores for the set at [index]: `set` is the set with its empty
  /// fields filled from their hints, not yet marked done. Any result but
  /// [CompleteResult.ok] names the field with nothing to fill in, and `set`
  /// is unchanged. This is the one rule for [WorkoutEditor.toggleDone] and
  /// [WorkoutEditor.markAllDone].
  ///
  /// Reps exercises need reps, and weights a weight too. A time exercise
  /// needs a time and a distance exercise a distance. An extra load that is
  /// left empty counts as none.
  ({CompleteResult result, WorkoutSet set}) completion(int index) {
    final s = sets[index];
    final hint = hintFor(index);
    final timed = timedHintFor(index);
    final reps = s.reps ?? hint.reps;
    final seconds = s.durationSeconds ?? timed.seconds;
    final metres = s.distanceM ?? timed.metres;
    double? load = hasLoad ? (s.loadKg ?? hint.load) : null;
    final missing = switch (type) {
      TrackingType.weights when (reps ?? 0) > 0 && load == null =>
        CompleteResult.needsWeight,
      TrackingType.weights ||
      TrackingType.bodyweight => (reps ?? 0) > 0 ? null : CompleteResult.needsReps,
      TrackingType.duration =>
        (seconds ?? 0) > 0 ? null : CompleteResult.needsTime,
      TrackingType.distance =>
        (metres ?? 0) > 0 ? null : CompleteResult.needsDistance,
    };
    if (missing != null) return (result: missing, set: s);
    if (type != TrackingType.weights && mode != LoadMode.none) load ??= 0;
    return (
      result: CompleteResult.ok,
      set: s.copyWith(
        loadKg: Value(load),
        reps: Value(reps),
        durationSeconds: Value(seconds),
        distanceM: Value(metres),
      ),
    );
  }
}

enum SetField { load, reps, time, distance }

/// Where typing continues once the set at [index] is completed: the next open
/// set, in its load field if that is empty and in reps otherwise. Null after
/// the last set.
({int setId, SetField field})? nextField(DraftExercise ex, int index) {
  if (index >= ex.sets.length || !ex.sets[index].isCompleted) return null;
  for (final s in ex.sets.skip(index + 1)) {
    if (s.isCompleted) continue;
    return (setId: s.id, field: _openField(ex, s));
  }
  return null;
}

SetField _openField(DraftExercise ex, WorkoutSet s) =>
    ex.hasLoad && s.loadKg == null
    ? SetField.load
    : switch (ex.type) {
        TrackingType.duration => SetField.time,
        TrackingType.distance => SetField.distance,
        _ => SetField.reps,
      };

/// [nextField] across a superset: completing a working set moves on to the
/// same round of the other exercises, the ones below first, and then to the
/// next round from the top. Outside a superset, and for warm-ups, this is
/// [nextField].
({int setId, SetField field})? nextFocus(
  WorkoutDraft draft,
  int exerciseId,
  int index,
) {
  final ex = draft.byId(exerciseId);
  if (ex == null || index >= ex.sets.length) return null;
  final members = draft.supersetOf(exerciseId);
  final round = ex.roundOf(index);
  if (members.length < 2 || round == null) return nextField(ex, index);
  if (!ex.sets[index].isCompleted) return null;
  final at = members.indexOf(ex);
  final rounds = members.fold(
    0,
    (n, m) => math.max(n, m.sets.where((s) => !s.setType.isWarmup).length),
  );
  for (var r = round; r < rounds; r++) {
    final order = r == round
        ? [...members.skip(at + 1), ...members.take(at)]
        : members;
    for (final m in order) {
      final s = m.setOfRound(r);
      if (s != null && !s.isCompleted) {
        return (setId: s.id, field: _openField(m, s));
      }
    }
  }
  return null;
}

/// Whether the round of the set at [index] still has an open set in another
/// exercise of its superset. Rest starts once this is false.
bool roundOpen(WorkoutDraft draft, int exerciseId, int index) {
  final ex = draft.byId(exerciseId);
  final round = ex == null || index >= ex.sets.length
      ? null
      : ex.roundOf(index);
  if (round == null) return false;
  return draft
      .supersetOf(exerciseId)
      .any(
        (m) => m.id != exerciseId && m.setOfRound(round)?.isCompleted == false,
      );
}

@immutable
class WorkoutDraft {
  const WorkoutDraft({
    required this.workout,
    required this.exercises,
    this.bodyweightKg,
  });

  final Workout workout;
  final List<DraftExercise> exercises;

  /// Body weight used for past-workout edits.
  final double? bodyweightKg;

  bool get isLive => workout.endedAt == null;

  int get completedSets => exercises.fold(
    0,
    (n, e) => n + e.sets.where((s) => s.isCompleted).length,
  );

  int get totalSets => exercises.fold(0, (n, e) => n + e.sets.length);

  int get uncheckedSets => exercises.fold(
    0,
    (n, e) => n + e.sets.where((s) => !s.isCompleted).length,
  );

  /// Unchecked sets that mark all done can complete.
  int get markableSets {
    var n = 0;
    for (final e in exercises) {
      for (var i = 0; i < e.sets.length; i++) {
        if (!e.sets[i].isCompleted &&
            e.completion(i).result == CompleteResult.ok) {
          n++;
        }
      }
    }
    return n;
  }

  /// The exercise with the most recently completed set, and when that was.
  ({DraftExercise exercise, DateTime at})? get _lastCompleted {
    ({DraftExercise exercise, DateTime at})? last;
    for (final e in exercises) {
      for (final s in e.sets) {
        if (s.completedAt case final at?
            when s.isCompleted && (last == null || at.isAfter(last.at))) {
          last = (exercise: e, at: at);
        }
      }
    }
    return last;
  }

  /// When the last set was completed. Null if none has a time.
  DateTime? get lastSetAt => _lastCompleted?.at;

  /// Rest to start by hand: that of the exercise completed last, else
  /// [fallback].
  int restAfterLast(int fallback) =>
      _lastCompleted?.exercise.restSeconds ?? fallback;

  /// A name from the muscles trained, while the workout still has the default.
  String? get suggestedName {
    if (workout.name != kDefaultWorkoutName) return null;
    final sets = <MuscleGroup, int>{};
    for (final e in exercises) {
      final n = e.sets
          .where((s) => s.isCompleted && !s.setType.isWarmup)
          .length;
      sets.update(e.exercise.muscleGroup, (v) => v + n, ifAbsent: () => n);
    }
    return suggestWorkoutName(sets);
  }

  DraftExercise? byId(int id) {
    for (final e in exercises) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// The exercises linked with [id] in order, itself included. Just itself
  /// when it is not in a superset.
  List<DraftExercise> supersetOf(int id) {
    final i = exercises.indexWhere((e) => e.id == id);
    if (i < 0) return const [];
    final run = supersetRun([for (final e in exercises) e.supersetGroup], i);
    return run == null ? [exercises[i]] : exercises.sublist(run.start, run.end);
  }

  WorkoutDraft copyWith({
    Workout? workout,
    List<DraftExercise>? exercises,
    double? Function()? bodyweightKg,
  }) => WorkoutDraft(
    workout: workout ?? this.workout,
    exercises: exercises ?? this.exercises,
    bodyweightKg: bodyweightKg != null ? bodyweightKg() : this.bodyweightKg,
  );
}

enum CompleteResult { ok, needsReps, needsWeight, needsTime, needsDistance }

/// The time set being timed in the app, if any. It is kept in memory only
/// and has nothing to do with the rest timer.
class SetStopwatch extends Notifier<({int setId, DateTime startedAt})?> {
  @override
  ({int setId, DateTime startedAt})? build() => null;

  /// Starts timing [setId] from [at] (now), dropping a time still running.
  void start(int setId, {DateTime? at}) =>
      state = (setId: setId, startedAt: at ?? DateTime.now());

  /// Stops timing [setId] and returns its whole seconds, at least 1. Null if
  /// it wasn't being timed.
  int? stop(int setId) {
    final s = state;
    if (s == null || s.setId != setId) return null;
    state = null;
    return math.max(1, DateTime.now().difference(s.startedAt).inSeconds);
  }

  /// Drops the running time if it is of one of [setIds].
  void cancel(Iterable<int> setIds) {
    if (setIds.contains(state?.setId)) state = null;
  }
}

final setStopwatchProvider =
    NotifierProvider<SetStopwatch, ({int setId, DateTime startedAt})?>(
      SetStopwatch.new,
    );

class WorkoutEditor extends AsyncNotifier<WorkoutDraft> {
  WorkoutEditor(this.workoutId);
  final int workoutId;

  late WorkoutRepository _repo;
  KeepAliveLink? _keepAlive;
  AppLifecycleListener? _lifecycle;
  Timer? _debounce;
  final Map<int, WorkoutSet> _dirty = {};

  /// A removed set that [undoDelete] can still bring back.
  ({int exerciseId, int index, WorkoutSet set, Completer<void> settled})?
  _pending;

  static const _debounceDelay = Duration(milliseconds: 400);

  @override
  Future<WorkoutDraft> build() async {
    _repo = ref.read(workoutRepoProvider);
    _lifecycle = AppLifecycleListener(onPause: _settle, onHide: _settle);
    ref.onDispose(() {
      _lifecycle?.dispose();
      _debounce?.cancel();
      unawaited(commitDelete());
      unawaited(_writeDirty());
    });

    final loaded = await _repo.load(workoutId);
    if (loaded == null) throw StateError('Workout $workoutId not found');
    final w = loaded.workout;
    final bests = bestsBefore(
      await _repo.setFacts(loaded.exercises.map((e) => e.exercise.id)),
      w.id,
      w.startedAt,
    );
    final exercises = await Future.wait([
      for (final e in loaded.exercises) _toDraft(e, w, bests[e.exercise.id]),
    ]);
    if (w.endedAt == null) _keepAlive = ref.keepAlive();
    ref.listen(
      settingsProvider.select((s) => (s.weightUnit, s.plates)),
      (_, _) => _refreshSteps(),
    );
    return WorkoutDraft(
      workout: w,
      exercises: exercises,
      bodyweightKg: w.bodyweightKg,
    );
  }

  Future<DraftExercise> _toDraft(
    LoadedExercise e,
    Workout w,
    ExerciseBests? bests,
  ) async {
    final previous = await _repo.previousSets(
      e.exercise.id,
      excludeWorkoutId: w.id,
      before: w.startedAt,
    );
    return DraftExercise(
      id: e.row.id,
      exercise: e.exercise,
      sets: e.sets,
      previous: previous,
      bests: bests,
      repsMin: e.row.targetRepsMin,
      repsMax: e.row.targetRepsMax,
      restSeconds: e.row.restSeconds,
      note: e.row.note,
      supersetGroup: e.row.supersetGroup,
      targetWeightKg: e.row.targetWeightKg,
      stepKg: _stepFor(e.exercise),
    );
  }

  double _stepFor(Exercise e) {
    final s = ref.read(settingsProvider);
    return loadStep(
      e.equipment,
      s.weightUnit,
      parsePlates(s.plates, s.weightUnit),
    );
  }

  void _refreshSteps() {
    final d = state.value;
    if (d == null) return;
    state = AsyncData(
      d.copyWith(
        exercises: [
          for (final e in d.exercises)
            e.copyWith(stepKg: () => _stepFor(e.exercise)),
        ],
      ),
    );
  }

  WorkoutDraft get _draft => state.requireValue;

  void _replaceExercise(DraftExercise ex) {
    final d = _draft;
    state = AsyncData(
      d.copyWith(
        exercises: [for (final e in d.exercises) e.id == ex.id ? ex : e],
      ),
    );
  }

  void _replaceSet(int exerciseId, WorkoutSet set) {
    final ex = _draft.byId(exerciseId);
    if (ex == null) return;
    _replaceExercise(
      ex.copyWith(sets: [for (final s in ex.sets) s.id == set.id ? set : s]),
    );
  }

  WorkoutSet? _set(int exerciseId, int setId) {
    final ex = _draft.byId(exerciseId);
    if (ex == null) return null;
    for (final s in ex.sets) {
      if (s.id == setId) return s;
    }
    return null;
  }

  // ------------------------------------------------------------ set edits

  void setLoad(int exerciseId, int setId, double? kg) {
    final s = _set(exerciseId, setId);
    if (s == null || s.loadKg == kg) return;
    _edit(exerciseId, s.copyWith(loadKg: Value(kg)));
  }

  void setReps(int exerciseId, int setId, int? reps) {
    final s = _set(exerciseId, setId);
    if (s == null || s.reps == reps) return;
    _edit(exerciseId, s.copyWith(reps: Value(reps)));
  }

  void setDuration(int exerciseId, int setId, int? seconds) {
    final s = _set(exerciseId, setId);
    if (s == null || s.durationSeconds == seconds) return;
    _edit(exerciseId, s.copyWith(durationSeconds: Value(seconds)));
  }

  void setDistance(int exerciseId, int setId, double? metres) {
    final s = _set(exerciseId, setId);
    if (s == null || s.distanceM == metres) return;
    _edit(exerciseId, s.copyWith(distanceM: Value(metres)));
  }

  void _edit(int exerciseId, WorkoutSet updated) {
    _replaceSet(exerciseId, updated);
    _dirty[updated.id] = updated;
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, flush);
  }

  /// [rpe] is RPE 1–10 in 0.5 steps, also when it is entered as RIR.
  void setRpe(int exerciseId, int setId, double? rpe) {
    final s = _set(exerciseId, setId);
    if (s == null || s.rpe == rpe) return;
    _edit(exerciseId, s.copyWith(rpe: Value(rpe)));
  }

  void setType(int exerciseId, int setId, SetType type) {
    final s = _set(exerciseId, setId);
    if (s == null || s.setType == type) return;
    _edit(exerciseId, s.copyWith(setType: type));
    flush();
  }

  void setNote(int exerciseId, int setId, String? note) {
    final s = _set(exerciseId, setId);
    final n = note?.trim();
    if (s == null) return;
    _edit(
      exerciseId,
      s.copyWith(note: Value(n == null || n.isEmpty ? null : n)),
    );
    flush();
  }

  /// Toggles completion. When completing, empty fields take their hints as
  /// [DraftExercise.completion] says.
  CompleteResult toggleDone(int exerciseId, int setId) {
    final ex = _draft.byId(exerciseId);
    final s = _set(exerciseId, setId);
    if (ex == null || s == null) return CompleteResult.ok;

    if (s.isCompleted) {
      final u = s.copyWith(isCompleted: false, completedAt: const Value(null));
      _replaceSet(exerciseId, u);
      _dirty[u.id] = u;
      flush();
      return CompleteResult.ok;
    }

    final index = ex.sets.indexOf(s);
    final c = ex.completion(index);
    if (c.result != CompleteResult.ok) return c.result;
    final u = c.set.copyWith(
      isCompleted: true,
      completedAt: Value(DateTime.now()),
    );
    _replaceSet(exerciseId, u);
    _dirty[u.id] = u;
    flush();

    // In a superset, rest waits for the last exercise of the round.
    final settings = ref.read(settingsProvider);
    if (_draft.isLive &&
        settings.autoStartRest &&
        !roundOpen(_draft, exerciseId, index)) {
      ref
          .read(restTimerProvider.notifier)
          .start(ex.restSeconds ?? settings.defaultRestSeconds);
    }
    return CompleteResult.ok;
  }

  Future<void> addSet(int exerciseId) async {
    final ex = _draft.byId(exerciseId);
    if (ex == null) return;
    final created = await _repo.addSet(exerciseId, position: ex.sets.length);
    if (!ref.mounted) return;
    final latest = _draft.byId(exerciseId);
    if (latest == null) return;
    _replaceExercise(latest.copyWith(sets: [...latest.sets, created]));
  }

  /// Puts the warm-up ramp of [DraftExercise.warmups] before the first working
  /// set, filled in but not completed.
  Future<void> addWarmups(int exerciseId) async {
    final ex = _draft.byId(exerciseId);
    final at = ex?.firstWorking;
    if (ex == null || at == null) return;
    final s = ref.read(settingsProvider);
    final plan = ex.warmups(barKg: barWeightKg(s.barWeightKg, s.weightUnit));
    final created = [
      for (final (i, p) in plan.indexed)
        await _repo.addSet(
          exerciseId,
          position: at + i,
          loadKg: p.loadKg,
          reps: p.reps,
          setType: SetType.warmup,
        ),
    ];
    if (created.isEmpty || !ref.mounted) return;
    final latest = _draft.byId(exerciseId);
    if (latest == null) return;
    final sets = [...latest.sets]
      ..insertAll(latest.firstWorking ?? latest.sets.length, created);
    _replaceExercise(latest.copyWith(sets: _renumber(sets)));
    flush();
  }

  /// Hides a set right away but keeps it for [undoDelete] until
  /// [commitDelete] writes the delete. Only one delete is pending at a time.
  /// The future completes once it is committed or undone.
  Future<void> removeSet(int exerciseId, int setId) {
    final ex = _draft.byId(exerciseId);
    final index = ex?.sets.indexWhere((s) => s.id == setId) ?? -1;
    if (ex == null || index < 0) return Future.value();
    unawaited(commitDelete());
    ref.read(setStopwatchProvider.notifier).cancel([setId]);
    final p = (
      exerciseId: exerciseId,
      index: index,
      set: ex.sets[index],
      settled: Completer<void>(),
    );
    _pending = p;
    _replaceExercise(
      ex.copyWith(sets: _renumber([...ex.sets]..removeAt(index))),
    );
    flush();
    return p.settled.future;
  }

  /// Puts the pending set back where it was. Returns false if there is none.
  bool undoDelete() {
    final p = _pending;
    if (p == null) return false;
    _pending = null;
    p.settled.complete();
    final ex = _draft.byId(p.exerciseId);
    if (ex == null) return false;
    final sets = [...ex.sets]..insert(p.index.clamp(0, ex.sets.length), p.set);
    _replaceExercise(ex.copyWith(sets: _renumber(sets)));
    flush();
    return true;
  }

  /// Writes the pending delete. With [setId], only if it is that set.
  Future<void> commitDelete([int? setId]) async {
    final p = _pending;
    if (p == null || (setId != null && p.set.id != setId)) return;
    _pending = null;
    _dirty.remove(p.set.id);
    await _repo.deleteSet(p.set.id);
    p.settled.complete();
  }

  /// Makes positions match the list order and marks moved sets for writing.
  List<WorkoutSet> _renumber(List<WorkoutSet> sets) => [
    for (final (i, s) in sets.indexed)
      s.position == i ? s : _dirty[s.id] = s.copyWith(position: i),
  ];

  // ------------------------------------------------------------ exercises

  Future<void> addExercises(List<Exercise> list) async {
    for (final e in list) {
      final w = _draft.workout;
      final previous = await _repo.previousSets(
        e.id,
        excludeWorkoutId: w.id,
        before: w.startedAt,
      );
      final bests = bestsBefore(
        await _repo.setFacts([e.id]),
        w.id,
        w.startedAt,
      );
      final count = previous.isEmpty ? 3 : previous.length.clamp(1, 10);
      final (row, sets) = await _repo.addExercise(
        w.id,
        e.id,
        position: _draft.exercises.length,
        sets: count,
      );
      if (!ref.mounted) return;
      state = AsyncData(
        _draft.copyWith(
          exercises: [
            ..._draft.exercises,
            DraftExercise(
              id: row.id,
              exercise: e,
              sets: sets,
              previous: previous,
              bests: bests[e.id],
              stepKg: _stepFor(e),
            ),
          ],
        ),
      );
    }
  }

  /// Swaps the exercise of a card and keeps its place, superset, note, rest
  /// and sets. Hints, previous sets and bests come from [e]. Loads carry over
  /// when both exercises track load the same way. Otherwise they are cleared
  /// along with what [e] doesn't record (reps, time or distance), and a
  /// completed set that now lacks what [e] needs is reopened.
  /// Returns whether loads were cleared.
  Future<bool> replaceExercise(int exerciseId, Exercise e) async {
    await commitDelete();
    final w = _draft.workout;
    if (_draft.byId(exerciseId)?.exercise.id == e.id) return false;
    final previous = await _repo.previousSets(
      e.id,
      excludeWorkoutId: w.id,
      before: w.startedAt,
    );
    final bests = bestsBefore(await _repo.setFacts([e.id]), w.id, w.startedAt);
    await _repo.updateExercise(
      exerciseId,
      WorkoutExercisesCompanion(
        exerciseId: Value(e.id),
        targetWeightKg: const Value(null),
      ),
    );
    if (!ref.mounted) return false;
    final old = _draft.byId(exerciseId);
    if (old == null) return false;
    final weights = e.trackingType == TrackingType.weights;
    final same =
        old.type == e.trackingType && (weights || old.mode == e.loadMode);
    var changed = false;
    WorkoutSet cleared(WorkoutSet s) {
      final type = e.trackingType;
      final reps = type.hasReps ? s.reps : null;
      final seconds = type.hasReps ? null : s.durationSeconds;
      final metres = type == TrackingType.distance ? s.distanceM : null;
      final done =
          s.isCompleted &&
          switch (type) {
            TrackingType.weights => false,
            TrackingType.bodyweight => (reps ?? 0) > 0,
            TrackingType.duration => (seconds ?? 0) > 0,
            TrackingType.distance => (metres ?? 0) > 0,
          };
      final load = done && e.loadMode != LoadMode.none ? 0.0 : null;
      final u = s.copyWith(
        loadKg: Value(load),
        reps: Value(reps),
        durationSeconds: Value(seconds),
        distanceM: Value(metres),
        isCompleted: done,
        completedAt: Value(done ? s.completedAt : null),
      );
      if (u == s) return s;
      changed = changed || s.loadKg != load;
      return _dirty[s.id] = u;
    }

    _replaceExercise(
      old.copyWith(
        exercise: e,
        sets: same ? null : [for (final s in old.sets) cleared(s)],
        previous: previous,
        bests: () => bests[e.id],
        targetWeightKg: () => null,
        stepKg: () => _stepFor(e),
      ),
    );
    flush();
    return changed;
  }

  Future<void> removeExercise(int exerciseId) async {
    final ex = _draft.byId(exerciseId);
    if (ex == null) return;
    for (final s in ex.sets) {
      _dirty.remove(s.id);
    }
    state = AsyncData(
      _draft.copyWith(
        exercises: [
          for (final e in _draft.exercises)
            if (e.id != exerciseId) e,
        ],
      ),
    );
    await _repo.removeExercise(exerciseId);
    // Its superset partner may be on its own now.
    if (ref.mounted) await _arrange(_draft.exercises);
  }

  /// Supersets stay together, see [moveGrouped].
  Future<void> reorder(int oldIndex, int newIndex) => _arrange(
    moveGrouped(_draft.exercises, oldIndex, newIndex, (e) => e.supersetGroup),
  );

  /// Links an exercise with the one below it into a superset, or adds it to
  /// the superset that one is in.
  Future<void> linkWithNext(int exerciseId) {
    final list = _draft.exercises;
    final groups = linkGroups([
      for (final e in list) e.supersetGroup,
    ], list.indexWhere((e) => e.id == exerciseId));
    return _arrange([
      for (final (i, e) in list.indexed)
        e.copyWith(supersetGroup: () => groups[i]),
    ]);
  }

  /// Takes an exercise out of its superset. From the middle it moves below
  /// the superset, so the others stay linked.
  Future<void> unlink(int exerciseId) {
    final list = [..._draft.exercises];
    final i = list.indexWhere((e) => e.id == exerciseId);
    if (i < 0) return Future.value();
    final run = supersetRun([for (final e in list) e.supersetGroup], i);
    final item = list.removeAt(i).copyWith(supersetGroup: () => null);
    list.insert(run == null || i == run.start ? i : run.end - 1, item);
    return _arrange(list);
  }

  /// Shows [list] and writes its order and superset groups, without the
  /// groups that link nothing.
  Future<void> _arrange(List<DraftExercise> list) async {
    final before = {for (final e in _draft.exercises) e.id: e.supersetGroup};
    final groups = dropLoneGroups([for (final e in list) e.supersetGroup]);
    final next = [
      for (final (i, e) in list.indexed)
        e.supersetGroup == groups[i]
            ? e
            : e.copyWith(supersetGroup: () => groups[i]),
    ];
    state = AsyncData(_draft.copyWith(exercises: next));
    for (final e in next) {
      if (before[e.id] == e.supersetGroup) continue;
      await _repo.updateExercise(
        e.id,
        WorkoutExercisesCompanion(supersetGroup: Value(e.supersetGroup)),
      );
    }
    await _repo.reorderExercises([for (final e in next) e.id]);
  }

  void setExerciseNote(int exerciseId, String? note) {
    final ex = _draft.byId(exerciseId);
    final n = note?.trim();
    final value = n == null || n.isEmpty ? null : n;
    if (ex == null || ex.note == value) return;
    _replaceExercise(ex.copyWith(note: () => value));
    unawaited(
      _repo.updateExercise(
        exerciseId,
        WorkoutExercisesCompanion(note: Value(value)),
      ),
    );
  }

  /// Rest after a set of this exercise in this workout. Null goes back to the
  /// default from settings.
  void setRest(int exerciseId, int? seconds) {
    final ex = _draft.byId(exerciseId);
    if (ex == null || ex.restSeconds == seconds) return;
    _replaceExercise(ex.copyWith(restSeconds: () => seconds));
    unawaited(
      _repo.updateExercise(
        exerciseId,
        WorkoutExercisesCompanion(restSeconds: Value(seconds)),
      ),
    );
  }

  /// Keeps exercise settings (e.g. load mode) in sync after editing.
  void refreshExercise(Exercise e) {
    final d = _draft;
    state = AsyncData(
      d.copyWith(
        exercises: [
          for (final x in d.exercises)
            x.exercise.id == e.id
                ? x.copyWith(exercise: e, stepKg: () => _stepFor(e))
                : x,
        ],
      ),
    );
  }

  Future<void> rename(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    state = AsyncData(
      _draft.copyWith(workout: _draft.workout.copyWith(name: n)),
    );
    await _repo.rename(workoutId, n);
  }

  Future<void> setWorkoutNote(String? note) async {
    final n = note?.trim();
    final value = n == null || n.isEmpty ? null : n;
    state = AsyncData(
      _draft.copyWith(workout: _draft.workout.copyWith(note: Value(value))),
    );
    await _repo.setNote(workoutId, value);
  }

  /// Moves a past workout in time. Callers check the pair first.
  Future<void> setTimes(DateTime start, DateTime end) async {
    state = AsyncData(
      _draft.copyWith(
        workout: _draft.workout.copyWith(startedAt: start, endedAt: Value(end)),
      ),
    );
    await _repo.setTimes(workoutId, start, end);
  }

  void setBodyweight(double? kg) {
    state = AsyncData(_draft.copyWith(bodyweightKg: () => kg));
  }

  // ------------------------------------------------------------ persistence

  void flush() {
    _debounce?.cancel();
    unawaited(_writeDirty());
  }

  /// Leaving the app: a delete can't wait for its snackbar any longer.
  void _settle() {
    unawaited(commitDelete());
    flush();
  }

  Future<void> _writeDirty() async {
    if (_dirty.isEmpty) return;
    final batch = _dirty.values.toList();
    _dirty.clear();
    await _repo.writeSets(batch);
  }

  /// Starts or restarts rest by hand with the time of the exercise completed
  /// last, else the default.
  void startRest() {
    if (!_draft.isLive) return;
    final fallback = ref.read(settingsProvider).defaultRestSeconds;
    ref.read(restTimerProvider.notifier).start(_draft.restAfterLast(fallback));
  }

  /// Completes every unchecked set the way ✓ does, filling empty fields from
  /// hints. Sets with nothing to use for a field they need stay unchecked and
  /// are counted in `skipped`. Marked sets get no time, and no rest starts.
  ({int marked, int skipped}) markAllDone() {
    var marked = 0;
    var skipped = 0;
    for (final id in [for (final e in _draft.exercises) e.id]) {
      for (var i = 0; i < _draft.byId(id)!.sets.length; i++) {
        final ex = _draft.byId(id)!;
        final s = ex.sets[i];
        if (s.isCompleted) continue;
        final c = ex.completion(i);
        if (c.result != CompleteResult.ok) {
          skipped++;
          continue;
        }
        final u = c.set.copyWith(isCompleted: true);
        _replaceSet(id, u);
        _dirty[u.id] = u;
        marked++;
      }
    }
    flush();
    return (marked: marked, skipped: skipped);
  }

  /// Finishes a live workout or saves edits of a past one. A live one ends at
  /// [endedAt] instead of now, and a default name becomes
  /// [WorkoutDraft.suggestedName].
  /// Returns false if nothing was logged (the workout is removed).
  Future<bool> finish({DateTime? endedAt}) async {
    _debounce?.cancel();
    _cancelStopwatch();
    await commitDelete();
    await _writeDirty();
    final d = _draft;
    final bodyweight = d.isLive
        ? ref.read(settingsProvider).bodyweightKg
        : d.bodyweightKg;
    final saved = await _repo.finish(
      workoutId,
      bodyweightKg: bodyweight,
      keepEndedAt: !d.isLive,
      endedAt: d.isLive ? endedAt : null,
      name: d.isLive ? d.suggestedName : null,
    );
    if (d.isLive) ref.read(restTimerProvider.notifier).skip();
    _release();
    return saved;
  }

  Future<void> discard() async {
    _debounce?.cancel();
    _cancelStopwatch();
    await commitDelete();
    _dirty.clear();
    final live = state.value?.isLive ?? true;
    await _repo.discard(workoutId);
    // Dropping a past workout must not stop the live workout’s rest timer.
    if (live) ref.read(restTimerProvider.notifier).skip();
    _release();
  }

  /// A set still being timed in this workout is not stored.
  void _cancelStopwatch() => ref.read(setStopwatchProvider.notifier).cancel([
    for (final e in state.value?.exercises ?? const <DraftExercise>[])
      for (final s in e.sets) s.id,
  ]);

  void _release() {
    _keepAlive?.close();
    _keepAlive = null;
  }
}

final workoutEditorProvider = AsyncNotifierProvider.autoDispose
    .family<WorkoutEditor, WorkoutDraft, int>(WorkoutEditor.new);
