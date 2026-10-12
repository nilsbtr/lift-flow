import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../data/database.dart';
import '../data/workout_repository.dart';
import 'records.dart';
import 'units.dart';

// ------------------------------------------------------------ days and weeks

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Adds calendar days at local midnight. Unlike adding a [Duration], this is
/// safe across DST changes.
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// First day of the week containing [d], at local midnight. [firstDay] is
/// [DateTime.monday] … [DateTime.sunday].
DateTime weekStart(DateTime d, [int firstDay = DateTime.monday]) =>
    addDays(d, -((d.weekday - firstDay) % 7));

/// Workout time is capped so a forgotten finish doesn't skew the totals.
const kMaxWorkoutTime = Duration(hours: 4);

Duration workoutTime(Workout w) {
  final end = w.endedAt;
  if (end == null || !end.isAfter(w.startedAt)) return Duration.zero;
  final d = end.difference(w.startedAt);
  return d > kMaxWorkoutTime ? kMaxWorkoutTime : d;
}

Iterable<Workout> _finished(Iterable<Workout> ws) =>
    ws.where((w) => w.endedAt != null);

class WeekStats {
  const WeekStats(
    this.start, {
    this.workouts = 0,
    this.sets = 0,
    this.volumeKg = 0,
    this.time = Duration.zero,
  });

  final DateTime start;
  final int workouts;
  final int sets;
  final double volumeKg;
  final Duration time;
}

/// The last [weeks] weeks up to the one containing [now], oldest first.
List<WeekStats> weeklyStats(
  Iterable<Workout> workouts, {
  required DateTime now,
  int weeks = 12,
  int firstDay = DateTime.monday,
}) {
  final first = addDays(weekStart(now, firstDay), -7 * (weeks - 1));
  final byWeek = groupBy(
    _finished(workouts).where((w) => !w.startedAt.isBefore(first)),
    (w) => weekStart(w.startedAt, firstDay),
  );
  WeekStats week(DateTime start) {
    final ws = byWeek[start];
    if (ws == null) return WeekStats(start);
    return WeekStats(
      start,
      workouts: ws.length,
      sets: ws.map((w) => w.totalSets).sum,
      volumeKg: ws.map((w) => w.totalVolumeKg).sum,
      time: ws.map(workoutTime).fold(Duration.zero, (a, b) => a + b),
    );
  }

  return [for (var i = 0; i < weeks; i++) week(addDays(first, 7 * i))];
}

/// Weeks to chart for [range], ending with the one containing [now]. "All"
/// starts at the week of [earliest]. Never fewer than [minWeeks].
int weeksInRange(
  TrendRange range, {
  required DateTime now,
  DateTime? earliest,
  int firstDay = DateTime.monday,
  int minWeeks = 12,
}) {
  final from = range.since(now) ?? earliest;
  if (from == null) return minWeeks;
  final days = _daysBetween(
    weekStart(from, firstDay),
    weekStart(now, firstDay),
  );
  return math.max(minWeeks, days ~/ 7 + 1);
}

/// Whole calendar days from [a] to [b], safe across DST changes.
int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Consecutive weeks with at least [goal] workouts (1 when off). The current
/// week counts once it meets the goal and never breaks the streak.
int weekStreak(
  Iterable<Workout> workouts, {
  required DateTime now,
  int? goal,
  int firstDay = DateTime.monday,
}) {
  final need = goal ?? 1;
  final counts = _finished(workouts).groupFoldBy<DateTime, int>(
    (w) => weekStart(w.startedAt, firstDay),
    (n, _) => (n ?? 0) + 1,
  );
  var week = weekStart(now, firstDay);
  var streak = (counts[week] ?? 0) >= need ? 1 : 0;
  while ((counts[week = addDays(week, -7)] ?? 0) >= need) {
    streak++;
  }
  return streak;
}

/// Working sets per training day, with intensity levels by quartile.
class DayActivity {
  DayActivity(this.sets) : _sorted = sets.values.sorted((a, b) => a - b);

