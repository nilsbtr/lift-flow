import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../domain/records.dart';
import '../../domain/stats.dart';
import '../../providers.dart';

/// Working sets of the last 180 days.
final statFactsProvider = StreamProvider.autoDispose<List<SetFact>>(
  (ref) => ref
      .watch(workoutRepoProvider)
      .watchStatFacts(addDays(dayOf(DateTime.now()), -180)),
);

/// Average working sets per week, over [weeks] weeks of data.
class MuscleBalance {
  const MuscleBalance(this.sets, this.weeks);
  final Map<MuscleGroup, double> sets;
  final int weeks;
}

final muscleBalanceProvider = Provider.autoDispose<MuscleBalance?>((ref) {
  final facts = ref.watch(statFactsProvider).value;
  if (facts == null) return null;
  final history = ref.watch(historyProvider).value ?? const <Workout>[];
  final now = DateTime.now();
  // New users have less than 4 weeks of data to average over.
  final first =
      history.map((w) => w.startedAt).minOrNull ??
      facts.map((f) => f.startedAt).minOrNull;
  return MuscleBalance(
    setsPerMuscle(facts, now: now, since: first),
    balanceWeeks(first, now),
  );
});

/// Every PR of the active exercises, newest first. Records need an earlier
/// best, so this looks at all history, not just the last 180 days.
final prHistoryProvider = FutureProvider.autoDispose<List<PrEvent>>((
  ref,
) async {
  await ref.watch(historyProvider.future);
  final exercises = await ref.watch(exercisesProvider.future);
  final facts = await ref.read(workoutRepoProvider).setFacts([
    for (final e in exercises) e.id,
  ]);
  return prHistory(facts);
});

class TopLift {
  const TopLift(this.exercise, this.metric, this.series);
  final Exercise exercise;
  final TrendMetric metric;
  final List<SessionPoint> series;
}

/// Most trained active exercises of the last 180 days.
final topLiftsProvider = Provider.autoDispose<List<TopLift>?>((ref) {
  final facts = ref.watch(statFactsProvider).value;
  final exercises = ref.watch(exercisesProvider).value;
  if (facts == null || exercises == null) return null;
  final byId = {for (final e in exercises) e.id: e};
  final active = groupBy(
    facts.where((f) => byId.containsKey(f.exerciseId)),
    (f) => f.exerciseId,
  );
  return [
    for (final id in topLifts(active.values.flattened))
      if (byId[id] case final e?)
        for (final m in metricsFor(e.trackingType, e.loadMode).take(1))
          TopLift(e, m, sessionSeries(active[id]!, m)),
  ].where((l) => l.series.isNotEmpty).toList();
});
