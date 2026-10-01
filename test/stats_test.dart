import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/workout_repository.dart';
import 'package:lift_flow/domain/records.dart';
import 'package:lift_flow/domain/stats.dart';

Workout workout(
  int id,
  DateTime start, {
  Duration length = const Duration(hours: 1),
  int sets = 10,
  double volume = 1000,
  int? templateId,
  bool finished = true,
}) => Workout(
  id: id,
  templateId: templateId,
  name: 'W$id',
  startedAt: start,
  endedAt: finished ? start.add(length) : null,
  totalSets: sets,
  totalVolumeKg: volume,
  exerciseCount: 1,
);

SetFact fact(
  int workoutId,
  DateTime at, {
  int exerciseId = 1,
  double? load = 100,
  int? reps = 5,
  TrackingType type = TrackingType.weights,
  LoadMode mode = LoadMode.none,
  double? bodyweight,
  MuscleGroup muscle = MuscleGroup.chest,
}) => SetFact(
  workoutId: workoutId,
  startedAt: at,
  exerciseId: exerciseId,
  type: type,
  mode: mode,
  loadKg: load,
  reps: reps,
  bodyweightKg: bodyweight,
  muscleGroup: muscle,
);

WorkoutSet set(
  int id, {
  DateTime? at,
  bool warmup = false,
  bool done = true,
  double load = 100,
  int reps = 5,
}) => WorkoutSet(
  id: id,
  workoutExerciseId: 1,
  position: id,
  loadKg: load,
  reps: reps,
  isCompleted: done,
  completedAt: at,
  isWarmup: warmup,
);

Exercise exercise(int id, {MuscleGroup muscle = MuscleGroup.chest}) =>
    Exercise(
      id: id,
      name: 'E$id',
      muscleGroup: muscle,
      trackingType: TrackingType.weights,
      loadMode: LoadMode.none,
      isArchived: false,
      createdAt: DateTime(2024),
    );

LoadedExercise loaded(Exercise e, List<WorkoutSet> sets) => LoadedExercise(
  WorkoutExercise(id: e.id, workoutId: 1, exerciseId: e.id, position: e.id),
  e,
  sets,
);

