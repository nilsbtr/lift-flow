// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:lift_flow/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

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
}
