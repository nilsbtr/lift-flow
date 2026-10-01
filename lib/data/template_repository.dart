import 'package:drift/drift.dart';

import 'database.dart';

class TemplateItem {
  const TemplateItem({
    required this.exercise,
    required this.targetSets,
    this.repsMin,
    this.repsMax,
  });

  final Exercise exercise;
  final int targetSets;
  final int? repsMin;
  final int? repsMax;

  TemplateItem copyWith({
    int? targetSets,
    int? Function()? repsMin,
    int? Function()? repsMax,
  }) => TemplateItem(
    exercise: exercise,
    targetSets: targetSets ?? this.targetSets,
    repsMin: repsMin != null ? repsMin() : this.repsMin,
    repsMax: repsMax != null ? repsMax() : this.repsMax,
  );
}

class TemplateDetail {
  const TemplateDetail(this.template, this.items);
  final WorkoutTemplate template;
  final List<TemplateItem> items;
}

class TemplateRepository {
  TemplateRepository(this._db);
  final AppDatabase _db;

  /// All templates with their items, ordered by position.
  Stream<List<TemplateDetail>> watchAll() {
    final t = _db.workoutTemplates;
    final te = _db.templateExercises;
    final e = _db.exercises;
    final q =
        _db.select(t).join([
          leftOuterJoin(te, te.templateId.equalsExp(t.id)),
          leftOuterJoin(e, e.id.equalsExp(te.exerciseId)),
        ])..orderBy([
          OrderingTerm.asc(t.position),
          OrderingTerm.asc(t.id),
          OrderingTerm.asc(te.position),
        ]);
    return q.watch().map((rows) {
      final byId = <int, (WorkoutTemplate, List<TemplateItem>)>{};
      for (final r in rows) {
        final tpl = r.readTable(t);
        final entry = byId.putIfAbsent(tpl.id, () => (tpl, <TemplateItem>[]));
        final row = r.readTableOrNull(te);
        final ex = r.readTableOrNull(e);
        if (row != null && ex != null) {
          entry.$2.add(
            TemplateItem(
              exercise: ex,
              targetSets: row.targetSets,
              repsMin: row.repsMin,
              repsMax: row.repsMax,
            ),
          );
        }
      }
      return [for (final v in byId.values) TemplateDetail(v.$1, v.$2)];
    });
  }

  Future<TemplateDetail?> get(int id) async {
    final tpl = await (_db.select(
      _db.workoutTemplates,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (tpl == null) return null;
    final te = _db.templateExercises;
    final e = _db.exercises;
    final rows =
        await (_db.select(te).join([
                innerJoin(e, e.id.equalsExp(te.exerciseId)),
              ])
              ..where(te.templateId.equals(id))
              ..orderBy([OrderingTerm.asc(te.position)]))
            .get();
    return TemplateDetail(tpl, [
      for (final r in rows)
        TemplateItem(
          exercise: r.readTable(e),
          targetSets: r.readTable(te).targetSets,
          repsMin: r.readTable(te).repsMin,
          repsMax: r.readTable(te).repsMax,
        ),
    ]);
  }

  /// Creates or replaces a template. Returns its id.
  Future<int> save({
    int? id,
    required String name,
    required List<TemplateItem> items,
  }) => _db.transaction(() async {
    final n = name.trim();
    var tid = id;
    if (tid == null) {
      final maxPos = _db.workoutTemplates.position.max();
      final row = await (_db.selectOnly(
        _db.workoutTemplates,
      )..addColumns([maxPos])).getSingle();
      tid = await _db
          .into(_db.workoutTemplates)
          .insert(
            WorkoutTemplatesCompanion.insert(
              name: n,
              position: Value((row.read(maxPos) ?? -1) + 1),
            ),
          );
    } else {
      await (_db.update(_db.workoutTemplates)..where((t) => t.id.equals(tid!)))
          .write(WorkoutTemplatesCompanion(name: Value(n)));
      await (_db.delete(
        _db.templateExercises,
      )..where((t) => t.templateId.equals(tid!))).go();
    }
    await _db.batch((b) {
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        b.insert(
          _db.templateExercises,
          TemplateExercisesCompanion.insert(
            templateId: tid!,
            exerciseId: it.exercise.id,
            position: i,
            targetSets: Value(it.targetSets.clamp(1, 10)),
            repsMin: Value(it.repsMin),
            repsMax: Value(it.repsMax),
          ),
        );
      }
    });
    return tid;
  });

  Future<void> delete(int id) =>
      (_db.delete(_db.workoutTemplates)..where((t) => t.id.equals(id))).go();

  Future<void> reorder(List<int> orderedIds) => _db.batch((b) {
    for (var i = 0; i < orderedIds.length; i++) {
      b.update(
        _db.workoutTemplates,
        WorkoutTemplatesCompanion(position: Value(i)),
        where: (t) => t.id.equals(orderedIds[i]),
      );
    }
  });

  /// Builds template items from a finished workout's structure.
  Future<List<TemplateItem>> itemsFromWorkout(int workoutId) async {
    final we = _db.workoutExercises;
    final e = _db.exercises;
    final rows =
        await (_db.select(we).join([
                innerJoin(e, e.id.equalsExp(we.exerciseId)),
              ])
              ..where(we.workoutId.equals(workoutId))
              ..orderBy([OrderingTerm.asc(we.position)]))
            .get();
    final items = <TemplateItem>[];
    for (final r in rows) {
      final w = r.readTable(we);
      final sets = await (_db.select(
        _db.workoutSets,
      )..where((s) => s.workoutExerciseId.equals(w.id))).get();
      int? min = w.targetRepsMin;
      int? max = w.targetRepsMax;
      if (min == null) {
        final reps = [
          for (final s in sets)
            if (!s.isWarmup) ?s.reps,
        ]..sort();
        if (reps.isNotEmpty) {
          min = reps.first;
          max = reps.last == reps.first ? null : reps.last;
        }
      }
      items.add(
        TemplateItem(
          exercise: r.readTable(e),
          targetSets: sets.isEmpty ? 3 : sets.length.clamp(1, 10),
          repsMin: min,
          repsMax: max,
        ),
      );
    }
    return items;
  }
}
