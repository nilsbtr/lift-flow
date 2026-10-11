import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/backup_service.dart';
import 'package:lift_flow/data/bodyweight_repository.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/exercise_repository.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/data/template_repository.dart';
import 'package:lift_flow/data/workout_repository.dart';
import 'package:lift_flow/domain/exercise_search.dart';
import 'package:lift_flow/domain/history.dart';
import 'package:lift_flow/domain/muscles.dart';
import 'package:lift_flow/domain/records.dart';
import 'package:lift_flow/domain/rest.dart';
import 'package:lift_flow/domain/stats.dart';
import 'package:lift_flow/domain/units.dart';
import 'package:lift_flow/providers.dart';
import 'package:lift_flow/services/notifications.dart';
import 'package:lift_flow/widgets/common.dart';

void main() {
  group('units', () {
    test('parseNumber accepts comma decimals', () {
      expect(parseNumber('82,5'), 82.5);
      expect(parseNumber(' '), isNull);
    });

    test('parseRepsRange', () {
      expect(parseRepsRange('8-12'), (min: 8, max: 12));
      expect(parseRepsRange('8'), (min: 8, max: null));
      expect(parseRepsRange(''), (min: null, max: null));
      expect(parseRepsRange('12-8'), isNull);
      expect(parseRepsRange('abc'), isNull);
    });

    test('fmtLoad for bodyweight modes', () {
      String f(LoadMode m, double? kg) => fmtLoad(
        type: TrackingType.bodyweight,
        mode: m,
        loadKg: kg,
        unit: WeightUnit.kg,
      );
      expect(f(LoadMode.none, null), 'BW');
      expect(f(LoadMode.added, 10), '+10');
      expect(f(LoadMode.assisted, -20), '${kMinus}20');
    });

    test('fmtClock / fmtDuration', () {
      expect(fmtClock(95), '1:35');
      expect(fmtDuration(const Duration(minutes: 65)), '1 h 5 min');
    });
  });

  test('estimateOneRm', () {
    expect(estimateOneRm(100, 1), 100);
    expect(estimateOneRm(100, 10), closeTo(133.3, 0.1));
  });

  test('setVolume counts per-side reps and per-dumbbell load twice', () {
    double v({
      TrackingType type = TrackingType.weights,
      double? load = 20,
      double? bodyweight,
      bool perSide = false,
      bool perDumbbell = false,
    }) => setVolume(
      type: type,
      loadKg: load,
      reps: 10,
      bodyweightKg: bodyweight,
      perSide: perSide,
      perDumbbell: perDumbbell,
    );
    expect(v(), 200);
    expect(v(perSide: true), 400);
    expect(v(perDumbbell: true), 400);
    expect(v(perSide: true, perDumbbell: true), 800);
    // Only the external load doubles, and assistance never does.
    const bw = TrackingType.bodyweight;
    expect(v(type: bw, load: 10, bodyweight: 80, perDumbbell: true), 1000);
    expect(v(type: bw, load: -20, bodyweight: 80, perDumbbell: true), 600);
    expect(v(type: bw, load: null, bodyweight: 80, perSide: true), 1600);
  });

  test('refineMuscleGroup remaps legacy groups by name', () {
    MuscleGroup arms(String n) => refineMuscleGroup(n, MuscleGroup.arms);
    MuscleGroup legs(String n) => refineMuscleGroup(n, MuscleGroup.legs);
    expect(arms('Barbell curl'), MuscleGroup.biceps);
    expect(arms('Hammer Curls'), MuscleGroup.biceps);
    expect(arms('Wrist curl'), MuscleGroup.forearms);
    expect(arms('Triceps push-down'), MuscleGroup.triceps);
    expect(arms('Skull crushers'), MuscleGroup.triceps);
    expect(arms('Close-grip bench press'), MuscleGroup.arms);
    expect(arms('Dips'), MuscleGroup.arms);
    expect(legs('Back squat'), MuscleGroup.quads);
    expect(legs('Leg press'), MuscleGroup.quads);
    expect(legs('Leg extension'), MuscleGroup.quads);
    expect(legs('Walking lunges'), MuscleGroup.quads);
    expect(legs('Seated leg curl'), MuscleGroup.hamstrings);
    expect(legs('Romanian deadlift'), MuscleGroup.hamstrings);
    expect(legs('Stiff-legged deadlift'), MuscleGroup.hamstrings);
    expect(legs('Single-leg RDL'), MuscleGroup.hamstrings);
    expect(legs('Glute ham raise'), MuscleGroup.hamstrings);
    expect(legs('Hip thrust'), MuscleGroup.glutes);
    expect(legs('Glute bridge'), MuscleGroup.glutes);
    expect(legs('Standing calf raise'), MuscleGroup.calves);
    expect(legs('Deadlift'), MuscleGroup.legs);
    expect(legs('Hurdle hops'), MuscleGroup.legs);
    // Other groups are never touched.
    expect(refineMuscleGroup('Leg curl', MuscleGroup.other), MuscleGroup.other);
    expect(refineMuscleGroup('Squat', MuscleGroup.arms), MuscleGroup.arms);
  });

  test('muscle group pickers hide legacy groups unless in use', () {
    expect(MuscleGroup.selectable, isNot(contains(MuscleGroup.arms)));
    expect(MuscleGroup.selectable, isNot(contains(MuscleGroup.legs)));
    expect(MuscleGroup.selectableWith(const []), MuscleGroup.selectable);
    final withLegs = MuscleGroup.selectableWith([MuscleGroup.legs]);
    expect(withLegs, contains(MuscleGroup.legs));
    expect(withLegs, isNot(contains(MuscleGroup.arms)));
  });

  test('setLabels numbers every set but warm-ups', () {
    expect(
      setLabels([
        SetType.warmup,
        SetType.normal,
        SetType.drop,
        SetType.failure,
        SetType.amrap,
      ]),
      ['W', '1', '2', '3', '4'],
    );
    expect([for (final t in SetType.values) t.letter], ['', 'W', 'D', 'F', 'A']);
  });

  group('adjustRest', () {
    final now = DateTime(2025, 1, 1, 12);
    DateTime at(int seconds) => now.add(Duration(seconds: seconds));

    test('moves the end and the total', () {
      final r = adjustRest(at(40), 60, 30, now)!;
      expect(r.endsAt, at(70));
      expect(r.totalSeconds, 90);
    });

    test('is over when nothing is left', () {
      expect(adjustRest(at(10), 60, -15, now), isNull);
      expect(adjustRest(at(15), 60, -15, now), isNull);
    });

    test('keeps the total at or above the time left', () {
      expect(adjustRest(at(60), 60, -15, now)!.totalSeconds, 60);
    });

    test('caps the end at an hour', () {
      final r = adjustRest(at(3590), 3600, 30, now)!;
      expect(r.endsAt, at(kMaxRestSeconds));
      expect(r.totalSeconds, kMaxRestSeconds);
    });
  });

  group('exercise search', () {
    Exercise ex(
      int id,
      String name, {
      MuscleGroup group = MuscleGroup.chest,
      Equipment equipment = Equipment.none,
      TrackingType type = TrackingType.weights,
      List<MuscleGroup> secondary = const [],
    }) => Exercise(
      id: id,
      name: name,
      muscleGroup: group,
      trackingType: type,
      loadMode: LoadMode.none,
      isArchived: false,
      createdAt: DateTime(2025),
      equipment: equipment,
      perSide: false,
      perDumbbell: false,
      secondaryMuscles: secondary,
    );

    final library = [
      ex(1, 'Bench press', equipment: Equipment.barbell),
      ex(2, 'Dumbbell bench press', equipment: Equipment.dumbbell),
      ex(3, 'Incline press', equipment: Equipment.dumbbell),
      ex(4, 'Overhead press', group: MuscleGroup.shoulders),
      ex(5, 'Romanian deadlift', group: MuscleGroup.hamstrings),
      ex(6, 'Deadlift', group: MuscleGroup.back),
      ex(7, 'Hammer curls', group: MuscleGroup.biceps),
      ex(
        8,
        'Pull-up',
        group: MuscleGroup.back,
        type: TrackingType.bodyweight,
        secondary: [MuscleGroup.biceps],
      ),
    ];

    List<int> find(String q, {MuscleGroup? group, List<Exercise>? from}) => [
      for (final e in rankExercises(from ?? library, query: q, group: group).exercises)
        e.id,
    ];

    test('words match in any order and by prefix', () {
      expect(find('press bench'), [1, 2]);
      expect(find('inc pr'), [3]);
      expect(find('curl'), [7]);
      expect(find('xyz'), isEmpty);
    });

    test('abbreviations expand', () {
      expect(find('db bench'), [2]);
      expect(find('bb bench'), [1]);
      expect(find('ohp'), [4]);
      expect(find('rdl'), [5]);
      expect(find('dl'), [6, 5]);
    });

    test('equipment, muscle and secondary muscles can match', () {
      expect(find('barbell'), [1]);
      expect(find('hamstrings'), [5]);
      expect(find('bicep'), [7, 8]);
      expect(find('bodyweight'), [8]);
    });

    test('name matches outrank equipment matches', () {
      final l = [
        ex(1, 'Cable row', group: MuscleGroup.back),
        ex(2, 'Row', equipment: Equipment.dumbbell, group: MuscleGroup.back),
        ex(3, 'Dumbbell press', equipment: Equipment.dumbbell),
      ];
      expect(find('dumbbell', from: l), [3, 2]);
    });

    test('the group filter limits the list', () {
      expect(find('', group: MuscleGroup.back), [6, 8]);
      expect(find('dead', group: MuscleGroup.back), [6]);
    });

    test('no query puts recent and frequent first, then A to Z', () {
      final now = DateTime(2025, 6, 1);
      final usage = {
        8: ExerciseUsage(2, DateTime(2025, 5, 30)),
        6: ExerciseUsage(30, DateTime(2024, 6, 1)),
        1: ExerciseUsage(10, DateTime(2025, 5, 20)),
      };
      final r = rankExercises(library, usage: usage, now: now);
      expect(r.recent, 3);
      expect([for (final e in r.exercises) e.id].take(3), [1, 8, 6]);
      expect([for (final e in r.exercises.skip(3)) e.name], [
        'Dumbbell bench press',
        'Hammer curls',
        'Incline press',
        'Overhead press',
        'Romanian deadlift',
      ]);
      expect(rankExercises(library, now: now).recent, 0);
    });

    test('usage breaks ties between equal matches', () {
      final usage = {4: ExerciseUsage(5, DateTime.now())};
      final r = rankExercises(library, query: 'press', usage: usage);
      expect(r.exercises.first.id, 4);
      expect(r.recent, 0);
    });
  });

  group('rep maxes', () {
    SetFact fact(
      int workout,
      int day,
      double? kg,
      int? reps, {
      TrackingType type = TrackingType.weights,
      LoadMode mode = LoadMode.none,
    }) => SetFact(
      workoutId: workout,
      startedAt: DateTime(2025, 1, day),
      exerciseId: 1,
      type: type,
      mode: mode,
      loadKg: kg,
      reps: reps,
      bodyweightKg: 80,
    );

    test('best load per exact rep count, first date wins ties', () {
      final r = repMaxes([
        fact(3, 20, 100, 5),
        fact(1, 1, 100, 5),
        fact(2, 10, 90, 5),
        fact(2, 10, 120, 1),
        fact(2, 10, 60, 12),
        fact(2, 10, 50, 13),
        fact(2, 10, null, 5),
        fact(2, 10, 70, null),
        fact(2, 10, 0, 8),
      ]);
      expect([for (final m in r) m.reps], [1, 5, 12]);
      expect([for (final m in r) m.loadKg], [120, 100, 60]);
      expect(r[1].date, DateTime(2025, 1, 1));
      expect(r[1].workoutId, 1);
    });

    test('bodyweight modes use the signed load', () {
      const bw = TrackingType.bodyweight;
      final added = repMaxes([
        fact(1, 1, 0, 8, type: bw, mode: LoadMode.added),
        fact(1, 1, 10, 8, type: bw, mode: LoadMode.added),
        fact(1, 1, null, 3, type: bw, mode: LoadMode.added),
      ]);
      expect([for (final m in added) (m.reps, m.loadKg)], [(3, 0.0), (8, 10.0)]);
      // Less assistance is better.
      final assisted = repMaxes([
        fact(1, 1, -30, 5, type: bw, mode: LoadMode.assisted),
        fact(2, 2, -20, 5, type: bw, mode: LoadMode.assisted),
      ]);
      expect(assisted.single.loadKg, -20);
      // Bodyweight only has nothing to compare.
      expect(hasRepMaxes(bw, LoadMode.none), isFalse);
      expect(hasRepMaxes(bw, LoadMode.assisted), isTrue);
      expect(repMaxes([fact(1, 1, null, 10, type: bw)]), isEmpty);
    });

    test('warm-ups never count', () {
      final squat = Exercise(
        id: 1,
        name: 'Squat',
        muscleGroup: MuscleGroup.quads,
        trackingType: TrackingType.weights,
        loadMode: LoadMode.none,
        isArchived: false,
        createdAt: DateTime(2025),
        equipment: Equipment.barbell,
        perSide: false,
        perDumbbell: false,
        secondaryMuscles: const [],
      );
      final workout = Workout(
        id: 1,
        name: 'Legs',
        startedAt: DateTime(2025, 1, 1),
        totalSets: 2,
        totalVolumeKg: 0,
        exerciseCount: 1,
      );
      WorkoutSet set(int id, double kg, SetType type) => WorkoutSet(
        id: id,
        workoutExerciseId: 1,
        position: id,
        loadKg: kg,
        reps: 5,
        isCompleted: true,
        setType: type,
      );
      final r = repMaxes(
        sessionFacts(squat, [
          ExerciseSession(workout, [
            set(1, 200, SetType.warmup),
            set(2, 100, SetType.normal),
          ]),
        ]),
      );
      expect(r.single.loadKg, 100);
    });
  });

  group('database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('finish drops unchecked sets and summarises', () async {
      final ex = await ExerciseRepository(db).create(
        name: 'Bench press',
        muscleGroup: MuscleGroup.chest,
        trackingType: TrackingType.weights,
      );
      final repo = WorkoutRepository(db);
      final id = await repo.start();
      final (_, sets) = await repo.addExercise(id, ex.id, position: 0, sets: 3);
      await repo.writeSets([
        sets[0].copyWith(
          loadKg: const Value(80),
          reps: const Value(8),
          isCompleted: true,
        ),
        sets[1].copyWith(
          loadKg: const Value(80),
          reps: const Value(6),
          isCompleted: true,
        ),
      ]);

      expect(await repo.finish(id, bodyweightKg: null), isTrue);
      final w = (await repo.load(id))!;
      expect(w.workout.endedAt, isNotNull);
      expect(w.workout.totalSets, 2);
      expect(w.workout.totalVolumeKg, 80 * 14);
      expect(w.exercises.single.sets, hasLength(2));
    });

    test('finish with nothing logged deletes the workout', () async {
      final repo = WorkoutRepository(db);
      final id = await repo.start();
      expect(await repo.finish(id, bodyweightKg: null), isFalse);
      expect(await repo.load(id), isNull);
    });

    test('backup round-trip', () async {
      final ex = await ExerciseRepository(db).create(
        name: 'Pull-up',
        muscleGroup: MuscleGroup.back,
        trackingType: TrackingType.bodyweight,
        loadMode: LoadMode.added,
      );
      final repo = WorkoutRepository(db);
      final id = await repo.start();
      final (_, sets) = await repo.addExercise(id, ex.id, position: 0);
      await repo.writeSets([
        sets[0].copyWith(
          loadKg: const Value(10),
          reps: const Value(5),
          isCompleted: true,
        ),
      ]);
      await repo.finish(id, bodyweightKg: 80);

      final backup = BackupService(db);
      final bytes = await backup.export();
      await backup.deleteAll();
      expect(await db.select(db.exercises).get(), isEmpty);

      await backup.import(bytes);
      final restored = (await repo.load(id))!;
      expect(restored.exercises.single.exercise.name, 'Pull-up');
      expect(restored.exercises.single.sets.single.loadKg, 10);
      expect(restored.workout.bodyweightKg, 80);
    });

    test('import rejects invalid data', () async {
      final bad = Uint8List.fromList('{"app":"other","version":1}'.codeUnits);
      expect(() => parseBackup(bad), throwsA(isA<BackupFormatException>()));
    });

    Future<(WorkoutRepository, int, List<WorkoutSet>)> bench({
      int sets = 3,
    }) async {
      final ex = await ExerciseRepository(db).create(
        name: 'Bench press',
        muscleGroup: MuscleGroup.chest,
        trackingType: TrackingType.weights,
      );
      final repo = WorkoutRepository(db);
      final id = await repo.start();
      final (_, created) = await repo.addExercise(
        id,
        ex.id,
        position: 0,
        sets: sets,
      );
      return (repo, id, created);
    }

    WorkoutSet done(WorkoutSet s, double kg, int reps, {bool warmup = false}) =>
        s.copyWith(
          loadKg: Value(kg),
          reps: Value(reps),
          isCompleted: true,
          setType: warmup ? SetType.warmup : SetType.normal,
        );

    test('warm-ups are kept but excluded from totals and facts', () async {
      final (repo, id, sets) = await bench();
      await repo.writeSets([
        done(sets[0], 40, 10, warmup: true),
        done(sets[1], 80, 8),
        done(sets[2], 80, 6),
      ]);
      expect(await repo.finish(id, bodyweightKg: null), isTrue);
      final w = (await repo.load(id))!;
      expect(w.workout.totalSets, 2);
      expect(w.workout.totalVolumeKg, 80 * 14);
      expect(w.exercises.single.sets, hasLength(3));
      expect(w.exercises.single.sets.first.setType, SetType.warmup);

      final facts = await repo.setFacts([w.exercises.single.exercise.id]);
      expect(facts, hasLength(2));
      expect(facts.every((f) => f.loadKg == 80), isTrue);
      expect(facts.first.muscleGroup, MuscleGroup.chest);
    });

    test('a workout with only warm-ups is kept', () async {
      final (repo, id, sets) = await bench(sets: 1);
      await repo.writeSets([done(sets[0], 40, 10, warmup: true)]);
      expect(await repo.finish(id, bodyweightKg: null), isTrue);
      final w = (await repo.load(id))!;
      expect(w.workout.totalSets, 0);
      expect(w.exercises.single.sets, hasLength(1));
    });

    test('starting a template mirrors the last session’s warm-ups', () async {
      final (repo, id, sets) = await bench();
      await repo.writeSets([
        done(sets[0], 40, 10, warmup: true),
        done(sets[1], 80, 8),
        done(sets[2], 80, 6),
      ]);
      await repo.finish(id, bodyweightKg: null);
      final ex = (await repo.load(id))!.exercises.single.exercise;
      final tid = await TemplateRepository(db).save(
        name: 'Push',
        items: [TemplateItem(exercise: ex, targetSets: 4)],
      );

      final next = (await repo.load(await repo.start(templateId: tid)))!;
      expect(
        [for (final s in next.exercises.single.sets) s.setType.isWarmup],
        [true, false, false, false],
      );
    });

    test('a past workout can be logged during a live one', () async {
      final (repo, live, _) = await bench(sets: 1);
      final start = DateTime(2026, 10, 3, 18);
      final end = DateTime(2026, 10, 3, 19, 15);
      final id = await repo.createPast(start, end, bodyweightKg: 80);
      expect((await repo.getLive())!.id, live);

      final ex = (await repo.load(live))!.exercises.single.exercise;
      final (_, sets) = await repo.addExercise(id, ex.id, position: 0, sets: 2);
      await repo.writeSets([done(sets[0], 60, 10)]);
      expect(
        await repo.finish(id, bodyweightKg: 80, keepEndedAt: true),
        isTrue,
      );

      final w = (await repo.load(id))!.workout;
      expect((w.startedAt, w.endedAt, w.totalSets), (start, end, 1));
      expect((await repo.watchHistory().first).map((x) => x.id), [id]);
    });

    test('abandoned past workouts are purged, logged ones are kept', () async {
      final (repo, live, liveSets) = await bench(sets: 1);
      await repo.writeSets([done(liveSets[0], 50, 5)]);
      final ex = (await repo.load(live))!.exercises.single.exercise;
      final empty = await repo.createPast(
        DateTime(2026, 10, 1, 9),
        DateTime(2026, 10, 1, 10),
      );
      final kept = await repo.createPast(
        DateTime(2026, 10, 2, 9),
        DateTime(2026, 10, 2, 10),
      );
      final (_, sets) = await repo.addExercise(kept, ex.id, position: 0);
      await repo.writeSets([done(sets[0], 60, 10)]);
      await repo.finish(kept, bodyweightKg: null, keepEndedAt: true);

      // The next log clears the empty one, not the live or finished ones.
      final next = await repo.createPast(
        DateTime(2026, 10, 3, 9),
        DateTime(2026, 10, 3, 10),
      );
      expect(await repo.load(empty), isNull);
      expect(await repo.load(kept), isNotNull);
      expect(await repo.load(live), isNotNull);
      expect(await repo.purgeEmpty(), 1);
      expect(await repo.load(next), isNull);

      // A saved workout is never purged, even if edits unchecked every set.
      await repo.writeSets([done(sets[0], 60, 10).copyWith(isCompleted: false)]);
      expect(await repo.purgeEmpty(), 0);
      expect(await repo.load(kept), isNotNull);
    });

    test('setTimes moves a workout and finishing keeps the end', () async {
      final (repo, id, sets) = await bench(sets: 1);
      await repo.writeSets([done(sets[0], 60, 10)]);
      await repo.finish(id, bodyweightKg: null);
      final start = DateTime(2026, 9, 1, 7);
      final end = DateTime(2026, 9, 1, 8, 30);
      await repo.setTimes(id, start, end);
      final w = (await repo.load(id))!.workout;
      expect((w.startedAt, w.endedAt), (start, end));

      await repo.finish(id, bodyweightKg: null, keepEndedAt: true);
      expect((await repo.load(id))!.workout.endedAt, end);
    });

    test('do again copies exercises, sets and targets', () async {
      final exercises = ExerciseRepository(db);
      final a = await exercises.create(
        name: 'Bench press',
        muscleGroup: MuscleGroup.chest,
        trackingType: TrackingType.weights,
      );
      final b = await exercises.create(
        name: 'Row',
        muscleGroup: MuscleGroup.back,
        trackingType: TrackingType.weights,
      );
      final repo = WorkoutRepository(db);
      final tid = await TemplateRepository(db).save(
        name: 'Upper',
        items: [
          TemplateItem(exercise: a, targetSets: 3, restSeconds: 90),
          TemplateItem(exercise: b, targetSets: 2, supersetGroup: 1),
        ],
      );
      final first = await repo.start(templateId: tid);
      await repo.writeSets([
        for (final e in (await repo.load(first))!.exercises)
          for (final s in e.sets) done(s, 60, 8),
      ]);
      await repo.finish(first, bodyweightKg: null);

      final source = (await repo.load(first))!.workout;
      final items = await TemplateRepository(db).itemsFromWorkout(first);
      final id = await repo.start(
        templateId: source.templateId,
        name: source.name,
        items: items,
      );
      final again = (await repo.load(id))!;
      expect(again.workout.endedAt, isNull);
      expect(again.workout.name, 'Upper');
      expect(again.workout.templateId, tid);
      expect(again.exercises.map((e) => e.exercise.name), [
        'Bench press',
        'Row',
      ]);
      expect(again.exercises.map((e) => e.sets.length), [3, 2]);
      expect(again.exercises.first.row.restSeconds, 90);
      expect(again.exercises.last.row.supersetGroup, 1);
      expect(
        again.exercises.every((e) => e.sets.every((s) => !s.isCompleted)),
        isTrue,
      );
      // The live guard in the repository still applies.
      expect(
        () => repo.start(name: 'x', items: items),
        throwsA(isA<LiveWorkoutExistsException>()),
      );
    });

    Future<Workout> logged(
      DateTime start, {
      double kg = 0,
      String name = 'Push',
      int? templateId,
    }) => db
        .into(db.workouts)
        .insertReturning(
          WorkoutsCompanion.insert(
            name: name,
            startedAt: start,
            endedAt: Value(start.add(const Duration(hours: 1))),
            totalSets: const Value(3),
            totalVolumeKg: Value(kg),
            templateId: Value(templateId),
          ),
        );

    test('history filters by name, template and exercise', () async {
      final (repo, id, sets) = await bench(sets: 1);
      await repo.writeSets([done(sets[0], 60, 10)]);
      await repo.finish(id, bodyweightKg: null);
      final exId = (await repo.load(id))!.exercises.single.exercise.id;
      final tpl = await TemplateRepository(db).save(name: 'Legs', items: []);
      final a = await logged(DateTime(2026, 10, 1), name: 'Legs', templateId: tpl);
      final b = await logged(DateTime(2026, 10, 2), name: 'Push day');
      final c = await logged(DateTime(2026, 10, 3), name: 'legs (home)');
      final bench0 = (await repo.load(id))!.workout;
      final all = [a, b, c, bench0];

      expect(filterHistory(all), all);
      expect(filterHistory(all, query: ' LEGS ').map((w) => w.id), [a.id, c.id]);
      expect(filterHistory(all, templateId: tpl), [a]);
      expect(filterHistory(all, query: 'push', templateId: tpl), isEmpty);
      expect(filterHistory(all, query: 'nothing'), isEmpty);

      final ids = await repo.workoutIdsWithExercise(exId);
      expect(ids, {id});
      expect(filterHistory(all, exerciseWorkoutIds: ids), [bench0]);
      expect(filterHistory(all, exerciseWorkoutIds: {}), isEmpty);
    });

    test('week comparison matches the same part of last week', () async {
      // Wednesday noon: last week’s Friday must not count against this week.
      final now = DateTime(2026, 10, 14, 12);
      final all = [
        await logged(DateTime(2026, 10, 5, 10), kg: 1000),
        await logged(DateTime(2026, 10, 9, 10), kg: 5000),
        await logged(DateTime(2026, 10, 11, 10), kg: 500),
        await logged(DateTime(2026, 10, 13, 10), kg: 1100),
      ];
      final monday = compareWeeks(all, now: now)!;
      expect((monday.thisKg, monday.lastKg), (1100, 1000));
      expect(monday.label, 'Volume +10% vs this time last week');
      // With Sunday first, the 11th belongs to this week.
      final sunday = compareWeeks(all, now: now, firstDay: DateTime.sunday)!;
      expect((sunday.thisKg, sunday.lastKg), (1600, 1000));
      expect(sunday.label, 'Volume +60% vs this time last week');

      expect(compareWeeks(all.sublist(1), now: now), isNull);
      expect(compareWeeks(all.sublist(0, 1), now: now), isNull);
      final drop = [
        await logged(DateTime(2026, 10, 6), kg: 1000),
        await logged(DateTime(2026, 10, 13), kg: 500),
      ];
      expect(
        compareWeeks(drop, now: now)!.label,
        'Volume ${kMinus}50% vs this time last week',
      );
    });

    test('a workout’s end must follow its start', () {
      final start = DateTime(2026, 10, 13, 23, 30);
      expect(endAtClock(start, 0, 30), DateTime(2026, 10, 14, 0, 30));
      expect(endAtClock(start, 23, 45), DateTime(2026, 10, 13, 23, 45));
      // Too far into the next day to be the same session.
      final morning = DateTime(2026, 10, 13, 10);
      expect(endAtClock(morning, 9, 0), DateTime(2026, 10, 13, 9));

      final now = DateTime(2026, 10, 14, 12);
      const after = 'End must be after start.';
      const future = 'That’s in the future.';
      expect(workoutTimesError(morning, DateTime(2026, 10, 13, 11), now), isNull);
      expect(workoutTimesError(morning, morning, now), after);
      expect(workoutTimesError(morning, DateTime(2026, 10, 13, 9), now), after);
      expect(workoutTimesError(morning, DateTime(2026, 10, 14, 13), now), future);
      expect(
        workoutTimesError(DateTime(2026, 10, 15), DateTime(2026, 10, 15, 1), now),
        future,
      );
    });

    test('backup round-trip keeps goal, warm-ups and body weight', () async {
      final (repo, id, sets) = await bench(sets: 2);
      await repo.writeSets([
        done(sets[0], 40, 10, warmup: true),
        done(sets[1], 80, 8),
      ]);
      await repo.finish(id, bodyweightKg: 80);
      await SettingsRepository(
        db,
      ).write(const AppSettingsCompanion(weeklyGoal: Value(3)));
      final bw = BodyweightRepository(db);
      await bw.upsertDay(DateTime(2025, 3, 1, 9), 80.5);
      await bw.upsertDay(DateTime(2025, 3, 2, 9), 81);

      final backup = BackupService(db);
      final bytes = await backup.export();
      await backup.deleteAll();
      expect(await db.select(db.bodyweightEntries).get(), isEmpty);
      await backup.import(bytes);

      expect((await SettingsRepository(db).get()).weeklyGoal, 3);
      final restored = (await repo.load(id))!;
      expect([
        for (final s in restored.exercises.single.sets) s.setType.isWarmup,
      ], [true, false]);
      final entries = await db.select(db.bodyweightEntries).get();
      expect([for (final e in entries) (e.date, e.kg)], [
        (DateTime(2025, 3, 1), 80.5),
        (DateTime(2025, 3, 2), 81.0),
      ]);
    });

    test('v1 backup imports with defaults and a seeded log', () async {
      Map<String, Object?> workout(int id, String day, double bw) => {
        'id': id,
        'templateId': null,
        'name': 'W$id',
        'startedAt': DateTime.parse('${day}T18:00:00').toUtc().toIso8601String(),
        'endedAt': DateTime.parse('${day}T19:00:00').toUtc().toIso8601String(),
        'bodyweightKg': bw,
        'totalSets': 0,
        'totalVolumeKg': 0,
        'exerciseCount': 0,
        'exercises': <Object?>[],
      };
      final json = jsonEncode({
        'app': 'lift_flow',
        'version': 1,
        'settings': {
          'weightUnit': 'kg',
          'themeMode': 'system',
          'pureBlack': false,
          'bodyweightKg': 81,
          'defaultRestSeconds': 90,
          'autoStartRest': true,
          'restAlerts': true,
          'keepScreenOn': false,
        },
        'exercises': <Object?>[],
        'templates': <Object?>[],
        'workouts': [
          workout(2, '2025-01-05', 81),
          workout(1, '2025-01-01', 80),
          workout(3, '2025-01-09', 81),
        ],
      });
      await BackupService(db).import(Uint8List.fromList(utf8.encode(json)));
      expect((await SettingsRepository(db).get()).weeklyGoal, isNull);
      expect(
        (await SettingsRepository(db).get()).firstDayOfWeek,
        DateTime.monday,
      );
      final entries = await db.select(db.bodyweightEntries).get();
      expect([for (final e in entries) (e.date, e.kg)], [
        (DateTime(2025, 1, 1), 80.0),
        (DateTime(2025, 1, 5), 81.0),
      ]);
    });

    test('only warm-ups are left out of totals and facts', () async {
      final (repo, id, sets) = await bench(sets: 5);
      await repo.writeSets([
        for (final (i, t) in SetType.values.indexed)
          done(sets[i], 100, 5).copyWith(setType: t),
      ]);
      await repo.finish(id, bodyweightKg: null);
      final w = (await repo.load(id))!;
      expect(w.workout.totalSets, 4);
      expect(w.workout.totalVolumeKg, 4 * 500);
      expect([for (final s in w.exercises.single.sets) s.setType], SetType.values);
      final facts = await repo.setFacts([w.exercises.single.exercise.id]);
      expect(facts, hasLength(4));
    });

    test('finish applies per-side and per-dumbbell volume', () async {
      final ex = await ExerciseRepository(db).create(
        name: 'Dumbbell lunge',
        muscleGroup: MuscleGroup.quads,
        trackingType: TrackingType.weights,
        equipment: Equipment.dumbbell,
        perSide: true,
        perDumbbell: true,
        secondaryMuscles: [
          MuscleGroup.glutes,
          MuscleGroup.quads,
          MuscleGroup.glutes,
        ],
      );
      expect(ex.secondaryMuscles, [MuscleGroup.glutes]);
      final repo = WorkoutRepository(db);
      final id = await repo.start();
      final (_, sets) = await repo.addExercise(id, ex.id, position: 0);
      await repo.writeSets([done(sets[0], 20, 10)]);
      await repo.finish(id, bodyweightKg: null);

      expect((await repo.load(id))!.workout.totalVolumeKg, 40 * 20);
      final fact = (await repo.setFacts([ex.id])).single;
      expect(fact.volume, 800);
      expect(fact.loadKg, 20);
      expect(fact.secondaryMuscles, [MuscleGroup.glutes]);
      // Records stay on the entered load.
      final bests = ExerciseBests()..add(fact);
      expect(bests.heaviest, 20);

      // Leaving the new fields out of an update keeps them.
      final exercises = ExerciseRepository(db);
      await exercises.update(
        ex.id,
        name: ex.name,
        muscleGroup: MuscleGroup.glutes,
        trackingType: ex.trackingType,
        loadMode: ex.loadMode,
      );
      final kept = (await exercises.getById(ex.id))!;
      expect(kept.perSide && kept.perDumbbell, isTrue);
      expect(kept.equipment, Equipment.dumbbell);
      expect(kept.secondaryMuscles, isEmpty);
    });

    test('changing per-side or per-dumbbell recalculates volume', () async {
      final exercises = ExerciseRepository(db);
      final curl = await exercises.create(
        name: 'Curl',
        muscleGroup: MuscleGroup.biceps,
        trackingType: TrackingType.weights,
        equipment: Equipment.dumbbell,
      );
      final row = await exercises.create(
        name: 'Row',
        muscleGroup: MuscleGroup.back,
        trackingType: TrackingType.weights,
      );
      final repo = WorkoutRepository(db);
      final w1 = await repo.start();
      final (_, a) = await repo.addExercise(w1, curl.id, position: 0);
      final (_, b) = await repo.addExercise(w1, row.id, position: 1, sets: 2);
      await repo.writeSets([
        done(a[0], 20, 10),
        done(b[0], 100, 5),
        done(b[1], 60, 5, warmup: true),
      ]);
      await repo.finish(w1, bodyweightKg: null);
      final w2 = await repo.start();
      final (_, c) = await repo.addExercise(w2, row.id, position: 0);
      await repo.writeSets([done(c[0], 80, 5)]);
      await repo.finish(w2, bodyweightKg: null);
      final live = await repo.start();
      await repo.addExercise(live, curl.id, position: 0);

      Future<List<double>> volumes() async => [
        for (final id in [w1, w2, live])
          (await repo.load(id))!.workout.totalVolumeKg,
      ];
      Future<void> flags({bool? side, bool? dumbbell, String? name}) =>
          exercises.update(
            curl.id,
            name: name ?? curl.name,
            muscleGroup: curl.muscleGroup,
            trackingType: curl.trackingType,
            loadMode: curl.loadMode,
            perSide: side,
            perDumbbell: dumbbell,
          );

      expect(await volumes(), [700, 400, 0]);
      await flags(dumbbell: true);
      expect(await volumes(), [900, 400, 0]);
      await flags(side: true);
      expect(await volumes(), [1300, 400, 0]);
      await flags(side: false, dumbbell: false);
      expect(await volumes(), [700, 400, 0]);

      // Edits that leave both flags alone don't touch the stored summary.
      await (db.update(db.workouts)..where((w) => w.id.equals(w1))).write(
        const WorkoutsCompanion(totalVolumeKg: Value(1)),
      );
      await flags(name: 'Curls');
      expect((await volumes())[0], 1);

      // A rejected edit changes nothing.
      await expectLater(
        flags(side: true, name: 'Row'),
        throwsA(isA<DuplicateNameException>()),
      );
      expect((await exercises.getById(curl.id))!.perSide, isFalse);
      expect((await volumes())[0], 1);
    });

    test('exercise usage counts finished sessions only', () async {
      final exercises = ExerciseRepository(db);
      final bench = await exercises.create(
        name: 'Bench press',
        muscleGroup: MuscleGroup.chest,
        trackingType: TrackingType.weights,
      );
      final squat = await exercises.create(
        name: 'Squat',
        muscleGroup: MuscleGroup.quads,
        trackingType: TrackingType.weights,
      );
      final repo = WorkoutRepository(db);
      var last = 0;
      for (var i = 0; i < 2; i++) {
        last = await repo.start();
        final (_, s) = await repo.addExercise(last, bench.id, position: 0);
        await repo.writeSets([done(s[0], 60, 5)]);
        await repo.finish(last, bodyweightKg: null);
      }
      final live = await repo.start();
      await repo.addExercise(live, squat.id, position: 0);

      final usage = await repo.watchExerciseUsage().first;
      expect(usage.keys, [bench.id]);
      expect(usage[bench.id]!.count, 2);
      expect(
        usage[bench.id]!.lastUsed,
        (await repo.load(last))!.workout.startedAt,
      );
    });

    test('writeSets stores the new set fields', () async {
      final (repo, id, sets) = await bench(sets: 1);
      await repo.writeSets([
        done(sets[0], 80, 8).copyWith(
          setType: SetType.amrap,
          rpe: const Value(8.5),
          note: const Value('Paused'),
          durationSeconds: const Value(45),
          distanceM: const Value(400),
        ),
      ]);
      final s = (await repo.load(id))!.exercises.single.sets.single;
      expect(s.setType, SetType.amrap);
      expect((s.rpe, s.note, s.durationSeconds, s.distanceM), (
        8.5,
        'Paused',
        45,
        400.0,
      ));
    });

    test('rest, target and superset travel template to workout and back', () async {
      final exercises = ExerciseRepository(db);
      final a = await exercises.create(
        name: 'Bench press',
        muscleGroup: MuscleGroup.chest,
        trackingType: TrackingType.weights,
      );
      final b = await exercises.create(
        name: 'Row',
        muscleGroup: MuscleGroup.back,
        trackingType: TrackingType.weights,
      );
      final templates = TemplateRepository(db);
      final tid = await templates.save(
        name: 'Upper',
        items: [
          TemplateItem(
            exercise: a,
            targetSets: 1,
            restSeconds: 120,
            targetWeightKg: 82.5,
            supersetGroup: 1,
          ),
          TemplateItem(exercise: b, targetSets: 1, supersetGroup: 1),
        ],
      );
      final stored = (await templates.get(tid))!.items;
      expect(stored.first.restSeconds, 120);
      expect(stored.first.targetWeightKg, 82.5);
      expect([for (final i in stored) i.supersetGroup], [1, 1]);

      final repo = WorkoutRepository(db);
      final id = await repo.start(templateId: tid);
      final w = (await repo.load(id))!;
      expect(w.exercises.first.row.restSeconds, 120);
      expect(w.exercises.first.row.targetWeightKg, 82.5);
      expect([for (final e in w.exercises) e.row.supersetGroup], [1, 1]);
      expect(w.exercises.last.row.restSeconds, isNull);

      await repo.updateExercise(
        w.exercises.last.row.id,
        const WorkoutExercisesCompanion(
          restSeconds: Value(60),
          note: Value('Slow'),
        ),
      );
      await repo.setNote(id, ' Felt good ');
      await repo.writeSets([
        done(w.exercises.first.sets.single, 80, 5),
        done(w.exercises.last.sets.single, 60, 8),
      ]);
      await repo.finish(id, bodyweightKg: null);
      final finished = (await repo.load(id))!;
      expect(finished.workout.note, 'Felt good');
      expect(finished.exercises.last.row.note, 'Slow');

      final items = await templates.itemsFromWorkout(id);
      expect([for (final i in items) i.restSeconds], [120, 60]);
      expect([for (final i in items) i.targetWeightKg], [82.5, null]);
      expect([for (final i in items) i.supersetGroup], [1, 1]);
      await templates.save(id: tid, name: 'Upper', items: items);
      expect((await templates.get(tid))!.items.last.restSeconds, 60);
    });

    test('template folders', () async {
      final templates = TemplateRepository(db);
      final push = await templates.createFolder(' Push ');
      final pull = await templates.createFolder('Pull');
      final tid = await templates.save(
        name: 'Day A',
        items: const [],
        folderId: push,
      );
      final loose = await templates.save(name: 'Day B', items: const []);
      expect((await templates.get(tid))!.template.folderId, push);
      expect((await templates.get(loose))!.template.folderId, isNull);

      await templates.renameFolder(push, 'Push days');
      await templates.setFolderCollapsed(push, true);
      await templates.reorderFolders([pull, push]);
      await templates.moveToFolder(loose, pull);
      final folders = await templates.watchFolders().first;
      expect([for (final f in folders) f.name], ['Pull', 'Push days']);
      expect(folders.last.isCollapsed, isTrue);
      expect((await templates.get(loose))!.template.folderId, pull);

      // Saving an existing template keeps it in its folder.
      await templates.save(id: tid, name: 'Day A+', items: const []);
      expect((await templates.get(tid))!.template.folderId, push);
      // Deleting a folder keeps its templates.
      await templates.deleteFolder(push);
      expect((await templates.get(tid))!.template.folderId, isNull);
      expect(await templates.watchFolders().first, hasLength(1));
    });

    test('v3 backup round-trip keeps the new fields and folders', () async {
      final exercises = ExerciseRepository(db);
      final ex = await exercises.create(
        name: 'Dumbbell curl',
        muscleGroup: MuscleGroup.biceps,
        trackingType: TrackingType.weights,
        equipment: Equipment.dumbbell,
        perSide: true,
        perDumbbell: true,
        secondaryMuscles: [MuscleGroup.forearms],
      );
      final templates = TemplateRepository(db);
      final folder = await templates.createFolder('Arms');
      await templates.setFolderCollapsed(folder, true);
      final tid = await templates.save(
        name: 'Arm day',
        folderId: folder,
        items: [
          TemplateItem(
            exercise: ex,
            targetSets: 1,
            restSeconds: 75,
            targetWeightKg: 12.5,
            supersetGroup: 2,
          ),
        ],
      );
      final repo = WorkoutRepository(db);
      final id = await repo.start(templateId: tid);
      final loaded = (await repo.load(id))!;
      await repo.setNote(id, 'Late session');
      await repo.updateExercise(
        loaded.exercises.single.row.id,
        const WorkoutExercisesCompanion(note: Value('Strict')),
      );
      await repo.writeSets([
        done(loaded.exercises.single.sets.single, 12.5, 10).copyWith(
          setType: SetType.drop,
          rpe: const Value(9),
          note: const Value('Left first'),
          durationSeconds: const Value(30),
          distanceM: const Value(12.5),
        ),
      ]);
      await repo.finish(id, bodyweightKg: 80);
      final lastBackup = DateTime(2025, 5, 1);
      await SettingsRepository(db).write(
        AppSettingsCompanion(
          effortMode: const Value(EffortMode.rir),
          restSound: const Value(true),
          firstDayOfWeek: const Value(DateTime.sunday),
          barWeightKg: const Value(15),
          plates: const Value('20,10,5,2.5'),
          balanceMin: const Value(8),
          balanceMax: const Value(16),
          dynamicColor: const Value(true),
          reminderDays: const Value(0x15),
          reminderMinutes: const Value(420),
          lastBackupAt: Value(lastBackup),
          backupSnoozedAt: Value(lastBackup),
          appLock: const Value(true),
          setMenuHintSeen: const Value(true),
          permissionsPrompted: const Value(true),
        ),
      );
      await db
          .into(db.progressPhotos)
          .insert(
            ProgressPhotosCompanion.insert(
              takenAt: DateTime(2025, 4, 1),
              fileName: 'a.jpg',
            ),
          );

      final backup = BackupService(db);
      final bytes = await backup.export();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      expect(json['version'], 3);
      expect(json.containsKey('progressPhotos'), isFalse);
      final exported = json['settings']! as Map<String, Object?>;
      for (final k in [
        'lastBackupAt',
        'backupSnoozedAt',
        'appLock',
        'setMenuHintSeen',
        'permissionsPrompted',
      ]) {
        expect(exported.containsKey(k), isFalse, reason: k);
      }

      await backup.deleteAll();
      await backup.import(bytes);

      final s = await SettingsRepository(db).get();
      expect(s.effortMode, EffortMode.rir);
      expect(s.restSound, isTrue);
      expect(s.firstDayOfWeek, DateTime.sunday);
      expect(s.barWeightKg, 15);
      expect(s.plates, '20,10,5,2.5');
      expect((s.balanceMin, s.balanceMax), (8, 16));
      expect(s.dynamicColor, isTrue);
      expect((s.reminderDays, s.reminderMinutes), (0x15, 420));
      // Device-local state is not part of a backup.
      expect(s.lastBackupAt, isNull);
      expect(s.backupSnoozedAt, isNull);
      expect(s.appLock, isFalse);
      expect(s.setMenuHintSeen, isFalse);
      expect(s.permissionsPrompted, isFalse);

      final e = (await exercises.getById(ex.id))!;
      expect(e.muscleGroup, MuscleGroup.biceps);
      expect(e.equipment, Equipment.dumbbell);
      expect(e.perSide && e.perDumbbell, isTrue);
      expect(e.secondaryMuscles, [MuscleGroup.forearms]);

      final f = (await templates.watchFolders().first).single;
      expect((f.id, f.name, f.isCollapsed), (folder, 'Arms', true));
      final tpl = (await templates.get(tid))!;
      expect(tpl.template.folderId, folder);
      final item = tpl.items.single;
      expect((item.restSeconds, item.targetWeightKg, item.supersetGroup), (
        75,
        12.5,
        2,
      ));

      final w = (await repo.load(id))!;
      expect(w.workout.note, 'Late session');
      expect(w.workout.totalVolumeKg, 25 * 20);
      final row = w.exercises.single.row;
      expect(
        (row.note, row.restSeconds, row.targetWeightKg, row.supersetGroup),
        ('Strict', 75, 12.5, 2),
      );
      final set = w.exercises.single.sets.single;
      expect(set.setType, SetType.drop);
      expect((set.rpe, set.note, set.durationSeconds, set.distanceM), (
        9.0,
        'Left first',
        30,
        12.5,
      ));

      // Photos live outside the backup: delete and import leave them alone.
      expect(
        (await db.select(db.progressPhotos).getSingle()).fileName,
        'a.jpg',
      );
    });

    test('v2 backup imports with defaults, warm-ups and remapped groups', () async {
      Map<String, Object?> exercise(int id, String name, String group) => {
        'id': id,
        'name': name,
        'muscleGroup': group,
        'trackingType': 'weights',
        'loadMode': 'none',
        'notes': null,
        'isArchived': false,
        'createdAt': '2025-01-01T08:00:00.000Z',
      };
      Map<String, Object?> set(int position, {required bool warmup}) => {
        'position': position,
        'loadKg': 30,
        'reps': 10,
        'isCompleted': true,
        'completedAt': '2025-01-05T18:10:00.000Z',
        'isWarmup': warmup,
      };
      final json = jsonEncode({
        'app': 'lift_flow',
        'version': 2,
        'settings': {
          'weightUnit': 'lb',
          'themeMode': 'dark',
          'pureBlack': true,
          'bodyweightKg': 81,
          'defaultRestSeconds': 120,
          'autoStartRest': true,
          'restAlerts': true,
          'keepScreenOn': false,
          'weeklyGoal': 4,
        },
        'bodyweight': [
          {'date': '2025-01-05', 'kg': 81},
        ],
        'exercises': [
          exercise(1, 'Barbell curl', 'arms'),
          exercise(2, 'Leg press', 'legs'),
          exercise(3, 'Farmer walk', 'legs'),
          exercise(4, 'Bench press', 'chest'),
        ],
        'templates': [
          {
            'id': 1,
            'name': 'Arms',
            'position': 0,
            'items': [
              {
                'exerciseId': 1,
                'position': 0,
                'targetSets': 3,
                'repsMin': 8,
                'repsMax': 12,
              },
            ],
          },
        ],
        'workouts': [
          {
            'id': 1,
            'templateId': 1,
            'name': 'Arms',
            'startedAt': '2025-01-05T18:00:00.000Z',
            'endedAt': '2025-01-05T19:00:00.000Z',
            'bodyweightKg': 81,
            'totalSets': 1,
            'totalVolumeKg': 300,
            'exerciseCount': 1,
            'exercises': [
              {
                'exerciseId': 1,
                'position': 0,
                'targetRepsMin': 8,
                'targetRepsMax': 12,
                'sets': [set(0, warmup: true), set(1, warmup: false)],
              },
            ],
          },
        ],
      });
      // Settings changed on this device must not survive the import.
      await SettingsRepository(db).write(
        const AppSettingsCompanion(
          firstDayOfWeek: Value(DateTime.saturday),
          effortMode: Value(EffortMode.rpe),
          balanceMin: Value(4),
        ),
      );
      await BackupService(db).import(Uint8List.fromList(utf8.encode(json)));

      final s = await SettingsRepository(db).get();
      expect(s.weightUnit, WeightUnit.lb);
      expect(s.weeklyGoal, 4);
      expect(s.firstDayOfWeek, DateTime.monday);
      expect(s.effortMode, EffortMode.off);
      expect((s.balanceMin, s.balanceMax), (10, 20));
      expect((s.reminderDays, s.reminderMinutes), (0, 1080));
      expect(s.barWeightKg, isNull);
      expect(s.plates, isNull);

      final all = await db.select(db.exercises).get();
      expect({for (final e in all) e.name: e.muscleGroup}, {
        'Barbell curl': MuscleGroup.biceps,
        'Leg press': MuscleGroup.quads,
        'Farmer walk': MuscleGroup.legs,
        'Bench press': MuscleGroup.chest,
      });
      expect(all.every((e) => e.equipment == Equipment.none), isTrue);
      expect(all.every((e) => !e.perSide && !e.perDumbbell), isTrue);
      expect(all.every((e) => e.secondaryMuscles.isEmpty), isTrue);

      final tpl = (await TemplateRepository(db).get(1))!;
      expect(tpl.template.folderId, isNull);
      expect(tpl.items.single.restSeconds, isNull);
      expect(await TemplateRepository(db).watchFolders().first, isEmpty);
      final w = (await WorkoutRepository(db).load(1))!;
      expect(w.workout.note, isNull);
      expect(
        [for (final s in w.exercises.single.sets) s.setType],
        [SetType.warmup, SetType.normal],
      );
      expect(w.exercises.single.sets.every((s) => s.rpe == null), isTrue);
    });

    test('v3 backup rejects unknown set types and muscles', () async {
      final (repo, id, sets) = await bench(sets: 1);
      await repo.writeSets([done(sets[0], 80, 8)]);
      await repo.finish(id, bodyweightKg: null);
      final bytes = await BackupService(db).export();
      Map<String, Object?> decode() =>
          jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      Uint8List encode(Object? m) =>
          Uint8List.fromList(utf8.encode(jsonEncode(m)));
      Map<String, Object?> first(Map<String, Object?> m, String k) =>
          (m[k]! as List<Object?>).first! as Map<String, Object?>;

      final badSet = decode();
      first(first(first(badSet, 'workouts'), 'exercises'), 'sets')['setType'] =
          'giant';
      expect(
        () => parseBackup(encode(badSet)),
        throwsA(isA<BackupFormatException>()),
      );
      final badMuscle = decode();
      first(badMuscle, 'exercises')['secondaryMuscles'] = ['neck'];
      expect(
        () => parseBackup(encode(badMuscle)),
        throwsA(isA<BackupFormatException>()),
      );
      final badBand = decode();
      (badBand['settings']! as Map<String, Object?>)['balanceMax'] = 5;
      expect(
        () => parseBackup(encode(badBand)),
        throwsA(isA<BackupFormatException>()),
      );
      expect(parseBackup(bytes).workouts, hasLength(1));
    });

    test('v2 backup rejects two body weights on one day', () async {
      final bytes = await BackupService(db).export();
      final m = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      m['bodyweight'] = [
        {'date': '2025-01-01', 'kg': 80},
        {'date': '2025-01-01', 'kg': 81},
      ];
      expect(
        () => parseBackup(Uint8List.fromList(utf8.encode(jsonEncode(m)))),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('body-weight log updates the current value', () async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(
            await SettingsRepository(db).get(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final bw = BodyweightRepository(db);
      await bw.upsertDay(DateTime(2025, 1, 1), 79);
      final ctrl = container.read(settingsProvider.notifier);

      await ctrl.logBodyweight(80);
      await ctrl.logBodyweight(80.5);
      final today = DateTime.now();
      final day = DateTime(today.year, today.month, today.day);
      expect(await db.select(db.bodyweightEntries).get(), hasLength(2));
      expect(container.read(settingsProvider).bodyweightKg, 80.5);

      await ctrl.deleteBodyweightEntry(day);
      expect(container.read(settingsProvider).bodyweightKg, 79);
      await ctrl.deleteBodyweightEntry(DateTime(2025, 1, 1));
      expect(container.read(settingsProvider).bodyweightKg, isNull);
    });

    test('workout insights compare with the last session', () async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(
            await SettingsRepository(db).get(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final (repo, first, sets) = await bench(sets: 1);
      await repo.writeSets([done(sets[0], 80, 5)]);
      await repo.finish(first, bodyweightKg: null);
      final exId = (await repo.load(first))!.exercises.single.exercise.id;
      final second = await repo.start();
      final (_, s2) = await repo.addExercise(second, exId, position: 0, sets: 2);
      await repo.writeSets([
        done(s2[0], 40, 10, warmup: true),
        done(s2[1], 85, 5),
      ]);
      await repo.finish(second, bodyweightKg: null);

      final sub = container.listen(workoutInsightsProvider(second), (_, _) {});
      addTearDown(sub.close);
      final i = (await container.read(workoutInsightsProvider(second).future))!;
      final lift = i.lifts[exId]!;
      expect(lift.series, hasLength(2));
      expect(lift.delta!, closeTo(5 * (1 + 5 / 30), 1e-9));
      expect(lift.prs, contains(PrKind.heaviest));
      expect(
        await container.read(workoutPrsProvider(second).future),
        {exId: lift.prs},
      );
    });

    test('rest actions update the persisted rest', () async {
      final repo = RestRepository(db);
      final now = DateTime(2025, 1, 1, 12);
      await repo.save(now.add(const Duration(seconds: 40)), 60);

      final next = await applyRestAction(
        repo,
        NotificationService.actionAdd,
        now: now,
      );
      expect(next?.endsAt, now.add(const Duration(seconds: 70)));
      final row = (await repo.get())!;
      expect(row.endsAt, next!.endsAt);
      expect(row.totalSeconds, 90);

      final skipped = await applyRestAction(
        repo,
        NotificationService.actionSkip,
        now: now,
      );
      expect(skipped, isNull);
      expect(await repo.get(), isNull);
    });

    test('a finished rest is not revived by +30 s', () async {
      final repo = RestRepository(db);
      final now = DateTime(2025, 1, 1, 12);
      await repo.save(now.subtract(const Duration(seconds: 5)), 60);
      final next = await applyRestAction(
        repo,
        NotificationService.actionAdd,
        now: now,
      );
      expect(next, isNull);
      expect(await repo.get(), isNull);
    });

    test('rest timer reloads what a notification action changed', () async {
      final repo = RestRepository(db);
      await repo.save(DateTime.now().add(const Duration(seconds: 60)), 60);
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          initialRestProvider.overrideWithValue(await repo.get()),
        ],
      );
      addTearDown(container.dispose);
      final ctrl = container.read(restTimerProvider.notifier);
      final before = container.read(restTimerProvider)!;

      await applyRestAction(repo, NotificationService.actionAdd);
      await ctrl.reload();
      final after = container.read(restTimerProvider)!;
      expect(after.endsAt.difference(before.endsAt).inSeconds, 30);
      expect(after.totalSeconds, 90);

      await applyRestAction(repo, NotificationService.actionSkip);
      await ctrl.reload();
      expect(container.read(restTimerProvider), isNull);
    });
  });
}
