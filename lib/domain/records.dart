import '../data/enums.dart';

const double _eps = 1e-6;

/// Load actually moved in kg. For bodyweight exercises this requires a known
/// body weight: body weight + signed load.
double? effectiveLoad({
  required TrackingType type,
  required double? loadKg,
  required double? bodyweightKg,
}) {
  if (type == TrackingType.weights) return loadKg;
  if (bodyweightKg == null) return null;
  return bodyweightKg + (loadKg ?? 0);
}

/// Volume of one set in kg. [perDumbbell] counts the entered load twice and
/// [perSide] the reps. Records and e1RM use the entered values instead.
double setVolume({
  required TrackingType type,
  required double? loadKg,
  required int? reps,
  required double? bodyweightKg,
  bool perSide = false,
  bool perDumbbell = false,
}) {
  if (reps == null || reps <= 0) return 0;
  final eff = effectiveLoad(
    type: type,
    loadKg: perDumbbell && loadKg != null && loadKg > 0 ? loadKg * 2 : loadKg,
    bodyweightKg: bodyweightKg,
  );
  if (eff == null || eff <= 0) return 0;
  return eff * (perSide ? reps * 2 : reps);
}

/// Epley estimated 1RM; only meaningful for 1–12 reps.
double? estimateOneRm(double load, int reps) {
  if (reps < 1 || reps > 12 || load <= 0) return null;
  if (reps == 1) return load;
  return load * (1 + reps / 30);
}

enum PrKind {
  heaviest('Heaviest'),
  e1rm('Best e1RM'),
  bestLoad('Best load'),
  mostReps('Most reps');

  const PrKind(this.label);
  final String label;
}

/// A completed set joined with the context needed for records.
class SetFact {
  const SetFact({
    required this.workoutId,
    required this.startedAt,
    required this.exerciseId,
    required this.type,
    required this.mode,
    required this.loadKg,
    required this.reps,
    required this.bodyweightKg,
    this.muscleGroup = MuscleGroup.other,
    this.secondaryMuscles = const [],
    this.perSide = false,
    this.perDumbbell = false,
  });

  final int workoutId;
  final DateTime startedAt;
  final int exerciseId;
  final TrackingType type;
  final LoadMode mode;
  final double? loadKg;
  final int? reps;
  final double? bodyweightKg;
  final MuscleGroup muscleGroup;
  final List<MuscleGroup> secondaryMuscles;
  final bool perSide;
  final bool perDumbbell;

  double get volume => setVolume(
    type: type,
    loadKg: loadKg,
    reps: reps,
    bodyweightKg: bodyweightKg,
    perSide: perSide,
    perDumbbell: perDumbbell,
  );
}

/// Best values of one exercise over a set of facts.
class ExerciseBests {
  double? heaviest;
  double? e1rm;
  double? bestLoad;
  int? mostReps;

  void add(SetFact f) {
    final reps = f.reps;
    if (reps == null || reps <= 0) return;
    if (f.type == TrackingType.weights) {
      final load = f.loadKg;
      if (load == null) return;
      heaviest = _max(heaviest, load);
      final e = estimateOneRm(load, reps);
      if (e != null) e1rm = _max(e1rm, e);
      return;
    }
    final load = f.loadKg ?? 0;
    if (f.mode != LoadMode.none) bestLoad = _max(bestLoad, load);
    if (load >= -_eps) {
      mostReps = mostReps == null || reps > mostReps! ? reps : mostReps;
    }
    final eff = effectiveLoad(
      type: f.type,
      loadKg: f.loadKg,
      bodyweightKg: f.bodyweightKg,
    );
    if (eff != null) {
      final e = estimateOneRm(eff, reps);
      if (e != null) e1rm = _max(e1rm, e);
    }
  }

  double? valueOf(PrKind k) => switch (k) {
    PrKind.heaviest => heaviest,
    PrKind.e1rm => e1rm,
    PrKind.bestLoad => bestLoad,
    PrKind.mostReps => mostReps?.toDouble(),
  };

  static double _max(double? a, double b) => a == null || b > a ? b : a;
}

/// Best load at one rep count.
class RepMax {
  const RepMax(this.reps, this.loadKg, this.workoutId, this.date);
  final int reps;
  final double loadKg;
  final int workoutId;
  final DateTime date;
}

/// Whether a table of best loads per rep count says anything for [mode].
/// Bodyweight-only sets all carry the same load.
bool hasRepMaxes(TrackingType type, LoadMode mode) =>
    type == TrackingType.weights || mode != LoadMode.none;

/// Best load at each exact rep count from 1 to [maxReps], by reps. [facts] are
/// working sets (warm-ups are left out when building them). Loads are the
/// entered ones: for bodyweight exercises the signed extra or assisted load,
/// where the higher value (closer to zero when assisted) is better. An equal
/// load keeps the date it was first set. Counts without a set are left out.
List<RepMax> repMaxes(Iterable<SetFact> facts, {int maxReps = 12}) {
  final sorted = [...facts]
    ..sort((a, b) {
      final c = a.startedAt.compareTo(b.startedAt);
      return c != 0 ? c : a.workoutId.compareTo(b.workoutId);
    });
  final best = <int, RepMax>{};
  for (final f in sorted) {
    final reps = f.reps;
    if (reps == null || reps < 1 || reps > maxReps) continue;
    if (!hasRepMaxes(f.type, f.mode)) continue;
    final weights = f.type == TrackingType.weights;
    final load = f.loadKg ?? (weights ? null : 0);
    if (load == null || (weights && load <= 0)) continue;
    final prev = best[reps];
    if (prev == null || load > prev.loadKg + _eps) {
      best[reps] = RepMax(reps, load, f.workoutId, f.startedAt);
    }
  }
  return [for (final r in best.keys.toList()..sort()) best[r]!];
}

/// Computes PRs set in [workoutId]. [facts] must contain all completed sets of
/// finished workouts for the relevant exercises, including [workoutId].
/// A PR requires an earlier best to beat. Returns exerciseId → kinds.
Map<int, Set<PrKind>> computePrs(List<SetFact> facts, int workoutId) {
  DateTime? start;
  for (final f in facts) {
    if (f.workoutId == workoutId) {
      start = f.startedAt;
      break;
    }
  }
  if (start == null) return const {};

  final before = <int, ExerciseBests>{};
  final current = <int, ExerciseBests>{};
  for (final f in facts) {
    if (f.workoutId == workoutId) {
      current.putIfAbsent(f.exerciseId, ExerciseBests.new).add(f);
    } else if (f.startedAt.isBefore(start) ||
        (f.startedAt == start && f.workoutId < workoutId)) {
      before.putIfAbsent(f.exerciseId, ExerciseBests.new).add(f);
    }
  }

  final result = <int, Set<PrKind>>{};
  current.forEach((exerciseId, now) {
    final prev = before[exerciseId];
    if (prev == null) return;
    for (final k in PrKind.values) {
      final a = now.valueOf(k);
      final b = prev.valueOf(k);
      if (a != null && b != null && a > b + _eps) {
        (result[exerciseId] ??= {}).add(k);
      }
    }
  });
  return result;
}
