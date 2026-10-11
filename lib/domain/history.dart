import '../data/database.dart';
import 'stats.dart';
import 'units.dart';

// ------------------------------------------------------------ filtering

/// History narrowed by name, template and exercise. [exerciseWorkoutIds] are
/// the workouts that include the chosen exercise; null matches everything.
List<Workout> filterHistory(
  Iterable<Workout> workouts, {
  String query = '',
  int? templateId,
  Set<int>? exerciseWorkoutIds,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final w in workouts)
      if ((q.isEmpty || w.name.toLowerCase().contains(q)) &&
          (templateId == null || w.templateId == templateId) &&
          (exerciseWorkoutIds == null || exerciseWorkoutIds.contains(w.id)))
        w,
  ];
}

// ------------------------------------------------------------ weekly load

/// Volume of the week so far against the same stretch of the week before.
class WeekComparison {
  const WeekComparison({required this.thisKg, required this.lastKg});
  final double thisKg;
  final double lastKg;

  /// Relative change, 0.1 for +10 %.
  double get change => thisKg / lastKg - 1;

  /// "Volume +12% vs this time last week".
  String get label {
    final pct = (change * 100).round();
    return pct == 0
        ? 'Volume level with this time last week'
        : 'Volume ${fmtDelta(pct.toDouble(), (v) => '${v.round()}%')} '
              'vs this time last week';
  }
}

/// Compares like with like: this week up to [now] against the matching part of
/// last week, so a fresh week doesn't read as a drop. Null until both have
/// some volume.
WeekComparison? compareWeeks(
  Iterable<Workout> workouts, {
  required DateTime now,
  int firstDay = DateTime.monday,
}) {
  final start = weekStart(now, firstDay);
  final lastStart = addDays(start, -7);
  final lastEnd = lastStart.add(now.difference(start));
  var thisKg = 0.0;
  var lastKg = 0.0;
  for (final w in workouts) {
    if (w.endedAt == null) continue;
    final t = w.startedAt;
    if (!t.isBefore(start) && !t.isAfter(now)) {
      thisKg += w.totalVolumeKg;
    } else if (!t.isBefore(lastStart) && t.isBefore(lastEnd)) {
      lastKg += w.totalVolumeKg;
    }
  }
  if (thisKg <= 0 || lastKg <= 0) return null;
  return WeekComparison(thisKg: thisKg, lastKg: lastKg);
}

// ------------------------------------------------------------ start and end

/// The end time picked on the clock: on the day of [start], or the day after
/// when it falls before it and that gives a plausible session (up to 12 h).
DateTime endAtClock(DateTime start, int hour, int minute) {
  final sameDay = DateTime(start.year, start.month, start.day, hour, minute);
  if (sameDay.isAfter(start)) return sameDay;
  final nextDay = DateTime(
    start.year,
    start.month,
    start.day + 1,
    hour,
    minute,
  );
  return nextDay.difference(start) <= const Duration(hours: 12)
      ? nextDay
      : sameDay;
}

/// Why [start] and [end] can't be saved, or null when they can.
String? workoutTimesError(DateTime start, DateTime end, DateTime now) {
  if (start.isAfter(now) || end.isAfter(now)) return 'That’s in the future.';
  if (!end.isAfter(start)) return 'End must be after start.';
  return null;
}