  final Map<DateTime, int> sets;
  final List<int> _sorted;

  /// 0 on rest days, otherwise 1–4 by the day’s rank among training days.
  int level(DateTime day) {
    final n = sets[dayOf(day)];
    if (n == null) return 0;
    final below = lowerBound(_sorted, n);
    return 1 + math.min(3, below * 4 ~/ _sorted.length);
  }
}

DayActivity dayActivity(Iterable<Workout> workouts) => DayActivity(
  _finished(workouts).groupFoldBy<DateTime, int>(
    (w) => dayOf(w.startedAt),
    (n, w) => (n ?? 0) + w.totalSets,
  ),
);

// ------------------------------------------------------------ trends

enum TrendMetric {
  e1rm('Best e1RM'),
  heaviest('Heaviest'),
  bestLoad('Best load'),
  reps('Most reps'),
  volume('Volume'),
  time('Longest time'),
  totalTime('Total time'),
  distance('Longest distance'),
  totalDistance('Total distance'),

  /// The fastest set, as a speed in m/s so that higher is better.
  pace('Best pace');

  const TrendMetric(this.label);
  final String label;
}

/// Metrics that make sense for an exercise, most useful first.
List<TrendMetric> metricsFor(TrackingType type, LoadMode mode) =>
    switch ((type, mode)) {
      (TrackingType.weights, _) => const [
        TrendMetric.e1rm,
        TrendMetric.heaviest,
        TrendMetric.volume,
      ],
      (TrackingType.duration, _) => [
        TrendMetric.time,
        TrendMetric.totalTime,
        if (mode != LoadMode.none) TrendMetric.heaviest,
      ],
      (TrackingType.distance, _) => [
        TrendMetric.distance,
        TrendMetric.totalDistance,
        TrendMetric.pace,
        if (mode != LoadMode.none) TrendMetric.heaviest,
      ],
      (_, LoadMode.none) => const [
        TrendMetric.reps,
        TrendMetric.e1rm,
        TrendMetric.volume,
      ],
      _ => const [
        TrendMetric.bestLoad,
        TrendMetric.reps,
        TrendMetric.e1rm,
        TrendMetric.volume,
      ],
    };

/// A metric value in the display unit, for charts. Times stay seconds and a
/// pace stays a speed in m/s; [fmtMetricAxis] labels them. [mode] is the
/// exercise's, which picks the distance unit.
double metricDisplay(
  TrendMetric m,
  double v,
  WeightUnit unit, {
  LoadMode mode = LoadMode.none,
}) => switch (m) {
  TrendMetric.reps ||
  TrendMetric.time ||
  TrendMetric.totalTime ||
  TrendMetric.pace => v,
  TrendMetric.distance ||
  TrendMetric.totalDistance => v / DistanceUnit.of(unit, mode).metres,
  _ => kgToUnit(v, unit),
};

/// Axis label for a [metricDisplay] value: "1:30" for a time, "5:30" for a
/// pace, else a short number in the unit of [fmtMetric].
String fmtMetricAxis(
  TrendMetric m,
  double v,
  WeightUnit unit, {
  LoadMode mode = LoadMode.none,
}) => switch (m) {
  TrendMetric.time || TrendMetric.totalTime => fmtHms(v.round()),
  TrendMetric.pace when v <= 0 => '',
  TrendMetric.pace => fmtHms(
    (DistanceUnit.of(unit, mode).paceMetres / v).round(),
  ),
  _ => fmtCompact(v),
};

