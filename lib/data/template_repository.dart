import 'package:drift/drift.dart';

import '../domain/supersets.dart';
import 'database.dart';

class TemplateItem {
  const TemplateItem({
    required this.exercise,
    required this.targetSets,
    this.repsMin,
    this.repsMax,
    this.restSeconds,
    this.targetWeightKg,
    this.supersetGroup,
  });

  TemplateItem.fromRow(TemplateExercise row, this.exercise)
    : targetSets = row.targetSets,
      repsMin = row.repsMin,
      repsMax = row.repsMax,
      restSeconds = row.restSeconds,
      targetWeightKg = row.targetWeightKg,
      supersetGroup = row.supersetGroup;

  final Exercise exercise;
  final int targetSets;
  final int? repsMin;
  final int? repsMax;

  /// Null uses the default rest from settings.
  final int? restSeconds;
  final double? targetWeightKg;

  /// Items of one template sharing a value form a superset.
  final int? supersetGroup;

  TemplateItem copyWith({
    int? targetSets,
    int? Function()? repsMin,
    int? Function()? repsMax,
    int? Function()? restSeconds,
    double? Function()? targetWeightKg,
    int? Function()? supersetGroup,
  }) => TemplateItem(
    exercise: exercise,
    targetSets: targetSets ?? this.targetSets,
    repsMin: repsMin != null ? repsMin() : this.repsMin,
    repsMax: repsMax != null ? repsMax() : this.repsMax,
    restSeconds: restSeconds != null ? restSeconds() : this.restSeconds,
    targetWeightKg: targetWeightKg != null
        ? targetWeightKg()
        : this.targetWeightKg,
    supersetGroup: supersetGroup != null ? supersetGroup() : this.supersetGroup,
  );
}

class TemplateDetail {
  const TemplateDetail(this.template, this.items);
  final WorkoutTemplate template;
  final List<TemplateItem> items;
}

/// [items] with superset groups cleaned up: a group left with one member is
/// dropped, groups are made of neighbors and numbered 1, 2, …
List<TemplateItem> normalizedSupersets(List<TemplateItem> items) {
  final groups = normalizeGroups([for (final i in items) i.supersetGroup]);
  return [
    for (var i = 0; i < items.length; i++)
      if (items[i].supersetGroup == groups[i])
        items[i]
      else
        items[i].copyWith(supersetGroup: () => groups[i]),
  ];
}

/// Name for a copy of [name]: "Push copy", then "Push copy 2" and so on,
/// cut so it fits [maxLength] and is not in [taken] (ignoring case).
String duplicateName(
  String name,
  Iterable<String> taken, {
  int maxLength = 60,
}) {
  final used = {for (final n in taken) n.toLowerCase()};
  final stripped = name.replaceFirst(RegExp(r' copy( \d+)?$'), '');
  final base = stripped.isEmpty ? name : stripped;
  String fit(String suffix) {
    final room = maxLength - suffix.length;
    final b = base.length > room ? base.substring(0, room).trimRight() : base;
    return '$b$suffix';
  }

  var candidate = fit(' copy');
  for (var n = 2; used.contains(candidate.toLowerCase()); n++) {
    candidate = fit(' copy $n');
  }
  return candidate;
}

class TemplateRepository {
  TemplateRepository(this._db);
  final AppDatabase _db;

  $TemplateFoldersTable get _f => _db.templateFolders;

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
          entry.$2.add(TemplateItem.fromRow(row, ex));
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
        TemplateItem.fromRow(r.readTable(te), r.readTable(e)),
    ]);
  }

  /// Creates or replaces a template. Returns its id. [folderId] only applies
  /// to a new template; use [moveToFolder] for an existing one.
  Future<int> save({
    int? id,
    required String name,
    required List<TemplateItem> items,
    int? folderId,
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
              folderId: Value(folderId),
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
            restSeconds: Value(it.restSeconds),
            targetWeightKg: Value(it.targetWeightKg),
            supersetGroup: Value(it.supersetGroup),
          ),
        );
      }
    });
    return tid;
  });

  /// Copies a template with everything on it, into the same folder and right
  /// after the original. Returns the copy's id, or null if [id] is gone.
  Future<int?> duplicate(int id) => _db.transaction(() async {
    final d = await get(id);
    if (d == null) return null;
    final all =
        await (_db.select(_db.workoutTemplates)..orderBy([
              (t) => OrderingTerm.asc(t.position),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    final copy = await save(
      name: duplicateName(d.template.name, [for (final t in all) t.name]),
      items: d.items,
      folderId: d.template.folderId,
    );
    final order = [for (final t in all) t.id]
      ..insert(all.indexWhere((t) => t.id == id) + 1, copy);
    await reorder(order);
    return copy;
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

  /// Moves a template into a folder, or out of any folder with null.
  Future<void> moveToFolder(int templateId, int? folderId) =>
      (_db.update(_db.workoutTemplates)..where((t) => t.id.equals(templateId)))
          .write(WorkoutTemplatesCompanion(folderId: Value(folderId)));

  // ---------------------------------------------------------------- folders

  Stream<List<TemplateFolder>> watchFolders() =>
      (_db.select(_f)..orderBy([
            (f) => OrderingTerm.asc(f.position),
            (f) => OrderingTerm.asc(f.id),
          ]))
          .watch();

  /// Adds a folder after the existing ones. Returns its id.
  Future<int> createFolder(String name) => _db.transaction(() async {
    final maxPos = _f.position.max();
    final row = await (_db.selectOnly(_f)..addColumns([maxPos])).getSingle();
    return _db
        .into(_f)
        .insert(
          TemplateFoldersCompanion.insert(
            name: name.trim(),
            position: Value((row.read(maxPos) ?? -1) + 1),
          ),
        );
  });

  Future<void> renameFolder(int id, String name) =>
      (_db.update(_f)..where((f) => f.id.equals(id))).write(
        TemplateFoldersCompanion(name: Value(name.trim())),
      );

  /// Deletes a folder. Its templates are kept and leave the folder.
  Future<void> deleteFolder(int id) =>
      (_db.delete(_f)..where((f) => f.id.equals(id))).go();

  Future<void> reorderFolders(List<int> orderedIds) => _db.batch((b) {
    for (var i = 0; i < orderedIds.length; i++) {
      b.update(
        _f,
        TemplateFoldersCompanion(position: Value(i)),
        where: (f) => f.id.equals(orderedIds[i]),
      );
    }
  });

  Future<void> setFolderCollapsed(int id, bool collapsed) =>
      (_db.update(_f)..where((f) => f.id.equals(id))).write(
        TemplateFoldersCompanion(isCollapsed: Value(collapsed)),
      );

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
            if (!s.setType.isWarmup) ?s.reps,
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
          restSeconds: w.restSeconds,
          targetWeightKg: w.targetWeightKg,
          supersetGroup: w.supersetGroup,
        ),
      );
    }
    return items;
  }
}
