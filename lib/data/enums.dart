enum MuscleGroup {
  chest('Chest'),
  back('Back'),
  shoulders('Shoulders'),
  biceps('Biceps'),
  triceps('Triceps'),
  forearms('Forearms'),
  arms('Arms'),
  core('Core'),
  quads('Quads'),
  hamstrings('Hamstrings'),
  glutes('Glutes'),
  calves('Calves'),
  legs('Legs'),
  fullBody('Full body'),
  other('Other');

  const MuscleGroup(this.label);
  final String label;

  /// Generic groups from before the split into single muscles. Kept so old
  /// data and backups stay valid, but not offered for new exercises.
  bool get isLegacy => this == arms || this == legs;

  /// Groups a picker offers.
  static const selectable = [
    chest,
    back,
    shoulders,
    biceps,
    triceps,
    forearms,
    core,
    quads,
    hamstrings,
    glutes,
    calves,
    fullBody,
    other,
  ];

  /// [selectable] plus the legacy groups in [current], in display order.
  static List<MuscleGroup> selectableWith(Iterable<MuscleGroup> current) => [
    for (final g in values)
      if (!g.isLegacy || current.contains(g)) g,
  ];
}

enum Equipment {
  none('None'),
  barbell('Barbell'),
  dumbbell('Dumbbell'),
  machine('Machine'),
  cable('Cable'),
  kettlebell('Kettlebell');

  const Equipment(this.label);
  final String label;
}

enum TrackingType {
  weights('Weights'),
  bodyweight('Bodyweight');

  const TrackingType(this.label);
  final String label;
}

/// How the load column works for bodyweight exercises. Ignored for weights.
///
/// Loads are stored signed: `added` >= 0, `assisted` <= 0, `none` is null.
enum LoadMode {
  none('Bodyweight only'),
  added('Extra weight'),
  assisted('Assisted');

  const LoadMode(this.label);
  final String label;
}

enum SetType {
  normal('Normal', ''),
  warmup('Warm-up', 'W'),
  drop('Drop set', 'D'),
  failure('Failure', 'F'),
  amrap('AMRAP', 'A');

  const SetType(this.label, this.letter);
  final String label;

  /// Short marker for the set. Empty for [normal].
  final String letter;

  /// Warm-ups are the only sets left out of totals, facts and records.
  bool get isWarmup => this == warmup;
}

/// How set effort is entered and shown. It is stored as RPE either way;
/// RIR is 10 − RPE.
enum EffortMode {
  off('Off'),
  rpe('RPE'),
  rir('RIR');

  const EffortMode(this.label);
  final String label;
}

enum WeightUnit {
  kg('kg'),
  lb('lb');

  const WeightUnit(this.label);
  final String label;
}

enum ThemePref {
  system('System'),
  light('Light'),
  dark('Dark');

  const ThemePref(this.label);
  final String label;
}
