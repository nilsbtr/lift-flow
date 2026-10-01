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

final muscleBalanceProvider = Provider.autoDispose<Map<MuscleGroup, double>?>(
  (ref) => switch (ref.watch(statFactsProvider).value) {
    final facts? => setsPerMuscle(facts, now: DateTime.now()),
    null => null,
  },
);

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
