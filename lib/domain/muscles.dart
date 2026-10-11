import '../data/enums.dart';

// Checked in order, so "wrist curl" and "leg curl" win over "curl" and
// "glute ham raise" over "glute".
const _arms = [
  (MuscleGroup.forearms, ['forearm', 'wrist']),
  (
    MuscleGroup.triceps,
    ['tricep', 'pushdown', 'push down', 'pressdown', 'skull crusher', 'kickback'],
  ),
  (MuscleGroup.biceps, ['bicep', 'curl']),
];

const _legs = [
  (MuscleGroup.calves, ['calf', 'calves']),
  (
    MuscleGroup.hamstrings,
    [
      'hamstring',
      'leg curl',
      'glute ham',
      'romanian',
      'rdl',
      'stiff leg',
      'nordic',
    ],
  ),
  (MuscleGroup.glutes, ['glute', 'hip thrust']),
  (
    MuscleGroup.quads,
    ['quad', 'squat', 'leg press', 'leg extension', 'lunge'],
  ),
];

/// Moves an exercise filed under a legacy group ([MuscleGroup.arms],
/// [MuscleGroup.legs]) to a single muscle when its name makes that clear.
/// Anything else keeps [group].
MuscleGroup refineMuscleGroup(String name, MuscleGroup group) {
  final table = switch (group) {
    MuscleGroup.arms => _arms,
    MuscleGroup.legs => _legs,
    _ => null,
  };
  if (table == null) return group;
  final n = ' ${name.toLowerCase().replaceAll(RegExp('[^a-z]+'), ' ')} ';
  for (final (to, keywords) in table) {
    // Keywords match from a word start: "rdl", not "hurdle".
    if (keywords.any((k) => n.contains(' $k'))) return to;
  }
  return group;
}
