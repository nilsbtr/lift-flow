import '../data/enums.dart';

/// The name of a workout started without a template.
const kDefaultWorkoutName = 'Workout';

enum _Region {
  chest('Chest'),
  back('Back'),
  shoulders('Shoulders'),
  arms('Arms'),
  legs('Legs'),
  core('Core');

  const _Region(this.label);
  final String label;

  bool get isUpper => index < legs.index;
}

_Region? _regionOf(MuscleGroup g) => switch (g) {
  MuscleGroup.chest => _Region.chest,
  MuscleGroup.back => _Region.back,
  MuscleGroup.shoulders => _Region.shoulders,
  MuscleGroup.biceps ||
  MuscleGroup.triceps ||
  MuscleGroup.forearms ||
  MuscleGroup.arms => _Region.arms,
  MuscleGroup.quads ||
  MuscleGroup.hamstrings ||
  MuscleGroup.glutes ||
  MuscleGroup.calves ||
  MuscleGroup.legs => _Region.legs,
  MuscleGroup.core => _Region.core,
  MuscleGroup.fullBody || MuscleGroup.other => null,
};

/// A name for a workout from its working sets per primary muscle group, e.g.
/// "Chest and arms", or null when nothing says what was trained.
///
/// Fine-grained groups roll up into arms and legs once two of them are
/// trained, a lone one keeps its own name ("Biceps"). Regions under a fifth of
/// the sets are left out. Four or more regions, or legs with two upper-body
/// ones, read as "Full body" ("Upper body" without legs).
String? suggestWorkoutName(Map<MuscleGroup, int> workingSets) {
  final groups = <_Region, Map<MuscleGroup, int>>{};
  var full = 0;
  for (final MapEntry(key: g, value: n) in workingSets.entries) {
    if (n <= 0) continue;
    if (g == MuscleGroup.fullBody) full += n;
    if (_regionOf(g) case final r?) (groups[r] ??= {})[g] = n;
  }
  int sets(_Region r) => groups[r]!.values.fold(0, (a, b) => a + b);

  final total = full + groups.keys.fold(0, (a, r) => a + sets(r));
  if (total == 0) return null;
  if (full * 2 >= total) return 'Full body';

  final top = [
    for (final r in _Region.values)
      if (groups.containsKey(r) && sets(r) * 5 >= total) r,
  ]..sort((a, b) => sets(a) == sets(b) ? a.index - b.index : sets(b) - sets(a));
  if (top.isEmpty) return 'Full body';

  final legs = top.contains(_Region.legs);
  final upper = top.where((r) => r.isUpper).length;
  if ((legs && top.length >= 3 && upper >= 2) || top.length >= 4) {
    return legs ? 'Full body' : 'Upper body';
  }

  String label(_Region r) {
    final g = groups[r]!.keys;
    return g.length == 1 ? g.single.label : r.label;
  }

  final names = [
    label(top.first),
    for (final r in top.skip(1)) label(r).toLowerCase(),
  ];
  if (names.length == 1) return names.single;
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}