/// "82.5 kg", "12 reps", "+10 kg", "BW", "1:30", "5 km", "5:30 /km".
/// Estimates get one decimal.
String fmtMetric(
  TrendMetric m,
  double v,
  WeightUnit unit, {
  LoadMode mode = LoadMode.none,
}) => switch (m) {
  TrendMetric.reps => '${v.round()} reps',
  TrendMetric.volume => fmtVolume(v, unit),
  TrendMetric.time || TrendMetric.totalTime => fmtHms(v.round()),
  TrendMetric.distance || TrendMetric.totalDistance => _fmtDistance(
    v,
    DistanceUnit.of(unit, mode),
  ),
  TrendMetric.pace => fmtPace(v, DistanceUnit.of(unit, mode)),
  TrendMetric.e1rm => '${_fmt1(kgToUnit(v, unit))} ${unit.label}',
  TrendMetric.bestLoad when v.abs() < 1e-6 => 'BW',
  TrendMetric.bestLoad =>
    '${v > 0 ? '+' : kMinus}${fmtWeight(v.abs(), unit)} ${unit.label}',
  _ => '${fmtWeight(v, unit)} ${unit.label}',
};

String _fmtDistance(double metres, DistanceUnit u) =>
    '${fmtDistance(metres, u)} ${u.label}';

/// "+2.5 kg", "−1 reps", "+1.2K kg", "+0:15", "+0.5 km". A pace changes by
/// its speed: "+0.4 km/h".
String fmtMetricDelta(
  TrendMetric m,
  double d,
  WeightUnit unit, {
  LoadMode mode = LoadMode.none,
}) => switch (m) {
  TrendMetric.reps => '${fmtDelta(d, (v) => '${v.round()}')} reps',
  TrendMetric.time ||
  TrendMetric.totalTime => fmtDelta(d, (v) => fmtHms(v.round())),
  TrendMetric.distance || TrendMetric.totalDistance => switch (DistanceUnit.of(
    unit,
    mode,
  )) {
    final u => '${fmtDelta(d / u.metres)} ${u.label}',
  },
  TrendMetric.pace => switch (DistanceUnit.of(unit, mode)) {
    final u => '${fmtDelta(speedIn(d, u), _fmt1)} ${u.speedLabel}',
  },
  TrendMetric.volume => '${fmtDelta(kgToUnit(d, unit), fmtCompact)} ${unit.label}',
  TrendMetric.e1rm => '${fmtDelta(kgToUnit(d, unit), _fmt1)} ${unit.label}',
  _ => '${fmtDelta(kgToUnit(d, unit))} ${unit.label}',
};

String _fmt1(double v) => fmtNum((v * 10).roundToDouble() / 10);

/// Value of [metric] over the sets of one session, or null if it doesn't apply.
double? metricValue(TrendMetric metric, Iterable<SetFact> sets) {
  final logged = sets.where((f) => f.isLogged);
  final valid = logged.where((f) => f.type.hasReps);
  double? positive(double v) => v > 0 ? v : null;
  return switch (metric) {
    TrendMetric.e1rm => valid.map((f) {
      final load = effectiveLoad(
        type: f.type,
        loadKg: f.loadKg,
        bodyweightKg: f.bodyweightKg,
      );
      return load == null ? null : estimateOneRm(load, f.reps!);
    }).nonNulls.maxOrNull,
    // Like the PR rule: a time or distance set needs a load to count.
    TrendMetric.heaviest =>
      logged
          .map((f) => f.loadKg)
          .nonNulls
          .where((l) => valid.isNotEmpty || l > 0)
          .maxOrNull,
    TrendMetric.bestLoad => valid.map((f) => f.loadKg ?? 0).maxOrNull,
    // Like the PR rule: assisted reps don't count.
    TrendMetric.reps =>
      valid
          .where((f) => (f.loadKg ?? 0) >= -1e-6)
          .map((f) => f.reps!.toDouble())
          .maxOrNull,
    TrendMetric.volume => positive(valid.map((f) => f.volume).sum),
    TrendMetric.time =>
      logged.map((f) => f.durationSeconds?.toDouble()).nonNulls.maxOrNull,
    // Per side, the time was held twice.
    TrendMetric.totalTime => positive(
      logged
          .map((f) => (f.durationSeconds ?? 0) * (f.perSide ? 2.0 : 1.0))
          .sum,
    ),
    TrendMetric.distance => logged.map((f) => f.distanceM).nonNulls.maxOrNull,
    TrendMetric.totalDistance => positive(
      logged.map((f) => f.distanceM ?? 0).sum,
    ),
    TrendMetric.pace => logged.map((f) => f.speed).nonNulls.maxOrNull,
  };
}

