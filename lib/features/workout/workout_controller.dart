import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../../data/database.dart';
import '../../data/workout_repository.dart';
import '../../providers.dart';

@immutable
class DraftExercise {
  const DraftExercise({
    required this.id,
    required this.exercise,
    required this.sets,
    required this.previous,
    this.repsMin,
    this.repsMax,
  });

  /// WorkoutExercise id.
  final int id;
  final Exercise exercise;
  final List<WorkoutSet> sets;

  /// Completed sets of the last session of this exercise.
  final List<WorkoutSet> previous;
  final int? repsMin;
  final int? repsMax;

  DraftExercise copyWith({List<WorkoutSet>? sets, Exercise? exercise}) =>
      DraftExercise(
        id: id,
        exercise: exercise ?? this.exercise,
        sets: sets ?? this.sets,
        previous: previous,
        repsMin: repsMin,
        repsMax: repsMax,
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

  /// Placeholder values for a set: previous session → set above → target.
  ({double? load, int? reps}) hintFor(int index) {
    final prev = index < previous.length ? previous[index] : null;
    double? load;
    int? reps;
    if (prev != null) {
      if (_fits(prev.loadKg)) load = prev.loadKg;
      reps = prev.reps;
    }
    if (index > 0 && (load == null || reps == null)) {
      final above = sets[index - 1];
      final aboveHint = hintFor(index - 1);
      if (hasLoad && load == null) {
        final l = above.loadKg ?? aboveHint.load;
        if (_fits(l)) load = l;
      }
      reps ??= above.reps ?? aboveHint.reps;
    }
    reps ??= repsMin;
    return (load: hasLoad ? load : null, reps: reps);
  }
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

  DraftExercise? byId(int id) {
    for (final e in exercises) {
      if (e.id == id) return e;
    }
    return null;
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

enum CompleteResult { ok, needsReps, needsWeight }

class WorkoutEditor extends AsyncNotifier<WorkoutDraft> {
  WorkoutEditor(this.workoutId);
  final int workoutId;

  late WorkoutRepository _repo;
  KeepAliveLink? _keepAlive;
  AppLifecycleListener? _lifecycle;
  Timer? _debounce;
  final Map<int, WorkoutSet> _dirty = {};

  static const _debounceDelay = Duration(milliseconds: 400);

  @override
  Future<WorkoutDraft> build() async {
    _repo = ref.read(workoutRepoProvider);
    _lifecycle = AppLifecycleListener(onPause: flush, onHide: flush);
    ref.onDispose(() {
      _lifecycle?.dispose();
      _debounce?.cancel();
      unawaited(_writeDirty());
    });

    final loaded = await _repo.load(workoutId);
    if (loaded == null) throw StateError('Workout $workoutId not found');
    final w = loaded.workout;
    final exercises = await Future.wait([
      for (final e in loaded.exercises) _toDraft(e, w),
    ]);
    if (w.endedAt == null) _keepAlive = ref.keepAlive();
    return WorkoutDraft(
      workout: w,
      exercises: exercises,
      bodyweightKg: w.bodyweightKg,
    );
  }

  Future<DraftExercise> _toDraft(LoadedExercise e, Workout w) async {
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
      repsMin: e.row.targetRepsMin,
      repsMax: e.row.targetRepsMax,
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

  void _edit(int exerciseId, WorkoutSet updated) {
    _replaceSet(exerciseId, updated);
    _dirty[updated.id] = updated;
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, flush);
  }

  void toggleWarmup(int exerciseId, int setId) {
    final s = _set(exerciseId, setId);
    if (s == null) return;
    final u = s.copyWith(isWarmup: !s.isWarmup);
    _replaceSet(exerciseId, u);
    _dirty[u.id] = u;
    flush();
  }

  /// Toggles completion. When completing, empty fields take their hints.
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
    final hint = ex.hintFor(index);
    final reps = s.reps ?? hint.reps;
    double? load = ex.hasLoad ? (s.loadKg ?? hint.load) : null;
    if (reps == null || reps <= 0) return CompleteResult.needsReps;
    if (ex.type == TrackingType.weights && load == null) {
      return CompleteResult.needsWeight;
    }
    if (ex.type == TrackingType.bodyweight && ex.mode != LoadMode.none) {
      load ??= 0;
    }
    final u = s.copyWith(
      loadKg: Value(load),
      reps: Value(reps),
      isCompleted: true,
      completedAt: Value(DateTime.now()),
    );
    _replaceSet(exerciseId, u);
    _dirty[u.id] = u;
    flush();

    final settings = ref.read(settingsProvider);
    if (_draft.isLive && settings.autoStartRest) {
      ref.read(restTimerProvider.notifier).start(settings.defaultRestSeconds);
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

  Future<void> removeSet(int exerciseId, int setId) async {
    final ex = _draft.byId(exerciseId);
    if (ex == null) return;
    _dirty.remove(setId);
    final remaining = [
      for (final s in ex.sets)
        if (s.id != setId) s,
    ];
    final renumbered = [
      for (var i = 0; i < remaining.length; i++)
        remaining[i].position == i
            ? remaining[i]
            : remaining[i].copyWith(position: i),
    ];
    _replaceExercise(ex.copyWith(sets: renumbered));
    await _repo.deleteSet(setId);
    for (final s in renumbered) {
      if (!remaining.contains(s)) _dirty[s.id] = s;
    }
    flush();
  }

  // ------------------------------------------------------------ exercises

  Future<void> addExercises(List<Exercise> list) async {
    for (final e in list) {
      final w = _draft.workout;
      final previous = await _repo.previousSets(
        e.id,
        excludeWorkoutId: w.id,
        before: w.startedAt,
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
            ),
          ],
        ),
      );
    }
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
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = [..._draft.exercises];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
    state = AsyncData(_draft.copyWith(exercises: list));
    await _repo.reorderExercises([for (final e in list) e.id]);
  }

  /// Keeps exercise settings (e.g. load mode) in sync after editing.
  void refreshExercise(Exercise e) {
    final d = _draft;
    state = AsyncData(
      d.copyWith(
        exercises: [
          for (final x in d.exercises)
            x.exercise.id == e.id ? x.copyWith(exercise: e) : x,
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

  void setBodyweight(double? kg) {
    state = AsyncData(_draft.copyWith(bodyweightKg: () => kg));
  }

  // ------------------------------------------------------------ persistence

  void flush() {
    _debounce?.cancel();
    unawaited(_writeDirty());
  }

  Future<void> _writeDirty() async {
    if (_dirty.isEmpty) return;
    final batch = _dirty.values.toList();
    _dirty.clear();
    await _repo.writeSets(batch);
  }

  /// Finishes a live workout or saves edits of a past one.
  /// Returns false if nothing was logged (the workout is removed).
  Future<bool> finish() async {
    _debounce?.cancel();
    await _writeDirty();
    final d = _draft;
    final bodyweight = d.isLive
        ? ref.read(settingsProvider).bodyweightKg
        : d.bodyweightKg;
    final saved = await _repo.finish(
      workoutId,
      bodyweightKg: bodyweight,
      keepEndedAt: !d.isLive,
    );
    if (d.isLive) ref.read(restTimerProvider.notifier).skip();
    _release();
    return saved;
  }

  Future<void> discard() async {
    _debounce?.cancel();
    _dirty.clear();
    await _repo.discard(workoutId);
    ref.read(restTimerProvider.notifier).skip();
    _release();
  }

  void _release() {
    _keepAlive?.close();
    _keepAlive = null;
  }
}

final workoutEditorProvider = AsyncNotifierProvider.autoDispose
    .family<WorkoutEditor, WorkoutDraft, int>(WorkoutEditor.new);
