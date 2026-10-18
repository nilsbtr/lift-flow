// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:lift_flow/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  test('v1 to v2 keeps sets and seeds the body-weight log', () async {
    int at(int day, [int hour = 18]) =>
        DateTime(2025, 1, day, hour).millisecondsSinceEpoch ~/ 1000;
    v1.WorkoutsData workout(int id, int day, double? bw, {int hour = 18}) =>
        v1.WorkoutsData(
          id: id,
          name: 'W$id',
          startedAt: at(day, hour),
          endedAt: at(day, hour + 1),
          bodyweightKg: bw,
          totalSets: 1,
          totalVolumeKg: 0,
          exerciseCount: 1,
        );

    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 2,
      createOld: v1.DatabaseAtV1.new,
      createNew: v2.DatabaseAtV2.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.exercises,
          v1.ExercisesData(
            id: 1,
            name: 'Squat',
            muscleGroup: 'legs',
            trackingType: 'weights',
            loadMode: 'none',
            isArchived: 0,
            createdAt: at(1, 8),
          ),
        );
        batch.insertAll(oldDb.workouts, [
          workout(1, 1, 80),
          workout(2, 2, 80),
          workout(3, 3, 81, hour: 8),
          workout(4, 3, 82),
          workout(5, 4, null),
          workout(6, 5, 82),
        ]);
        batch.insert(
          oldDb.workoutExercises,
          const v1.WorkoutExercisesData(
            id: 1,
            workoutId: 1,
            exerciseId: 1,
            position: 0,
          ),
        );
        batch.insert(
          oldDb.workoutSets,
          const v1.WorkoutSetsData(
            id: 1,
            workoutExerciseId: 1,
            position: 0,
            loadKg: 100,
            reps: 5,
            isCompleted: 1,
          ),
        );
      },
      validateItems: (newDb) async {
        int day(int d) => DateTime(2025, 1, d).millisecondsSinceEpoch ~/ 1000;
        expect(await newDb.select(newDb.bodyweightEntries).get(), [
          v2.BodyweightEntriesData(date: day(1), kg: 80),
          v2.BodyweightEntriesData(date: day(3), kg: 82),
        ]);
        final set = await newDb.select(newDb.workoutSets).getSingle();
        expect(set.loadKg, 100);
        expect(set.isWarmup, 0);
        expect(await newDb.select(newDb.workouts).get(), hasLength(6));
      },
    );
  });

  test('v2 to v3 converts warm-ups and remaps legacy muscle groups', () async {
    final at = DateTime(2025, 1, 1, 18).millisecondsSinceEpoch ~/ 1000;
    v2.ExercisesData exercise(int id, String name, String group) =>
        v2.ExercisesData(
          id: id,
          name: name,
          muscleGroup: group,
          trackingType: 'weights',
          loadMode: 'none',
          isArchived: 0,
          createdAt: at,
        );
    v2.WorkoutSetsData set(int id, int warmup) => v2.WorkoutSetsData(
      id: id,
      workoutExerciseId: 1,
      position: id - 1,
      loadKg: 40.0 * id,
      reps: 5,
      isCompleted: 1,
      completedAt: at + id,
      isWarmup: warmup,
    );

    await verifier.testWithDataIntegrity(
      oldVersion: 2,
      newVersion: 3,
      createOld: v2.DatabaseAtV2.new,
      createNew: v3.DatabaseAtV3.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insertAll(oldDb.exercises, [
          exercise(1, 'Barbell Curl', 'arms'),
          exercise(2, 'Triceps push-down', 'arms'),
          exercise(3, 'Dips', 'arms'),
          exercise(4, 'Back squat', 'legs'),
          exercise(5, 'Romanian deadlift', 'legs'),
          exercise(6, 'Hip thrust', 'legs'),
          exercise(7, 'Calf raise', 'legs'),
          exercise(8, 'Sled push', 'legs'),
          exercise(9, 'Leg curl', 'other'),
        ]);
        batch.insert(
          oldDb.workoutTemplates,
          const v2.WorkoutTemplatesData(id: 1, name: 'Arms', position: 0),
        );
        batch.insert(
          oldDb.templateExercises,
          const v2.TemplateExercisesData(
            id: 1,
            templateId: 1,
            exerciseId: 1,
            position: 0,
            targetSets: 3,
            repsMin: 8,
            repsMax: 12,
          ),
        );
        batch.insert(
          oldDb.workouts,
          v2.WorkoutsData(
            id: 1,
            templateId: 1,
            name: 'Arms',
            startedAt: at,
            endedAt: at + 3600,
            bodyweightKg: 80,
            totalSets: 2,
            totalVolumeKg: 1000,
            exerciseCount: 1,
          ),
        );
        batch.insert(
          oldDb.workoutExercises,
          const v2.WorkoutExercisesData(
            id: 1,
            workoutId: 1,
            exerciseId: 1,
            position: 0,
            targetRepsMin: 8,
          ),
        );
        batch.insertAll(oldDb.workoutSets, [set(1, 1), set(2, 0), set(3, 0)]);
        batch.insert(
          oldDb.appSettings,
          const v2.AppSettingsData(
            id: 1,
            weightUnit: 'lb',
            themeMode: 'dark',
            pureBlack: 1,
            bodyweightKg: 80,
            defaultRestSeconds: 120,
            autoStartRest: 0,
            restAlerts: 1,
            keepScreenOn: 1,
            permissionsPrompted: 1,
            weeklyGoal: 4,
          ),
        );
      },
      validateItems: (newDb) async {
        final exercises = await newDb.select(newDb.exercises).get();
        expect({for (final e in exercises) e.id: e.muscleGroup}, {
          1: 'biceps',
          2: 'triceps',
          3: 'arms',
          4: 'quads',
          5: 'hamstrings',
          6: 'glutes',
          7: 'calves',
          8: 'legs',
          9: 'other',
        });
        final e = exercises.first;
        expect(e.name, 'Barbell Curl');
        expect((e.equipment, e.perSide, e.perDumbbell, e.secondaryMuscles), (
          'none',
          0,
          0,
          '',
        ));

        final sets = await newDb.select(newDb.workoutSets).get();
        expect(
          [for (final s in sets) s.setType],
          ['warmup', 'normal', 'normal'],
        );
        expect([for (final s in sets) s.loadKg], [40, 80, 120]);
        expect([for (final s in sets) s.completedAt], [at + 1, at + 2, at + 3]);
        expect(sets.every((s) => s.isCompleted == 1 && s.reps == 5), isTrue);
        expect(sets.every((s) => s.rpe == null && s.note == null), isTrue);

        final w = await newDb.select(newDb.workouts).getSingle();
        expect((w.totalSets, w.totalVolumeKg, w.note), (2, 1000, null));
        final we = await newDb.select(newDb.workoutExercises).getSingle();
        expect((we.targetRepsMin, we.restSeconds, we.supersetGroup), (
          8,
          null,
          null,
        ));
        final tpl = await newDb.select(newDb.workoutTemplates).getSingle();
        expect((tpl.name, tpl.folderId), ('Arms', null));
        final item = await newDb.select(newDb.templateExercises).getSingle();
        expect((item.repsMin, item.repsMax, item.restSeconds), (8, 12, null));
        expect(await newDb.select(newDb.templateFolders).get(), isEmpty);
        expect(await newDb.select(newDb.progressPhotos).get(), isEmpty);

        final s = await newDb.select(newDb.appSettings).getSingle();
        expect((s.weightUnit, s.themeMode, s.weeklyGoal, s.autoStartRest), (
          'lb',
          'dark',
          4,
          0,
        ));
        expect((s.effortMode, s.firstDayOfWeek, s.balanceMin, s.balanceMax), (
          'off',
          1,
          10,
          20,
        ));
        expect((s.reminderDays, s.reminderMinutes, s.appLock), (0, 1080, 0));
        expect((s.barWeightKg, s.plates, s.lastBackupAt), (null, null, null));
      },
    );
  });

  test('v3 to v4 drops progress photos and keeps the rest', () async {
    final at = DateTime(2025, 1, 1, 18).millisecondsSinceEpoch ~/ 1000;
    await verifier.testWithDataIntegrity(
      oldVersion: 3,
      newVersion: 4,
      createOld: v3.DatabaseAtV3.new,
      createNew: v4.DatabaseAtV4.new,
      openTestedDatabase: AppDatabase.new,
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.exercises,
          v3.ExercisesData(
            id: 1,
            name: 'Squat',
            muscleGroup: 'quads',
            trackingType: 'weights',
            loadMode: 'none',
            isArchived: 0,
            createdAt: at,
            equipment: 'barbell',
            perSide: 0,
            perDumbbell: 0,
            secondaryMuscles: '',
          ),
        );
        batch.insert(
          oldDb.bodyweightEntries,
          v3.BodyweightEntriesData(date: at, kg: 80),
        );
        batch.insert(
          oldDb.progressPhotos,
          v3.ProgressPhotosData(id: 1, takenAt: at, fileName: 'a.jpg'),
        );
      },
      validateItems: (newDb) async {
        final e = await newDb.select(newDb.exercises).getSingle();
        expect((e.name, e.equipment), ('Squat', 'barbell'));
        expect(await newDb.select(newDb.bodyweightEntries).get(), [
          v4.BodyweightEntriesData(date: at, kg: 80),
        ]);
        final tables = await newDb
            .customSelect(
              "SELECT name FROM sqlite_master WHERE name = 'progress_photos'",
            )
            .get();
        expect(tables, isEmpty);
      },
    );
  });
}