class SessionPoint {
  const SessionPoint({
    required this.workoutId,
    required this.date,
    required this.value,
    required this.best,
    required this.isRecord,
  });

  final int workoutId;
  final DateTime date;
  final double value;

  /// Best value up to and including this session.
  final double best;

  /// Beats every earlier session.
  final bool isRecord;
}

/// One point per workout, oldest first.
List<SessionPoint> sessionSeries(Iterable<SetFact> facts, TrendMetric metric) {
  final sessions = [
    for (final MapEntry(key: id, value: sets) in groupBy(
      facts,
      (f) => f.workoutId,
    ).entries)
      if (metricValue(metric, sets) case final v?) (id, sets.first.startedAt, v),
  ].sortedBy((s) => s.$2);
  double? best;
  return [
    for (final (id, date, v) in sessions)
      SessionPoint(
        workoutId: id,
        date: date,
        value: v,
        isRecord: best != null && v > best + 1e-6,
        best: best = best == null ? v : math.max(best, v),
      ),
  ];
}

/// Change of session [workoutId] versus the session before it.
double? sessionDelta(List<SessionPoint> series, int workoutId) {
  final i = series.indexWhere((p) => p.workoutId == workoutId);
  if (i < 1) return null;
  return series[i].value - series[i - 1].value;
}

/// Working-set facts of an exercise's sessions.
List<SetFact> sessionFacts(Exercise e, Iterable<ExerciseSession> sessions) => [
  for (final s in sessions)
    for (final set in s.sets)
      if (!set.setType.isWarmup)
        SetFact(
          workoutId: s.workout.id,
          startedAt: s.workout.startedAt,
          exerciseId: e.id,
          type: e.trackingType,
          mode: e.loadMode,
          loadKg: set.loadKg,
          reps: set.reps,
          bodyweightKg: s.workout.bodyweightKg,
          durationSeconds: set.durationSeconds,
          distanceM: set.distanceM,
          muscleGroup: e.muscleGroup,
          secondaryMuscles: e.secondaryMuscles,
          perSide: e.perSide,
          perDumbbell: e.perDumbbell,
        ),
];

enum TrendRange {
  m3('3M', 3),
  m6('6M', 6),
  y1('1Y', 12),
  all('All', null);

  const TrendRange(this.label, this.months);
  final String label;
  final int? months;

  DateTime? since(DateTime now) {
    final m = months;
    return m == null ? null : DateTime(now.year, now.month - m, now.day);
  }
}

/// Smallest range that shows at least [minPoints] sessions, else all.
TrendRange defaultRange(
  Iterable<DateTime> dates,
  DateTime now, {
  int minPoints = 6,
}) =>
    TrendRange.values.firstWhereOrNull((r) {
      final since = r.since(now);
      return since == null ||
          dates.where((d) => !d.isBefore(since)).length >= minPoints;
    }) ??
    TrendRange.all;

// ------------------------------------------------------------ summaries

/// Share of a set credited to a secondary muscle group.
const kSecondaryShare = 0.5;

/// Sets per muscle group: a set counts fully for its primary group and
/// [kSecondaryShare] for each secondary one.
Map<MuscleGroup, double> muscleSets(
  Iterable<(MuscleGroup, List<MuscleGroup>)> sets,
) {
  final out = <MuscleGroup, double>{};
  for (final (primary, secondary) in sets) {
    out[primary] = (out[primary] ?? 0) + 1;
    for (final g in secondary) {
      if (g != primary) out[g] = (out[g] ?? 0) + kSecondaryShare;
    }
  }
  return out;
}

