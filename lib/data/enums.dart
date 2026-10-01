enum MuscleGroup {
  chest('Chest'),
  back('Back'),
  shoulders('Shoulders'),
  arms('Arms'),
  legs('Legs'),
  core('Core'),
  fullBody('Full body'),
  other('Other');

  const MuscleGroup(this.label);
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
