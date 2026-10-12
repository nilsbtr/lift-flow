import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/backup_service.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/exercise_repository.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/data/workout_repository.dart';
import 'package:lift_flow/domain/exercise_search.dart';
import 'package:lift_flow/domain/records.dart';
import 'package:lift_flow/domain/stats.dart';
import 'package:lift_flow/domain/units.dart';
import 'package:lift_flow/features/gym/exercise_editor_sheet.dart';
import 'package:lift_flow/features/gym/exercise_picker_sheet.dart';
import 'package:lift_flow/features/workout/set_row.dart';
import 'package:lift_flow/features/workout/workout_controller.dart';
import 'package:lift_flow/features/workout/workout_screen.dart';
import 'package:lift_flow/providers.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:lift_flow/widgets/set_list.dart';
import 'package:material_ui/material_ui.dart';

const time = TrackingType.duration;
const dist = TrackingType.distance;

Exercise exercise({
  TrackingType type = time,
  LoadMode mode = LoadMode.none,
  bool perSide = false,
}) => Exercise(
  id: 1,
  name: 'Plank',
  muscleGroup: MuscleGroup.core,
  trackingType: type,
  loadMode: mode,
  isArchived: false,
  createdAt: DateTime(2025),
  equipment: Equipment.none,
  perSide: perSide,
  perDumbbell: false,
  secondaryMuscles: const [],
);

WorkoutSet set(
  int id, {
  double? kg,
  int? reps,
  int? secs,
  double? metres,
  bool done = false,
  SetType type = SetType.normal,
  double? rpe,
  String? note,
}) => WorkoutSet(
  id: id,
  workoutExerciseId: 1,
  position: id - 1,
  loadKg: kg,
  reps: reps,
  durationSeconds: secs,
  distanceM: metres,
  isCompleted: done,
  setType: type,
  rpe: rpe,
  note: note,
);

DraftExercise draft(
  List<WorkoutSet> sets, {
  required Exercise of,
  ExerciseBests? bests,
  List<WorkoutSet> previous = const [],
  int? repsMin,
  int? repsMax,
}) => DraftExercise(
  id: 1,
  exercise: of,
  sets: sets,
  previous: previous,
  bests: bests,
  repsMin: repsMin,
  repsMax: repsMax,
  stepKg: 2.5,
);

SetFact fact(
  TrackingType type, {
  int? secs,
  double? metres,
  double? kg,
  int? reps,
  LoadMode mode = LoadMode.none,
  int workoutId = 1,
  bool perSide = false,
}) => SetFact(
  workoutId: workoutId,
  startedAt: DateTime(2025, 1, workoutId),
  exerciseId: 1,
  type: type,
  mode: mode,
  loadKg: kg,
  reps: reps,
  durationSeconds: secs,
  distanceM: metres,
  bodyweightKg: 80,
  perSide: perSide,
);

ExerciseBests bests(Iterable<SetFact> facts) {
  final b = ExerciseBests();
  facts.forEach(b.add);
  return b;
}