/// Weeks of data behind [setsPerMuscle]: up to 4, fewer when the first
/// workout ([first]) is more recent than the 28-day window.
int balanceWeeks(DateTime? first, DateTime now) {
  if (first == null) return 4;
  final days = _daysBetween(first, now) + 1;
  return ((days + 6) ~/ 7).clamp(1, 4);
}

/// Average working sets per week and muscle group over the last 28 days, or
/// over the weeks since [since] (the first workout) when that is shorter.
Map<MuscleGroup, double> setsPerMuscle(
  Iterable<SetFact> facts, {
  required DateTime now,
  DateTime? since,
}) {
  final from = addDays(now, -27);
  final weeks = balanceWeeks(
    since ?? facts.map((f) => f.startedAt).minOrNull,
    now,
  );
  return muscleSets([
    for (final f in facts)
      if (!f.startedAt.isBefore(from)) (f.muscleGroup, f.secondaryMuscles),
  ]).map((k, v) => MapEntry(k, v / weeks));
}

/// Bounds and default of the muscle balance band, in sets per week.
const kBalanceLowest = 1;
const kBalanceHighest = 50;
const kBalanceDefault = (10, 20);

/// Why a muscle balance band is invalid, or null when it is fine.
String? balanceBandError(int? min, int? max) {
  if (min == null || max == null) return 'Enter whole numbers';
  if (min < kBalanceLowest || max > kBalanceHighest) {
    return 'Use $kBalanceLowest–$kBalanceHighest sets';
  }
  if (min >= max) return 'The minimum must be below the maximum';
  return null;
}

/// Totals over finished workouts, e.g. for a year or a lifetime.
class PeriodStats {
  const PeriodStats({
    this.workouts = 0,
    this.sets = 0,
    this.volumeKg = 0,
    this.time = Duration.zero,
    this.days = 0,
  });

  final int workouts;
  final int sets;
  final double volumeKg;
  final Duration time;

  /// Distinct days with a workout.
  final int days;
}

/// Totals of the finished [workouts] started in [year], or all of them.
PeriodStats periodStats(Iterable<Workout> workouts, {int? year}) {
  final ws = _finished(workouts)
      .where((w) => year == null || w.startedAt.year == year)
      .toList();
  return PeriodStats(
    workouts: ws.length,
    sets: ws.map((w) => w.totalSets).sum,
    volumeKg: ws.map((w) => w.totalVolumeKg).sum,
    time: ws.map(workoutTime).fold(Duration.zero, (a, b) => a + b),
    days: ws.map((w) => dayOf(w.startedAt)).toSet().length,
  );
}

/// Years with a finished workout, newest first.
List<int> workoutYears(Iterable<Workout> workouts) =>
    _finished(workouts)
        .map((w) => w.startedAt.year)
        .toSet()
        .sorted((a, b) => b - a);

/// Mean of the entries within the 7 calendar days ending on each entry’s
/// day, for [entries] sorted oldest first. Days without an entry don’t count,
/// so gaps never drag the average down; with one entry in range it equals
/// that entry.
List<double> bodyweightAverages(List<BodyweightEntry> entries) {
  final out = <double>[];
  var from = 0;
  var sum = 0.0;
  for (var i = 0; i < entries.length; i++) {
    sum += entries[i].kg;
    final cutoff = addDays(dayOf(entries[i].date), -6);
    while (dayOf(entries[from].date).isBefore(cutoff)) {
      sum -= entries[from++].kg;
    }
    out.add(sum / (i - from + 1));
  }
  return out;
}

/// Exercises with the most sessions, then the most sets.
List<int> topLifts(Iterable<SetFact> facts, {int count = 4}) {
  final byExercise = groupBy(facts, (f) => f.exerciseId);
  int sessions(List<SetFact> fs) => fs.map((f) => f.workoutId).toSet().length;
  return byExercise.entries
      .sorted((a, b) {
        final c = sessions(b.value).compareTo(sessions(a.value));
        return c != 0 ? c : b.value.length.compareTo(a.value.length);
      })
      .take(count)
      .map((e) => e.key)
      .toList();
}