void main() {
  // A Wednesday.
  final now = DateTime(2025, 3, 12, 18);

  group('weeks', () {
    test('weekStart is Monday midnight, across DST', () {
      expect(weekStart(now), DateTime(2025, 3, 10));
      expect(weekStart(DateTime(2025, 3, 10)), DateTime(2025, 3, 10));
      expect(weekStart(DateTime(2025, 3, 16, 23)), DateTime(2025, 3, 10));
      // EU DST starts on 30 March 2025.
      expect(weekStart(DateTime(2025, 4, 2)), DateTime(2025, 3, 31));
      expect(addDays(DateTime(2025, 3, 29), 2), DateTime(2025, 3, 31));
    });

    test('weeklyStats buckets and caps time', () {
      final stats = weeklyStats(
        [
          workout(1, DateTime(2025, 3, 10, 9), sets: 12, volume: 500),
          workout(2, DateTime(2025, 3, 11, 9), length: const Duration(hours: 9)),
          workout(3, DateTime(2025, 3, 3, 9)),
          workout(4, DateTime(2025, 3, 12, 9), finished: false),
          workout(5, DateTime(2024, 1, 1)),
        ],
        now: now,
        weeks: 3,
      );
      expect(stats.map((s) => s.start), [
        DateTime(2025, 2, 24),
        DateTime(2025, 3, 3),
        DateTime(2025, 3, 10),
      ]);
      expect(stats.map((s) => s.workouts), [0, 1, 2]);
      expect(stats.last.sets, 22);
      expect(stats.last.volumeKg, 1500);
      expect(stats.last.time, const Duration(hours: 5));
    });

    test('weekStreak ignores an unfinished current week', () {
      final ws = [
        workout(1, DateTime(2025, 3, 3)),
        workout(2, DateTime(2025, 3, 5)),
        workout(3, DateTime(2025, 2, 24)),
        workout(4, DateTime(2025, 2, 26)),
        workout(5, DateTime(2025, 2, 10)),
        workout(6, DateTime(2025, 2, 12)),
      ];
      expect(weekStreak(ws, now: now), 2);
      expect(weekStreak(ws, now: now, goal: 2), 2);
      expect(weekStreak(ws, now: now, goal: 3), 0);
      final withThisWeek = [...ws, workout(7, DateTime(2025, 3, 11))];
      expect(weekStreak(withThisWeek, now: now), 3);
      expect(weekStreak(withThisWeek, now: now, goal: 2), 2);
      expect(weekStreak(const [], now: now), 0);
    });

    test('dayActivity levels by quartile', () {
      final activity = dayActivity([
        for (var i = 1; i <= 8; i++)
          workout(i, DateTime(2025, 3, i, 9), sets: i * 5),
        workout(9, DateTime(2025, 3, 8, 18), sets: 5),
      ]);
      expect(activity.sets[DateTime(2025, 3, 8)], 45);
      expect(activity.level(DateTime(2025, 3, 9)), 0);
      expect(activity.level(DateTime(2025, 3, 1, 12)), 1);
      expect(activity.level(DateTime(2025, 3, 8)), 4);
      expect(
        [for (var i = 1; i <= 8; i++) activity.level(DateTime(2025, 3, i))],
        orderedEquals([1, 1, 2, 2, 3, 3, 4, 4]),
      );
    });
  });

  group('trends', () {
    test('metricsFor by tracking and load mode', () {
      expect(metricsFor(TrackingType.weights, LoadMode.none).first,
          TrendMetric.e1rm);
      expect(metricsFor(TrackingType.bodyweight, LoadMode.none).first,
          TrendMetric.reps);
      expect(metricsFor(TrackingType.bodyweight, LoadMode.added).first,
          TrendMetric.bestLoad);
    });

    test('sessionSeries marks records against earlier sessions', () {
      final d1 = DateTime(2025, 1, 1);
      final d2 = DateTime(2025, 1, 8);
      final d3 = DateTime(2025, 1, 15);
      final d4 = DateTime(2025, 1, 22);
      final facts = [
        fact(3, d3, load: 110),
        fact(1, d1, load: 100),
        fact(1, d1, load: 105, reps: 1),
        fact(2, d2, load: 90),
        fact(4, d4, load: 110),
        fact(4, d4, load: null, reps: null),
      ];
      final s = sessionSeries(facts, TrendMetric.heaviest);
      expect(s.map((p) => p.workoutId), [1, 2, 3, 4]);
      expect(s.map((p) => p.value), [105, 90, 110, 110]);
      expect(s.map((p) => p.isRecord), [false, false, true, false]);
      expect(s.map((p) => p.best), [105, 105, 110, 110]);
      expect(sessionDelta(s, 2), -15);
      expect(sessionDelta(s, 1), isNull);

      final e = sessionSeries(facts, TrendMetric.e1rm);
      expect(e.first.value, closeTo(116.67, 0.01));
      final v = sessionSeries(facts, TrendMetric.volume);
      expect(v.first.value, 605);
    });

    test('bodyweight metrics need a body weight for load', () {
      final d = DateTime(2025, 1, 1);
      final noBw = [
        fact(1, d, type: TrackingType.bodyweight, load: null, reps: 10),
      ];
      expect(metricValue(TrendMetric.reps, noBw), 10);
      expect(metricValue(TrendMetric.e1rm, noBw), isNull);
      expect(metricValue(TrendMetric.volume, noBw), isNull);
      final assisted = [
        fact(1, d,
            type: TrackingType.bodyweight,
            mode: LoadMode.assisted,
            load: -20,
            reps: 8,
            bodyweight: 80),
      ];
      expect(metricValue(TrendMetric.bestLoad, assisted), -20);
      expect(metricValue(TrendMetric.reps, assisted), isNull);
      expect(metricValue(TrendMetric.volume, assisted), 480);
    });

    test('sessionFacts skips warm-ups', () {
      final e = exercise(1);
      final w = workout(1, DateTime(2025, 1, 1));
      final facts = sessionFacts(e, [
        ExerciseSession(w, [set(1, warmup: true, load: 40), set(2)]),
      ]);
      expect(facts.single.loadKg, 100);
      expect(facts.single.muscleGroup, MuscleGroup.chest);
    });

    test('defaultRange picks the smallest range with enough points', () {
      final recent = [for (var i = 0; i < 6; i++) DateTime(2025, 3, 1 + i)];
      expect(defaultRange(recent, now), TrendRange.m3);
      final spread = [
        for (var i = 0; i < 6; i++) DateTime(2024, 10 + (i ~/ 3), 1 + i),
      ];
      expect(defaultRange(spread, now), TrendRange.m6);
      expect(defaultRange([DateTime(2020)], now), TrendRange.all);
    });
  });

  group('summaries', () {
    test('setsPerMuscle averages the last 28 days', () {
      final facts = [
        for (var i = 0; i < 8; i++) fact(1, DateTime(2025, 3, 1)),
        fact(2, DateTime(2025, 3, 5), muscle: MuscleGroup.back),
        fact(3, DateTime(2025, 2, 1), muscle: MuscleGroup.legs),
      ];
      final m = setsPerMuscle(facts, now: now);
      expect(m[MuscleGroup.chest], 2);
      expect(m[MuscleGroup.back], 0.25);
      expect(m.containsKey(MuscleGroup.legs), isFalse);
    });

    test('topLifts ranks by sessions, then sets', () {
      final d = DateTime(2025, 3, 1);
      final facts = [
        fact(1, d, exerciseId: 1),
        fact(2, d, exerciseId: 1),
        for (var i = 0; i < 5; i++) fact(1, d, exerciseId: 2),
        fact(1, d, exerciseId: 3),
        fact(2, d, exerciseId: 3),
        fact(2, d, exerciseId: 3),
      ];
      expect(topLifts(facts), [3, 1, 2]);
      expect(topLifts(facts, count: 1), [3]);
    });

    test('timeline, rest and split', () {
      final start = DateTime(2025, 3, 1, 10);
      DateTime at(int min) => start.add(Duration(minutes: min));
      final w = LoadedWorkout(
        workout(1, start, length: const Duration(minutes: 60)),
        [
          loaded(exercise(1), [
            set(1, at: at(2), warmup: true),
            set(2, at: at(4)),
            set(3, at: at(7)),
          ]),
          loaded(exercise(2, muscle: MuscleGroup.back), [
            set(4, at: at(30)),
            set(5, at: at(32)),
            set(6, at: at(90)),
            set(7, done: false),
          ]),
        ],
      );
      final marks = sessionTimeline(w);
      expect(marks.map((m) => m.lane), [0, 0, 0, 1, 1]);
      expect(marks.first.warmup, isTrue);
      final rest = restAnalysis(marks)!;
      expect(rest.count, 3);
      expect(rest.longest, const Duration(minutes: 3));
      expect(rest.average, const Duration(minutes: 7) ~/ 3);
      expect(restAnalysis(const []), isNull);
      expect(muscleSplit(w), {MuscleGroup.chest: 2, MuscleGroup.back: 3});
    });

    test('workoutInsights compares with earlier sessions', () {
      final d1 = DateTime(2025, 1, 1);
      final d2 = DateTime(2025, 1, 8);
      final d3 = DateTime(2025, 1, 15);
      final facts = [
        fact(1, d1, load: 100),
        fact(2, d2, load: 110),
        fact(3, d3, load: 120),
        fact(2, d2, exerciseId: 2, load: 50),
      ];
      final history = [
        workout(1, d1, templateId: 7),
        workout(2, d2, templateId: 8),
        workout(3, d3, templateId: 7),
      ];
      final i = workoutInsights(
        workout: history[1],
        facts: facts,
        history: history,
      );
      expect(i.lifts.keys, unorderedEquals([1, 2]));
      final lift = i.lifts[1]!;
      expect(lift.metric, TrendMetric.e1rm);
      expect(lift.series.map((p) => p.workoutId), [1, 2]);
      expect(lift.delta, closeTo(10 * 7 / 6, 1e-9));
      expect(lift.prs, contains(PrKind.heaviest));
      expect(i.lifts[2]!.delta, isNull);
      expect(i.previous, isNull);

      final last = workoutInsights(
        workout: history[2],
        facts: facts,
        history: history,
        points: 2,
      );
      expect(last.previous?.id, 1);
      expect(last.lifts[1]!.series.map((p) => p.workoutId), [2, 3]);
    });

    test('metric formatting', () {
      expect(fmtMetric(TrendMetric.e1rm, 100, WeightUnit.kg), '100 kg');
      expect(fmtMetric(TrendMetric.reps, 12, WeightUnit.kg), '12 reps');
      expect(fmtMetric(TrendMetric.bestLoad, 0, WeightUnit.kg), 'BW');
      expect(fmtMetric(TrendMetric.bestLoad, -20, WeightUnit.kg), '\u221220 kg');
      expect(fmtMetric(TrendMetric.volume, 12500, WeightUnit.kg), '12,500 kg');
      expect(
        fmtMetricDelta(TrendMetric.heaviest, 2.5, WeightUnit.kg),
        '+2.5 kg',
      );
      expect(fmtMetricDelta(TrendMetric.reps, -1, WeightUnit.kg), '\u22121 reps');
      expect(
        fmtMetricDelta(TrendMetric.volume, 1200, WeightUnit.kg),
        '+1.2K kg',
      );
      expect(metricDisplay(TrendMetric.reps, 8, WeightUnit.lb), 8);
    });
  });
}
