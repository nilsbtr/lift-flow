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
import 'package:lift_flow/domain/records.dart';
import 'package:lift_flow/domain/units.dart';
import 'package:lift_flow/providers.dart';

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
          isWarmup: warmup,
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
      expect(w.exercises.single.sets.first.isWarmup, isTrue);

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
        [for (final s in next.exercises.single.sets) s.isWarmup],
        [true, false, false, false],
      );
    });

    test('v2 backup round-trip keeps goal, warm-ups and body weight', () async {
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
        for (final s in restored.exercises.single.sets) s.isWarmup,
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
      final entries = await db.select(db.bodyweightEntries).get();
      expect([for (final e in entries) (e.date, e.kg)], [
        (DateTime(2025, 1, 1), 80.0),
        (DateTime(2025, 1, 5), 81.0),
      ]);
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
  });
}
