import '../data/database.dart';

/// Launchers show about four app shortcuts.
const kMaxShortcuts = 4;

/// Templates to offer as launcher shortcuts: the ones started most recently
/// first, judged by their latest workout in [workouts] (live or finished),
/// then the rest in [templates] order so a fresh install still gets some.
List<WorkoutTemplate> shortcutTemplates(
  List<WorkoutTemplate> templates,
  Iterable<Workout> workouts, {
  int limit = kMaxShortcuts,
}) {
  final lastUsed = <int, DateTime>{};
  for (final w in workouts) {
    final id = w.templateId;
    if (id == null) continue;
    final last = lastUsed[id];
    if (last == null || w.startedAt.isAfter(last)) lastUsed[id] = w.startedAt;
  }
  final order = {for (final (i, t) in templates.indexed) t.id: i};
  final used = [
    for (final t in templates)
      if (lastUsed.containsKey(t.id)) t,
  ];
  used.sort((a, b) {
    final byDate = lastUsed[b.id]!.compareTo(lastUsed[a.id]!);
    return byDate != 0 ? byDate : order[a.id]!.compareTo(order[b.id]!);
  });
  return [
    ...used,
    for (final t in templates)
      if (!lastUsed.containsKey(t.id)) t,
  ].take(limit).toList();
}