/// Completed working sets per muscle group in one workout.
Map<MuscleGroup, double> muscleSplit(LoadedWorkout w) => muscleSets([
  for (final e in w.exercises)
    for (final s in e.sets)
      if (s.isCompleted && !s.setType.isWarmup)
        (e.exercise.muscleGroup, e.exercise.secondaryMuscles),
]);

class TimelineMark {
  const TimelineMark(this.at, this.lane, {this.warmup = false});
  final DateTime at;

  /// Index of the exercise in the workout.
  final int lane;
  final bool warmup;
}

/// Completed sets in time order. Times outside the workout come from editing
/// it later and are skipped.
List<TimelineMark> sessionTimeline(LoadedWorkout w) {
  final start = w.workout.startedAt;
  final end = w.workout.endedAt;
  if (end == null) return const [];
  return [
    for (final (lane, ex) in w.exercises.indexed)
      for (final s in ex.sets)
        if (s.completedAt case final at?
            when s.isCompleted && !at.isBefore(start) && !at.isAfter(end))
          TimelineMark(at, lane, warmup: s.setType.isWarmup),
  ].sortedBy((m) => m.at);
}

/// Breaks longer than this are not rest.
const kMaxRest = Duration(minutes: 10);

class RestStats {
  const RestStats({
    required this.count,
    required this.average,
    required this.longest,
  });
  final int count;
  final Duration average;
  final Duration longest;
}

RestStats? restAnalysis(List<TimelineMark> marks) {
  final rests = [
    for (var i = 1; i < marks.length; i++) marks[i].at.difference(marks[i - 1].at),
  ].where((d) => d > Duration.zero && d <= kMaxRest).toList();
  if (rests.isEmpty) return null;
  return RestStats(
    count: rests.length,
    average: Duration(
      milliseconds: rests.map((d) => d.inMilliseconds).average.round(),
    ),
    longest: rests.max,
  );
}

// ------------------------------------------------------------ one workout

class LiftInsight {
  const LiftInsight({
    required this.metric,
    required this.series,
    required this.prs,
  });

  final TrendMetric metric;

  /// Recent sessions ending with this workout, oldest first.
  final List<SessionPoint> series;
  final Set<PrKind> prs;

  double get value => series.last.value;

  double? get delta => series.length < 2
      ? null
      : series.last.value - series[series.length - 2].value;
}

class WorkoutInsights {
  const WorkoutInsights({
    required this.prs,
    required this.lifts,
    this.previous,
  });

  final Map<int, Set<PrKind>> prs;

  /// By exercise id.
  final Map<int, LiftInsight> lifts;

  /// The last earlier workout from the same template.
  final Workout? previous;
}

/// [facts] must hold all working sets of finished workouts for the exercises
/// of [workout].
WorkoutInsights workoutInsights({
  required Workout workout,
  required List<SetFact> facts,
  required Iterable<Workout> history,
  int points = 8,
}) {
  final prs = computePrs(facts, workout.id);
  final lifts = <int, LiftInsight>{};
  final upTo = facts.where((f) => !f.startedAt.isAfter(workout.startedAt));
  groupBy(upTo, (f) => f.exerciseId).forEach((id, fs) {
    for (final m in metricsFor(fs.first.type, fs.first.mode)) {
      final series = sessionSeries(fs, m);
      final i = series.indexWhere((p) => p.workoutId == workout.id);
      if (i < 0) continue;
      lifts[id] = LiftInsight(
        metric: m,
        series: series.sublist(math.max(0, i + 1 - points), i + 1),
        prs: prs[id] ?? const {},
      );
      return;
    }
  });
  final tid = workout.templateId;
  final previous = tid == null
      ? null
      : maxBy(
          _finished(history).where(
            (w) =>
                w.id != workout.id &&
                w.templateId == tid &&
                w.startedAt.isBefore(workout.startedAt),
          ),
          (w) => w.startedAt,
        );
  return WorkoutInsights(prs: prs, lifts: lifts, previous: previous);
}