void main() {
  group('units', () {
    test('times are m:ss, and h:mm:ss from an hour on', () {
      expect(fmtHms(0), '0:00');
      expect(fmtHms(45), '0:45');
      expect(fmtHms(90), '1:30');
      expect(fmtHms(3599), '59:59');
      expect(fmtHms(3600), '1:00:00');
      expect(fmtHms(3723), '1:02:03');
      expect(fmtHms(-5), '0:00');
    });

    test('parseHms reads seconds, m:ss and h:mm:ss', () {
      expect(parseHms('45'), 45);
      expect(parseHms('90'), 90);
      expect(parseHms('1:30'), 90);
      expect(parseHms('0:90'), 90);
      expect(parseHms(' 1:02:03 '), 3723);
      expect(parseHms(''), isNull);
      expect(parseHms('0'), isNull);
      expect(parseHms('0:00'), isNull);
      expect(parseHms('1:'), isNull);
      expect(parseHms('1:2:3:4'), isNull);
      expect(parseHms('1.5'), isNull);
      expect(parseHms('24:00:00'), kMaxSetSeconds);
      expect(parseHms('24:00:01'), isNull);
      for (final s in [1, 59, 60, 754, 3600, 86399]) {
        expect(parseHms(fmtHms(s)), s);
      }
    });

    test('hmsInput puts the colons into typed digits', () {
      expect(hmsInput(''), '');
      expect(hmsInput('5'), '5');
      expect(hmsInput('45'), '45');
      expect(hmsInput('130'), '1:30');
      expect(hmsInput('1:305'), '13:05');
      expect(hmsInput('10203'), '1:02:03');
      expect(hmsInput('1234567'), '12:34:56');
      expect(hmsInput('1:3'), '13');
      expect(parseHms(hmsInput('130')), 90);
    });

    test('the distance unit follows kg or lb and whether there is a load', () {
      expect(DistanceUnit.of(WeightUnit.kg, LoadMode.none), DistanceUnit.km);
      expect(DistanceUnit.of(WeightUnit.kg, LoadMode.added), DistanceUnit.m);
      expect(DistanceUnit.of(WeightUnit.lb, LoadMode.none), DistanceUnit.mi);
      expect(DistanceUnit.of(WeightUnit.lb, LoadMode.added), DistanceUnit.yd);
    });

    test('distances are stored in metres', () {
      expect(parseDistance('5', DistanceUnit.km), 5000);
      expect(parseDistance('0,4', DistanceUnit.km), 400);
      expect(parseDistance('40', DistanceUnit.m), 40);
      expect(parseDistance('1', DistanceUnit.mi), 1609.344);
      expect(parseDistance('100', DistanceUnit.yd), closeTo(91.44, 1e-9));
      expect(parseDistance('', DistanceUnit.km), isNull);
      expect(parseDistance('0', DistanceUnit.km), isNull);
      expect(parseDistance('1001', DistanceUnit.km), isNull);
      expect(fmtDistance(5000, DistanceUnit.km), '5');
      expect(fmtDistance(5250, DistanceUnit.km), '5.25');
      expect(fmtDistance(40, DistanceUnit.m), '40');
      expect(fmtDistance(parseDistance('3.1', DistanceUnit.mi)!, DistanceUnit.mi),
          '3.1');
      expect(fmtDistance(parseDistance('50', DistanceUnit.yd)!, DistanceUnit.yd),
          '50');
    });

    test('pace is time per km, mile, 100 m or 100 yd', () {
      const v = 5000 / 1650; // 5 km in 27:30
      expect(fmtPace(v, DistanceUnit.km), '5:30 /km');
      expect(fmtPace(v, DistanceUnit.mi), '8:51 /mi');
      expect(fmtPace(1, DistanceUnit.m), '1:40 /100 m');
      expect(fmtPace(0.9144, DistanceUnit.yd), '1:40 /100 yd');
      expect(fmtPace(0, DistanceUnit.km), '–');
      expect(speedIn(v, DistanceUnit.km), closeTo(10.909, 1e-3));
      expect(speedIn(v, DistanceUnit.yd), closeTo(6.779, 1e-3));
      expect(DistanceUnit.m.speedLabel, 'km/h');
      expect(DistanceUnit.mi.speedLabel, 'mph');
    });

    test('fmtSet shows time and distance sets', () {
      String f(
        TrackingType type, {
        LoadMode mode = LoadMode.none,
        double? kg,
        int? reps,
        int? secs,
        double? metres,
        WeightUnit unit = WeightUnit.kg,
      }) => fmtSet(
        type: type,
        mode: mode,
        loadKg: kg,
        reps: reps,
        durationSeconds: secs,
        distanceM: metres,
        unit: unit,
      );
      expect(f(time, secs: 90), '1:30');
      expect(f(time), '–');
      expect(f(time, mode: LoadMode.added, kg: 20, secs: 90), '20 $kTimes 1:30');
      expect(f(time, mode: LoadMode.added, kg: 0, secs: 90), '1:30');
      expect(f(dist, metres: 5000), '5 km');
      expect(f(dist, metres: 5000, secs: 1650), '5 km in 27:30');
      expect(f(dist, metres: 5000, unit: WeightUnit.lb), '3.11 mi');
      expect(
        f(dist, mode: LoadMode.added, kg: 40, metres: 30, secs: 25),
        '40 $kTimes 30 m in 0:25',
      );
      expect(
        f(dist, mode: LoadMode.added, kg: 40, metres: 30, unit: WeightUnit.lb),
        '88.18 $kTimes 32.81 yd',
      );
    });

    test('fmtSet keeps sets readable after a change of type', () {
      // Reps logged before the exercise became a time exercise.
      expect(
        fmtSet(
          type: time,
          mode: LoadMode.none,
          loadKg: 80,
          reps: 8,
          unit: WeightUnit.kg,
        ),
        '80 $kTimes 8',
      );
      expect(
        fmtSet(
          type: time,
          mode: LoadMode.none,
          loadKg: null,
          reps: 12,
          unit: WeightUnit.kg,
        ),
        '12 reps',
      );
      // A time logged before the exercise became a weights exercise.
      expect(
        fmtSet(
          type: TrackingType.weights,
          mode: LoadMode.none,
          loadKg: null,
          reps: null,
          durationSeconds: 60,
          unit: WeightUnit.kg,
        ),
        '1:00',
      );
      // Reps types are unchanged.
      expect(
        fmtSet(
          type: TrackingType.weights,
          mode: LoadMode.none,
          loadKg: 80,
          reps: 8,
          unit: WeightUnit.kg,
        ),
        '80 $kTimes 8',
      );
      expect(
        fmtSet(
          type: TrackingType.bodyweight,
          mode: LoadMode.none,
          loadKg: null,
          reps: null,
          unit: WeightUnit.kg,
        ),
        'BW $kTimes –',
      );
    });

    test('load modes and labels per type', () {
      expect(TrackingType.duration.hasReps, isFalse);
      expect(TrackingType.distance.hasReps, isFalse);
      expect(LoadMode.assisted.forType(TrackingType.weights), LoadMode.none);
      expect(
        LoadMode.assisted.forType(TrackingType.bodyweight),
        LoadMode.assisted,
      );
      expect(LoadMode.assisted.forType(time), LoadMode.none);
      expect(LoadMode.added.forType(dist), LoadMode.added);
      expect(exerciseTypeLabel(exercise()), 'Time');
      expect(exerciseTypeLabel(exercise(mode: LoadMode.added)), 'Time + weight');
      expect(exerciseTypeLabel(exercise(type: dist)), 'Distance');
      expect(exerciseSubtitle(exercise(type: dist, mode: LoadMode.added)),
          'Distance + weight');
      expect(matchScore(exercise(type: dist), 'distance'), isNotNull);
      expect(matchScore(exercise(), 'distance'), isNull);
    });
  });

  group('completion', () {
    test('a time exercise needs a time', () {
      final ex = draft([set(1), set(2, secs: 60)], of: exercise());
      expect(ex.completion(0).result, CompleteResult.needsTime);
      expect(ex.completion(0).set, ex.sets[0]);
      final c = ex.completion(1);
      expect(c.result, CompleteResult.ok);
      expect((c.set.durationSeconds, c.set.reps, c.set.loadKg), (60, null, null));
      expect(c.set.isCompleted, isFalse, reason: 'the caller marks it');
    });

    test('an empty time takes last time’s', () {
      final ex = draft(
        [set(1), set(2)],
        of: exercise(mode: LoadMode.added),
        previous: [set(1, secs: 45, kg: 10, done: true)],
      );
      final c = ex.completion(0);
      expect(c.result, CompleteResult.ok);
      expect((c.set.durationSeconds, c.set.loadKg), (45, 10));
      // No previous set for the second one: it copies the set above.
      expect(ex.completion(1).set.durationSeconds, 45);
    });

    test('an extra load left empty is none', () {
      final ex = draft([set(1, secs: 30)], of: exercise(mode: LoadMode.added));
      expect(ex.completion(0).set.loadKg, 0);
      final plain = draft([set(1, secs: 30)], of: exercise());
      expect(plain.completion(0).set.loadKg, isNull);
    });

    test('a distance exercise needs a distance and takes a time if given', () {
      final run = exercise(type: dist);
      final ex = draft(
        [set(1), set(2, secs: 600), set(3, metres: 2000, secs: 600)],
        of: run,
      );
      expect(ex.completion(0).result, CompleteResult.needsDistance);
      expect(ex.completion(1).result, CompleteResult.needsDistance);
      final c = ex.completion(2);
      expect(c.result, CompleteResult.ok);
      expect((c.set.distanceM, c.set.durationSeconds), (2000, 600));

      // The distance is hinted, the optional time never is.
      final again = draft(
        [set(1)],
        of: run,
        previous: [set(1, metres: 5000, secs: 1500, done: true)],
      );
      final hinted = again.completion(0);
      expect(hinted.result, CompleteResult.ok);
      expect((hinted.set.distanceM, hinted.set.durationSeconds), (5000, null));
    });

    test('reps exercises keep their rule', () {
      final weights = exercise(type: TrackingType.weights);
      expect(
        draft([set(1)], of: weights).completion(0).result,
        CompleteResult.needsReps,
      );
      expect(
        draft([set(1, reps: 8)], of: weights).completion(0).result,
        CompleteResult.needsWeight,
      );
      final ok = draft([set(1, reps: 8, kg: 60)], of: weights).completion(0);
      expect((ok.result, ok.set.loadKg, ok.set.reps), (CompleteResult.ok, 60, 8));
      final dip = exercise(type: TrackingType.bodyweight, mode: LoadMode.added);
      final bw = draft([set(1, reps: 8)], of: dip).completion(0);
      expect((bw.result, bw.set.loadKg), (CompleteResult.ok, 0));
      expect(
        draft([set(1)], of: dip).completion(0).result,
        CompleteResult.needsReps,
      );
      // A time on a reps set does not complete it.
      expect(
        draft([set(1, secs: 60)], of: dip).completion(0).result,
        CompleteResult.needsReps,
      );
    });

    test('mark all done counts what completion accepts', () {
      final d = WorkoutDraft(
        workout: Workout(
          id: 1,
          name: 'Workout',
          startedAt: DateTime(2025),
          totalSets: 0,
          totalVolumeKg: 0,
          exerciseCount: 0,
        ),
        exercises: [
          draft([set(1, secs: 30), set(2), set(3, done: true)], of: exercise()),
        ],
      );
      // The second set copies the first one's time.
      expect(d.markableSets, 2);
    });
  });

  group('hints', () {
    test('time hints line up by kind and never give reps', () {
      final ex = draft(
        [set(1, type: SetType.warmup), set(2), set(3), set(4)],
        of: exercise(),
        previous: [
          set(1, secs: 20, type: SetType.warmup, done: true),
          set(2, secs: 60, done: true),
          set(3, secs: 50, done: true),
        ],
        repsMin: 8,
        repsMax: 12,
      );
      expect(ex.timedHintFor(0), (seconds: 20, metres: null));
      expect(ex.timedHintFor(1), (seconds: 60, metres: null));
      expect(ex.timedHintFor(2), (seconds: 50, metres: null));
      expect(ex.timedHintFor(3), (seconds: 50, metres: null), reason: 'above');
      // A stale rep target is ignored, and nothing suggests more weight.
      expect(ex.hintFor(1), (load: null, reps: null, increase: false));
      expect(ex.increaseKg, isNull);
      expect(ex.warmups(barKg: 20), isEmpty);
    });

    test('a typed time above is the hint without a previous session', () {
      final ex = draft([set(1, secs: 75), set(2)], of: exercise());
      expect(ex.timedHintFor(0), (seconds: null, metres: null));
      expect(ex.timedHintFor(1), (seconds: 75, metres: null));
    });

    test('distance hints the distance and the load', () {
      final carry = exercise(type: dist, mode: LoadMode.added);
      final ex = draft(
        [set(1), set(2)],
        of: carry,
        previous: [set(1, kg: 40, metres: 30, secs: 25, done: true)],
      );
      expect(ex.timedHintFor(0), (seconds: null, metres: 30.0));
      expect(ex.timedHintFor(1), (seconds: null, metres: 30.0));
      expect(ex.hintFor(0), (load: 40.0, reps: null, increase: false));
    });

    test('reps exercises have no time hint', () {
      final ex = draft(
        [set(1)],
        of: exercise(type: TrackingType.weights),
        previous: [set(1, kg: 60, reps: 8, secs: 30, done: true)],
      );
      expect(ex.timedHintFor(0), (seconds: null, metres: null));
      expect(ex.hintFor(0), (load: 60.0, reps: 8, increase: false));
    });

    test('focus moves to the field the type needs', () {
      final plank = draft([set(1, secs: 30, done: true), set(2)], of: exercise());
      expect(nextField(plank, 0), (setId: 2, field: SetField.time));
      final run = draft(
        [set(1, metres: 1000, done: true), set(2)],
        of: exercise(type: dist),
      );
      expect(nextField(run, 0), (setId: 2, field: SetField.distance));
      final carry = draft(
        [set(1, metres: 30, kg: 40, done: true), set(2), set(3, kg: 40)],
        of: exercise(type: dist, mode: LoadMode.added),
      );
      expect(nextField(carry, 0), (setId: 2, field: SetField.load));
      expect(nextField(carry.copyWith(sets: [carry.sets[0], carry.sets[2]]), 0),
          (setId: 3, field: SetField.distance));
    });
  });

  group('records', () {
    test('longest time, and the heaviest load when there is one', () {
      final b = bests([
        fact(time, secs: 60),
        fact(time, secs: 90),
        fact(time, secs: 0),
        fact(time, reps: 10, kg: 50),
      ]);
      expect(b.longestTime, 90);
      expect(b.heaviest, isNull);
      expect(b.valueOf(PrKind.longestTime), 90);
      expect(b.e1rm, isNull);
      expect(b.mostReps, isNull);

      final loaded = bests([
        fact(time, secs: 60, kg: 20, mode: LoadMode.added),
        fact(time, secs: 30, kg: 30, mode: LoadMode.added),
        fact(time, secs: 45, kg: 0, mode: LoadMode.added),
      ]);
      expect((loaded.longestTime, loaded.heaviest), (60, 30));

      expect(b.beatenBy(fact(time, secs: 91)), {PrKind.longestTime});
      expect(b.beatenBy(fact(time, secs: 90)), isEmpty);
      expect(ExerciseBests().beatenBy(fact(time, secs: 90)), isEmpty);
    });

    test('longest distance and best pace', () {
      final b = bests([
        fact(dist, metres: 5000, secs: 1500),
        fact(dist, metres: 3000),
      ]);
      expect(b.longestDistance, 5000);
      expect(b.bestPace, closeTo(3.333, 1e-3));
      expect(b.beatenBy(fact(dist, metres: 6000)), {PrKind.longestDistance});
      expect(b.beatenBy(fact(dist, metres: 5000, secs: 1450)), {
        PrKind.bestPace,
      });
      expect(b.beatenBy(fact(dist, metres: 5000, secs: 1500)), isEmpty);
    });

    test('a pace is measured over the same distance or more', () {
      final b = bests([
        fact(dist, metres: 5000, secs: 1500), // 5:00 /km
        fact(dist, metres: 10000, secs: 3300), // 5:30 /km
      ]);
      // Faster than every 10 km, though slower than the 5 km.
      expect(b.beatenBy(fact(dist, metres: 10000, secs: 3200)), {
        PrKind.bestPace,
      });
      // A 5 km must beat the 5 km.
      expect(b.beatenBy(fact(dist, metres: 5000, secs: 1550)), isEmpty);
      // Nearly 5 km counts as 5 km.
      expect(b.beatenBy(fact(dist, metres: 4950, secs: 1400)), {
        PrKind.bestPace,
      });
      // Nothing that long to compare with: only the distance is a record.
      expect(b.beatenBy(fact(dist, metres: 21000, secs: 8000)), {
        PrKind.longestDistance,
      });
      // A sprint is faster than every longer run so far…
      final sprint = fact(dist, metres: 400, secs: 80);
      expect(b.beatenBy(sprint), {PrKind.bestPace});
      // …but doesn't raise the bar for a 5 km.
      b.add(sprint);
      expect(b.bestPace, 5);
      expect(b.paceOver(5000), closeTo(3.333, 1e-3));
      expect(b.beatenBy(fact(dist, metres: 5000, secs: 1490)), {
        PrKind.bestPace,
      });
      expect(b.copy().paceOver(5000), b.paceOver(5000));
    });

    test('computePrs, prHistory and live records agree', () {
      final facts = [
        fact(dist, metres: 5000, secs: 1500),
        fact(dist, metres: 5000, secs: 1450, workoutId: 2),
        fact(dist, metres: 8000, secs: 2600, workoutId: 3),
        fact(dist, metres: 3000, secs: 1000, workoutId: 4),
      ];
      expect(computePrs(facts, 1), isEmpty, reason: 'nothing to beat');
      expect(computePrs(facts, 2), {
        1: {PrKind.bestPace},
      });
      expect(computePrs(facts, 3), {
        1: {PrKind.longestDistance},
      });
      expect(computePrs(facts, 4), isEmpty);
      final history = prHistory(facts);
      expect([for (final e in history) e.workoutId], [3, 2]);
      expect(history[0].values, {PrKind.longestDistance: 8000.0});
      expect(history[1].values.keys, [PrKind.bestPace]);
      expect(history[1].values[PrKind.bestPace], closeTo(5000 / 1450, 1e-9));

      expect(
        liveRecords(bests([facts[0]]), [
          fact(dist, metres: 5000, secs: 1450),
          null,
          fact(dist, metres: 5000, secs: 1460),
          fact(dist, metres: 5200, secs: 1500),
        ]),
        [
          {PrKind.bestPace},
          <PrKind>{},
          <PrKind>{},
          {PrKind.longestDistance, PrKind.bestPace},
        ],
      );
    });

    test('live records of a draft use the time of each set', () {
      final ex = draft(
        [
          set(1, secs: 60, done: true),
          set(2, secs: 95, done: true),
          set(3, secs: 120, done: true, type: SetType.warmup),
          set(4, secs: 200),
        ],
        of: exercise(),
        bests: bests([fact(time, secs: 90)]),
      );
      expect(ex.records(80), {
        2: {PrKind.longestTime},
      });
    });

    test('no volume and no rep maxes', () {
      expect(fact(time, secs: 60, kg: 20, mode: LoadMode.added).volume, 0);
      expect(fact(dist, metres: 1000).volume, 0);
      // Reps left over from another type don't count either.
      expect(fact(time, reps: 10, kg: 50).volume, 0);
      expect(hasRepMaxes(time, LoadMode.added), isFalse);
      expect(hasRepMaxes(dist, LoadMode.none), isFalse);
      expect(hasRepMaxes(TrackingType.bodyweight, LoadMode.added), isTrue);
      expect(repMaxes([fact(time, reps: 5, kg: 50, mode: LoadMode.added)]), isEmpty);
    });
  });

  group('trends', () {
    test('metrics fit the type', () {
      expect(metricsFor(time, LoadMode.none), [
        TrendMetric.time,
        TrendMetric.totalTime,
      ]);
      expect(metricsFor(time, LoadMode.added).last, TrendMetric.heaviest);
      expect(metricsFor(dist, LoadMode.none), [
        TrendMetric.distance,
        TrendMetric.totalDistance,
        TrendMetric.pace,
      ]);
      expect(metricsFor(dist, LoadMode.added).last, TrendMetric.heaviest);
      expect(metricsFor(TrackingType.weights, LoadMode.none), [
        TrendMetric.e1rm,
        TrendMetric.heaviest,
        TrendMetric.volume,
      ]);
    });

    test('metric values of a session', () {
      final holds = [
        fact(time, secs: 60, perSide: true),
        fact(time, secs: 45, perSide: true),
        fact(time),
      ];
      expect(metricValue(TrendMetric.time, holds), 60);
      expect(metricValue(TrendMetric.totalTime, holds), 210);
      expect(metricValue(TrendMetric.heaviest, holds), isNull);
      expect(metricValue(TrendMetric.volume, holds), isNull);
      expect(metricValue(TrendMetric.e1rm, holds), isNull);

      final runs = [
        fact(dist, metres: 5000, secs: 1500),
        fact(dist, metres: 1000, secs: 240),
        fact(dist, metres: 2000),
      ];
      expect(metricValue(TrendMetric.distance, runs), 5000);
      expect(metricValue(TrendMetric.totalDistance, runs), 8000);
      expect(metricValue(TrendMetric.pace, runs), closeTo(4.1667, 1e-3));
      expect(metricValue(TrendMetric.pace, [runs[2]]), isNull);

      final carries = [
        fact(dist, metres: 30, kg: 40, mode: LoadMode.added),
        fact(dist, metres: 30, kg: 50, mode: LoadMode.added),
      ];
      expect(metricValue(TrendMetric.heaviest, carries), 50);

      final series = sessionSeries([
        fact(time, secs: 60),
        fact(time, secs: 75, workoutId: 2),
      ], TrendMetric.time);
      expect([for (final p in series) (p.value, p.isRecord)], [
        (60.0, false),
        (75.0, true),
      ]);
    });

    test('metric formatting', () {
      const kg = WeightUnit.kg;
      const lb = WeightUnit.lb;
      expect(fmtMetric(TrendMetric.time, 90, kg), '1:30');
      expect(fmtMetric(TrendMetric.totalTime, 3700, kg), '1:01:40');
      expect(fmtMetric(TrendMetric.distance, 5000, kg), '5 km');
      expect(fmtMetric(TrendMetric.distance, 5000, lb), '3.11 mi');
      expect(
        fmtMetric(TrendMetric.totalDistance, 90, kg, mode: LoadMode.added),
        '90 m',
      );
      expect(fmtMetric(TrendMetric.pace, 5000 / 1650, kg), '5:30 /km');
      expect(
        fmtMetric(TrendMetric.pace, 1, kg, mode: LoadMode.added),
        '1:40 /100 m',
      );
      expect(fmtMetricDelta(TrendMetric.time, 15, kg), '+0:15');
      expect(fmtMetricDelta(TrendMetric.time, -75, kg), '${kMinus}1:15');
      expect(fmtMetricDelta(TrendMetric.time, 0, kg), '±0:00');
      expect(fmtMetricDelta(TrendMetric.distance, 500, kg), '+0.5 km');
      expect(fmtMetricDelta(TrendMetric.pace, 0.5, kg), '+1.8 km/h');
      expect(fmtMetricDelta(TrendMetric.pace, 0.5, lb), '+1.1 mph');

      expect(metricDisplay(TrendMetric.time, 90, lb), 90);
      expect(metricDisplay(TrendMetric.distance, 5000, kg), 5);
      expect(
        metricDisplay(TrendMetric.distance, 50, kg, mode: LoadMode.added),
        50,
      );
      expect(metricDisplay(TrendMetric.pace, 3, kg), 3);
      expect(metricDisplay(TrendMetric.heaviest, 100, kg), 100);
      expect(fmtMetricAxis(TrendMetric.time, 90, kg), '1:30');
      expect(fmtMetricAxis(TrendMetric.pace, 5000 / 1650, kg), '5:30');
      expect(fmtMetricAxis(TrendMetric.pace, 0, kg), '');
      expect(fmtMetricAxis(TrendMetric.distance, 5, kg), '5');
      expect(fmtMetricAxis(TrendMetric.heaviest, 1200, kg), '1.2K');
    });
  });

  group('editor', () {
    late AppDatabase db;
    late ProviderContainer container;
    late WorkoutRepository repo;
    late ExerciseRepository exercises;
    late Exercise plank;
    late Exercise run;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = WorkoutRepository(db);
      exercises = ExerciseRepository(db);
      plank = await exercises.create(
        name: 'Plank',
        muscleGroup: MuscleGroup.core,
        trackingType: time,
        // Not offered for a time exercise.
        loadMode: LoadMode.assisted,
      );
      run = await exercises.create(
        name: 'Run',
        muscleGroup: MuscleGroup.fullBody,
        trackingType: dist,
      );
      await SettingsRepository(db)
          .write(const AppSettingsCompanion(autoStartRest: Value(false)));
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(
            await SettingsRepository(db).get(),
          ),
        ],
      );
    });
    tearDown(() async {
      container.dispose();
      await pumpEventQueue();
      await db.close();
    });

    Future<(int, WorkoutEditor)> open(List<Exercise> list, {int sets = 2}) async {
      final id = await repo.start();
      for (final (i, e) in list.indexed) {
        await repo.addExercise(id, e.id, position: i, sets: sets);
      }
      container.listen(workoutEditorProvider(id), (_, _) {});
      await container.read(workoutEditorProvider(id).future);
      return (id, container.read(workoutEditorProvider(id).notifier));
    }

    List<DraftExercise> drafts(int id) =>
        container.read(workoutEditorProvider(id)).requireValue.exercises;

    test('an assisted time exercise is stored without a load', () {
      expect(plank.loadMode, LoadMode.none);
    });

    test('✓ and mark all done share one rule', () async {
      final (id, editor) = await open([plank, run]);
      var p = drafts(id)[0];
      var r = drafts(id)[1];
      expect(editor.toggleDone(p.id, p.sets[0].id), CompleteResult.needsTime);
      expect(
        editor.toggleDone(r.id, r.sets[0].id),
        CompleteResult.needsDistance,
      );
      expect(drafts(id).first.sets.first.isCompleted, isFalse);
      expect(editor.markAllDone(), (marked: 0, skipped: 4));

      editor.setDuration(p.id, p.sets[0].id, 60);
      editor.setDistance(r.id, r.sets[0].id, 5000);
      editor.setDuration(r.id, r.sets[0].id, 1500);
      expect(editor.toggleDone(p.id, p.sets[0].id), CompleteResult.ok);
      // The sets below copy the ones above.
      expect(editor.markAllDone(), (marked: 3, skipped: 0));
      p = drafts(id)[0];
      r = drafts(id)[1];
      expect([for (final s in p.sets) s.durationSeconds], [60, 60]);
      expect([for (final s in r.sets) s.distanceM], [5000, 5000]);
      expect([for (final s in r.sets) s.durationSeconds], [1500, null]);
      expect(p.sets[0].completedAt, isNotNull);
      expect(p.sets[1].completedAt, isNull, reason: 'marked, not logged');

      expect(await editor.finish(), isTrue);
      final saved = (await repo.load(id))!;
      expect(saved.workout.totalSets, 4);
      expect(saved.workout.totalVolumeKg, 0);
      final sets = saved.exercises[1].sets;
      expect((sets[0].distanceM, sets[0].durationSeconds, sets[0].reps), (
        5000,
        1500,
        null,
      ));
      // They count as sets for the muscle stats.
      final facts = await repo.setFacts([plank.id, run.id]);
      expect(facts, hasLength(4));
      expect(facts.map((f) => f.volume).toSet(), {0});
      expect(muscleSplit(saved), {MuscleGroup.core: 2, MuscleGroup.fullBody: 2});
    });

    test('previous sets, bests and live badges in the next workout', () async {
      final (first, one) = await open([plank, run], sets: 1);
      var p = drafts(first)[0];
      var r = drafts(first)[1];
      one.setDuration(p.id, p.sets[0].id, 60);
      one.setDistance(r.id, r.sets[0].id, 5000);
      one.setDuration(r.id, r.sets[0].id, 1500);
      one.markAllDone();
      await one.finish();

      final (second, two) = await open([plank, run], sets: 1);
      p = drafts(second)[0];
      r = drafts(second)[1];
      expect(p.previous.single.durationSeconds, 60);
      expect(p.timedHintFor(0).seconds, 60);
      expect(p.bests!.longestTime, 60);
      expect(r.timedHintFor(0), (seconds: null, metres: 5000.0));
      expect(r.bests!.longestDistance, 5000);

      two.setDuration(p.id, p.sets[0].id, 75);
      two.setDuration(r.id, r.sets[0].id, 1450);
      expect(two.toggleDone(p.id, p.sets[0].id), CompleteResult.ok);
      expect(two.toggleDone(r.id, r.sets[0].id), CompleteResult.ok);
      p = drafts(second)[0];
      r = drafts(second)[1];
      expect(p.records(null), {
        p.sets[0].id: {PrKind.longestTime},
      });
      expect(r.records(null), {
        r.sets[0].id: {PrKind.bestPace},
      });
      await two.finish();
      expect(await repo.prsFor(second), {
        plank.id: {PrKind.longestTime},
        run.id: {PrKind.bestPace},
      });
    });

    test('replacing an exercise keeps only what the new one records', () async {
      final bench = await exercises.create(
        name: 'Bench press',
        muscleGroup: MuscleGroup.chest,
        trackingType: TrackingType.weights,
      );
      final (id, editor) = await open([bench], sets: 1);
      var ex = drafts(id).single;
      editor.setLoad(ex.id, ex.sets[0].id, 60);
      editor.setReps(ex.id, ex.sets[0].id, 8);
      editor.toggleDone(ex.id, ex.sets[0].id);

      // Weights to time: no time yet, so the set opens again.
      expect(await editor.replaceExercise(ex.id, plank), isTrue);
      var s = drafts(id).single.sets.single;
      expect((s.loadKg, s.reps, s.isCompleted), (null, null, false));
      editor.setDuration(ex.id, s.id, 60);
      expect(editor.toggleDone(ex.id, s.id), CompleteResult.ok);

      // Time to distance: the time stays, the distance is missing.
      expect(await editor.replaceExercise(ex.id, run), isFalse);
      s = drafts(id).single.sets.single;
      expect((s.durationSeconds, s.distanceM, s.isCompleted), (60, null, false));
      editor.setDistance(ex.id, s.id, 400);
      expect(editor.toggleDone(ex.id, s.id), CompleteResult.ok);

      // Distance to time: done sets stay done with their time.
      expect(await editor.replaceExercise(ex.id, plank), isFalse);
      s = drafts(id).single.sets.single;
      expect((s.durationSeconds, s.distanceM, s.isCompleted), (60, null, true));

      // Back to weights: nothing of it applies.
      expect(await editor.replaceExercise(ex.id, bench), isFalse);
      s = drafts(id).single.sets.single;
      expect((s.durationSeconds, s.reps, s.isCompleted), (null, null, false));
      await pumpEventQueue();
      ex = drafts(id).single;
      final stored = (await repo.load(id))!.exercises.single.sets.single;
      expect(stored.durationSeconds, isNull);
    });

    test('the stopwatch times one set and is dropped with it', () async {
      final (id, editor) = await open([plank]);
      final ex = drafts(id).single;
      final watch = container.read(setStopwatchProvider.notifier);
      expect(watch.stop(ex.sets[0].id), isNull);

      watch.start(
        ex.sets[0].id,
        at: DateTime.now().subtract(const Duration(seconds: 75, milliseconds: 500)),
      );
      expect(watch.stop(ex.sets[1].id), isNull, reason: 'another set');
      expect(watch.stop(ex.sets[0].id), 75);
      expect(container.read(setStopwatchProvider), isNull);

      watch.start(ex.sets[0].id);
      expect(watch.stop(ex.sets[0].id), 1, reason: 'never zero');

      watch.start(ex.sets[1].id);
      final settled = editor.removeSet(ex.id, ex.sets[1].id);
      expect(container.read(setStopwatchProvider), isNull);
      await editor.commitDelete();
      await settled;

      watch.start(ex.sets[0].id);
      await editor.discard();
      expect(container.read(setStopwatchProvider), isNull);
    });

    test('backup v4 round-trips and older files still import', () async {
      final carry = await exercises.create(
        name: 'Farmer carry',
        muscleGroup: MuscleGroup.forearms,
        trackingType: dist,
        loadMode: LoadMode.added,
        equipment: Equipment.kettlebell,
      );
      final (id, editor) = await open([plank, run, carry], sets: 1);
      final d = drafts(id);
      editor.setDuration(d[0].id, d[0].sets[0].id, 90);
      editor.setDistance(d[1].id, d[1].sets[0].id, 5000);
      editor.setDuration(d[1].id, d[1].sets[0].id, 1650);
      editor.setDistance(d[2].id, d[2].sets[0].id, 30);
      editor.setLoad(d[2].id, d[2].sets[0].id, 40);
      editor.markAllDone();
      await editor.finish();

      final backup = BackupService(db);
      final bytes = await backup.export();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      expect(kBackupVersion, 4);
      expect(json['version'], 4);
      expect(
        [
          for (final e in json['exercises']! as List<Object?>)
            (e! as Map<String, Object?>)['trackingType'],
        ],
        ['duration', 'distance', 'distance'],
      );

      Future<List<String>> restored(Uint8List file) async {
        await backup.deleteAll();
        await backup.import(file);
        final all = await db.select(db.exercises).get();
        final byName = {for (final e in all) e.name: e};
        expect(byName['Plank']!.trackingType, time);
        expect(byName['Farmer carry']!.loadMode, LoadMode.added);
        final w = (await repo.watchHistory().first).single;
        final loaded = (await repo.load(w.id))!;
        return [
          for (final e in loaded.exercises)
            fmtSet(
              type: e.exercise.trackingType,
              mode: e.exercise.loadMode,
              loadKg: e.sets.single.loadKg,
              reps: e.sets.single.reps,
              durationSeconds: e.sets.single.durationSeconds,
              distanceM: e.sets.single.distanceM,
              unit: WeightUnit.kg,
            ),
        ];
      }

      const expected = ['1:30', '5 km in 27:30', '40 $kTimes 30 m'];
      expect(await restored(bytes), expected);

      // A file from the next version is refused.
      Uint8List versioned(int v, Map<String, Object?> content) =>
          Uint8List.fromList(utf8.encode(jsonEncode({...content, 'version': v})));
      await expectLater(
        backup.import(versioned(5, json)),
        throwsA(isA<BackupFormatException>()),
      );
      expect(await restored(bytes), expected, reason: 'nothing was replaced');

      // A v3 file has only weights and bodyweight exercises.
      final v3 = {
        ...json,
        'exercises': [
          for (final e in json['exercises']! as List<Object?>)
            {...e! as Map<String, Object?>, 'trackingType': 'bodyweight'},
        ],
      };
      await backup.deleteAll();
      await backup.import(versioned(3, v3));
      final old = await db.select(db.exercises).get();
      expect({for (final e in old) e.trackingType}, {TrackingType.bodyweight});
      final w = (await repo.watchHistory().first).single;
      final sets = [
        for (final e in (await repo.load(w.id))!.exercises) e.sets.single,
      ];
      expect([for (final s in sets) s.durationSeconds], [90, 1650, null]);
      expect([for (final s in sets) s.distanceM], [null, 5000, 30]);
    });
  });

  group('set rows', () {
    final plank = draft(
      [
        set(1, secs: 20, done: true, type: SetType.warmup),
        set(2, secs: 3723, kg: 102.5, done: true, rpe: 9.5, note: 'Shaky'),
        set(3),
      ],
      of: exercise(mode: LoadMode.added),
      previous: [set(1, secs: 20, type: SetType.warmup), set(2, secs: 754, kg: 100)],
    );
    final hold = draft(
      [set(1, secs: 45, done: true), set(2)],
      of: exercise(),
      previous: [set(1, secs: 40)],
    );
    final carry = draft(
      [
        set(1, metres: 30, kg: 102.5, secs: 3723, done: true, rpe: 9.5),
        set(2),
      ],
      of: exercise(type: dist, mode: LoadMode.added),
      previous: [set(1, metres: 30, kg: 100, secs: 25)],
    );
    final run = draft(
      [set(1, metres: 5250, secs: 1650, done: true, note: 'Windy'), set(2)],
      of: exercise(type: dist),
      previous: [set(1, metres: 5000, secs: 1500)],
    );

    Widget host(double width, double scale, Widget child) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                // The card sits inside the list's Space.md padding.
                width: width - 24,
                child: SingleChildScrollView(child: child),
              ),
            ),
          ),
        ),
      ),
    );

    Widget rows(DraftExercise ex, EffortMode effort, {WeightUnit? unit}) => Column(
      children: [
        SetHeader(exercise: ex, unit: unit ?? WeightUnit.kg, effort: effort),
        for (var i = 0; i < ex.sets.length; i++)
          SetRow(
            workoutId: 1,
            exercise: ex,
            index: i,
            unit: unit ?? WeightUnit.kg,
            effort: effort,
            records: i == 1 ? const {PrKind.longestTime} : const {},
          ),
      ],
    );

    test('SetCols.fit shares the width with the new columns', () {
      for (final scale in [1.0, 2.0]) {
        for (final effort in [false, true]) {
          final d = SetCols.fit(
            296,
            textScale: scale,
            load: true,
            effort: effort,
            distance: true,
          );
          final gaps = (effort ? 4 : 3) * SetCols.gap;
          expect(
            d.set +
                d.previous +
                d.load +
                d.distance +
                d.reps +
                (effort ? d.effort : 0) +
                SetCols.check +
                gaps,
            closeTo(296, 1e-9),
          );
          expect(d.inputScale, greaterThanOrEqualTo(SetCols.minDistanceScale));

          final t = SetCols.fit(
            296,
            textScale: scale,
            load: true,
            effort: effort,
            timer: true,
          );
          expect(
            t.set +
                t.previous +
                t.load +
                t.reps +
                SetCols.timer +
                (effort ? t.effort : 0) +
                SetCols.check +
                gaps,
            closeTo(296, 1e-9),
          );
          expect(t.inputScale, greaterThanOrEqualTo(1));
        }
      }
      // Reps rows are laid out as before.
      final w = SetCols.fit(336, textScale: 1, load: true);
      expect((w.load, w.reps, w.inputScale), (76, 64, 1));
    });

    for (final effort in [EffortMode.off, EffortMode.rpe]) {
      for (final scale in [1.0, 2.0]) {
        final name = '320 dp, $scale$kTimes, effort ${effort.name}';

        testWidgets('time rows fit at $name', (tester) async {
          await tester.pumpWidget(
            host(320, scale, Column(children: [rows(plank, effort), rows(hold, effort)])),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('TIME'), findsNWidgets(2));
          expect(find.text('REPS'), findsNothing);
          expect(find.text('KG'), findsOneWidget);
          expect(find.text('W'), findsOneWidget);
          expect(find.text('Shaky'), findsOneWidget);
          expect(find.text('Longest time'), findsNWidgets(2));
          expect(find.text('1:02:03'), findsNWidgets(2));
          expect(find.text('0:45'), findsNWidgets(2));
          // Open sets offer the stopwatch, done ones don't.
          expect(find.byTooltip('Start timer'), findsNWidgets(2));
          // Load and time, plus effort, for the loaded rows; time for the others.
          final loaded = effort == EffortMode.off ? 2 : 3;
          final plain = effort == EffortMode.off ? 1 : 2;
          expect(
            find.byType(TextField),
            findsNWidgets(3 * loaded + 2 * plain),
          );
          expect(
            find.text('9.5'),
            effort == EffortMode.rpe ? findsOneWidget : findsNothing,
          );
          // Last time's values are the placeholders of the open sets.
          final hints = [
            for (final f in tester.widgetList<TextField>(find.byType(TextField)))
              ?f.decoration?.hintText,
          ];
          expect(hints, containsAll(['12:34', '100', '0:40']));
        });

        testWidgets('distance rows fit at $name', (tester) async {
          await tester.pumpWidget(
            host(320, scale, Column(children: [rows(carry, effort), rows(run, effort)])),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('TIME'), findsNWidgets(2));
          expect(find.text('M'), findsOneWidget);
          expect(find.text('KM'), findsOneWidget);
          expect(find.text('KG'), findsOneWidget);
          expect(find.text('REPS'), findsNothing);
          expect(find.text('Windy'), findsOneWidget);
          expect(find.byTooltip('Start timer'), findsNothing);
          expect(find.text('5.25'), findsNWidgets(2));
          expect(find.text('27:30'), findsOneWidget);
          final e = effort == EffortMode.off ? 0 : 1;
          expect(find.byType(TextField), findsNWidgets(2 * (3 + e) + 2 * (2 + e)));
          final hints = [
            for (final f in tester.widgetList<TextField>(find.byType(TextField)))
              ?f.decoration?.hintText,
          ];
          // The distance and load are hinted, the optional time is not.
          expect(hints, containsAll(['30', '100', '5']));
          expect(hints, isNot(contains('25:00')));
          expect(hints, isNot(contains('0:25')));
        });
      }
    }

    testWidgets('lb shows yards and miles', (tester) async {
      await tester.pumpWidget(
        host(
          360,
          1,
          Column(
            children: [
              rows(carry, EffortMode.off, unit: WeightUnit.lb),
              rows(run, EffortMode.off, unit: WeightUnit.lb),
            ],
          ),
        ),
      );
      expect(find.text('YD'), findsOneWidget);
      expect(find.text('MI'), findsOneWidget);
      expect(find.text('LB'), findsOneWidget);
      expect(find.text('3.26'), findsNWidgets(2));
    });

    testWidgets('set lists show time and distance sets', (tester) async {
      await tester.pumpWidget(
        host(
          320,
          2,
          Column(
            children: [
              SetList(
                exercise: plank.exercise,
                sets: plank.sets.take(2).toList(),
                unit: WeightUnit.kg,
                effort: EffortMode.rpe,
              ),
              SetList(
                exercise: run.exercise,
                sets: run.sets.take(1).toList(),
                unit: WeightUnit.kg,
                effort: EffortMode.off,
                compact: true,
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('102.5 $kTimes 1:02:03'), findsOneWidget);
      expect(find.textContaining('5.25 km in 27:30'), findsOneWidget);
    });
  });

  testWidgets('the exercise editor offers what a time exercise can have', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showExerciseEditor(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Load'), findsNothing);
    await tester.ensureVisible(find.text('Time'));
    await tester.tap(find.text('Time'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(ChoiceChip, 'No weight'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Extra weight'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Assisted'), findsNothing);
    expect(find.textContaining('Time is logged for one side'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Dumbbell'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dumbbell'));
    await tester.pumpAndSettle();
    expect(find.text('Per dumbbell'), findsNothing);
  });

  testWidgets('logging a plank with the keyboard and the stopwatch', (
    tester,
  ) async {
    late AppDatabase db;
    late WorkoutRepository repo;
    late UserSettings settings;
    late int id;
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = WorkoutRepository(db);
      final plank = await ExerciseRepository(db).create(
        name: 'Plank',
        muscleGroup: MuscleGroup.core,
        trackingType: time,
      );
      await SettingsRepository(db)
          .write(const AppSettingsCompanion(autoStartRest: Value(false)));
      settings = await SettingsRepository(db).get();
      id = await repo.start();
      await repo.addExercise(id, plank.id, position: 0, sets: 3);
    });
    addTearDown(() => db.close());
    Future<void> settle() async {
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(settings),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: WorkoutScreen(workoutId: id),
        ),
      ),
    );
    await settle();
    expect(find.text('TIME'), findsOneWidget);
    // Nothing that only fits reps and weights.
    expect(find.text('Warm-up sets'), findsNothing);
    expect(find.textContaining('Target'), findsNothing);

    // ✓ with nothing to use asks for the time.
    await tester.tap(find.byTooltip('Complete set').first);
    await settle();
    expect(find.text('0 / 3 sets · 0 min'), findsOneWidget);
    final fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.first).focusNode!.hasFocus, isTrue);

    // Typed digits get their colon, and Done completes the set.
    await tester.enterText(fields.first, '130');
    expect(tester.widget<TextField>(fields.first).controller!.text, '1:30');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle();
    expect(find.text('1 / 3 sets · 0 min'), findsOneWidget);
    // The next set takes the focus and shows the time above as its hint.
    expect(tester.widget<TextField>(fields.at(1)).focusNode!.hasFocus, isTrue);
    expect(tester.widget<TextField>(fields.at(1)).decoration!.hintText, '1:30');

    // The stopwatch runs in place of the field and completes the set.
    await tester.tap(find.byTooltip('Start timer').first);
    await tester.pump();
    expect(find.byTooltip('Stop timer'), findsOneWidget);
    expect(find.byTooltip('Start timer'), findsOneWidget, reason: 'third set');
    expect(find.text('0:00'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.tap(find.byTooltip('Stop timer'));
    await settle();
    expect(find.byTooltip('Stop timer'), findsNothing);
    expect(find.text('2 / 3 sets · 0 min'), findsOneWidget);

    late List<WorkoutSet> stored;
    await tester.runAsync(() async {
      await pumpEventQueue();
      stored = (await repo.load(id))!.exercises.single.sets;
    });
    expect([for (final s in stored) s.isCompleted], [true, true, false]);
    expect(stored[0].durationSeconds, 90);
    expect(stored[1].durationSeconds, 1);
    expect(stored.map((s) => s.reps).toSet(), {null});

    await tester.pumpWidget(const SizedBox());
    await settle();
  });
}
