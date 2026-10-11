import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/backup_service.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/exercise_repository.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/data/workout_repository.dart';
import 'package:lift_flow/domain/backup_nudge.dart';
import 'package:lift_flow/domain/csv_export.dart';
import 'package:lift_flow/features/settings/backup_actions.dart';
import 'package:lift_flow/features/workout/workout_controller.dart';
import 'package:lift_flow/providers.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('backup nudge', () {
    final base = DateTime(2026, 3, 1, 12);
    List<DateTime> days(int n, {DateTime? from}) => [
      for (var i = 1; i <= n; i++) (from ?? base).add(Duration(days: i)),
    ];

    test('is due at ten workouts, not before', () {
      expect(backupNudgeDue(days(9)), isFalse);
      expect(backupNudgeDue(days(10)), isTrue);
      expect(workoutsSinceBackup(days(12)), 12);
    });

    test('counts only workouts finished after the last backup', () {
      final all = days(14);
      final last = all[3]; // 4 workouts are covered, 10 are not
      expect(workoutsSinceBackup(all, lastBackupAt: last), 10);
      expect(backupNudgeDue(all, lastBackupAt: last), isTrue);
      expect(backupNudgeDue(all, lastBackupAt: all[4]), isFalse);
      // A workout finished at the very moment of the backup is covered.
      expect(workoutsSinceBackup(all, lastBackupAt: all.last), 0);
    });

    test('dismissing starts a new count', () {
      final all = days(25);
      final snoozed = all[14]; // 10 left after it
      expect(backupNudgeDue(all, snoozedAt: snoozed), isTrue);
      expect(backupNudgeDue(all, snoozedAt: all[15]), isFalse);
      expect(backupNudgeDue(all, snoozedAt: all.last), isFalse);
    });

    test('the later of backup and dismissal wins', () {
      final all = days(30);
      expect(
        workoutsSinceBackup(all, lastBackupAt: all[4], snoozedAt: all[19]),
        10,
      );
      expect(
        workoutsSinceBackup(all, lastBackupAt: all[19], snoozedAt: all[4]),
        10,
      );
    });

    test('is never due without workouts', () {
      expect(backupNudgeDue(const []), isFalse);
    });
  });

  group('last backup', () {
    late AppDatabase db;
    late BackupService backup;
    late SettingsRepository settings;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      backup = BackupService(db);
      settings = SettingsRepository(db);
    });
    tearDown(() => db.close());

    Future<Uint8List> fileExportedAt(Object? exportedAt) async {
      final json = jsonDecode(
        utf8.decode(await backup.export()),
      ) as Map<String, Object?>;
      json['exportedAt'] = exportedAt;
      return Uint8List.fromList(utf8.encode(jsonEncode(json)));
    }

    test('is not touched by export and not part of the file', () async {
      await settings.write(
        AppSettingsCompanion(lastBackupAt: Value(DateTime(2026, 1, 1))),
      );
      final json = jsonDecode(
        utf8.decode(await backup.export()),
      ) as Map<String, Object?>;
      expect((json['settings']! as Map).containsKey('lastBackupAt'), isFalse);
      expect((await settings.get()).lastBackupAt, DateTime(2026, 1, 1));
    });

    test('an import counts as backed up from when the file was made', () async {
      final made = DateTime.utc(2026, 2, 3, 10, 30);
      await settings.write(
        AppSettingsCompanion(
          lastBackupAt: Value(DateTime(2026, 4, 1)),
          backupSnoozedAt: Value(DateTime(2026, 4, 2)),
        ),
      );
      await backup.import(await fileExportedAt(made.toIso8601String()));
      final s = await settings.get();
      expect(s.lastBackupAt!.isAtSameMomentAs(made), isTrue);
      expect(s.backupSnoozedAt, isNull);
    });

    test('an unusable or future file date falls back to now', () async {
      for (final bad in [null, 'yesterday', 42, '2999-01-01T00:00:00Z']) {
        final before = DateTime.now().subtract(const Duration(seconds: 2));
        await backup.import(await fileExportedAt(bad));
        final at = (await settings.get()).lastBackupAt!;
        expect(at.isAfter(before), isTrue, reason: '$bad');
        expect(
          at.isAfter(DateTime.now().add(const Duration(seconds: 2))),
          isFalse,
        );
      }
    });

    test('delete-all forgets it', () async {
      await settings.write(
        AppSettingsCompanion(lastBackupAt: Value(DateTime(2026, 1, 1))),
      );
      await backup.deleteAll();
      expect((await settings.get()).lastBackupAt, isNull);
    });
  });

  group('csv export', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<int> exercise(String name, MuscleGroup g, {Equipment? eq}) => db
        .into(db.exercises)
        .insert(
          ExercisesCompanion.insert(
            name: name,
            muscleGroup: g,
            trackingType: TrackingType.weights,
            createdAt: DateTime(2026, 1, 1),
            equipment: Value(eq ?? Equipment.none),
          ),
        );

    Future<int> workout(
      String name,
      DateTime start, {
      bool live = false,
      String? note,
    }) => db
        .into(db.workouts)
        .insert(
          WorkoutsCompanion.insert(
            name: name,
            startedAt: start,
            endedAt: Value(live ? null : start.add(const Duration(hours: 1))),
            note: Value(note),
          ),
        );

    Future<int> slot(int workoutId, int exerciseId, int pos, {String? note}) =>
        db
            .into(db.workoutExercises)
            .insert(
              WorkoutExercisesCompanion.insert(
                workoutId: workoutId,
                exerciseId: exerciseId,
                position: pos,
                note: Value(note),
              ),
            );

    Future<void> set(
      int slotId,
      int pos, {
      double? kg,
      int? reps,
      bool done = true,
      SetType type = SetType.normal,
      double? rpe,
      String? note,
    }) => db
        .into(db.workoutSets)
        .insert(
          WorkoutSetsCompanion.insert(
            workoutExerciseId: slotId,
            position: pos,
            loadKg: Value(kg),
            reps: Value(reps),
            isCompleted: Value(done),
            setType: Value(type),
            rpe: Value(rpe),
            note: Value(note),
          ),
        );

    Future<List<String>> lines(WeightUnit unit) async {
      final text = utf8.decode(await BackupService(db).exportCsv(unit));
      expect(text.endsWith('\r\n'), isTrue);
      return text.substring(0, text.length - 2).split('\r\n');
    }

    test('header only for an empty database', () async {
      expect(await lines(WeightUnit.kg), [kCsvHeader.join(',')]);
    });

    test('one row per completed set of finished workouts', () async {
      final bench = await exercise(
        'Bench press',
        MuscleGroup.chest,
        eq: Equipment.barbell,
      );
      final w = await workout('Push', DateTime(2026, 3, 5, 18, 5));
      final s = await slot(w, bench, 0);
      await set(s, 0, kg: 40, reps: 10, type: SetType.warmup);
      await set(s, 1, kg: 100, reps: 5, rpe: 8.5, note: 'Felt heavy');
      await set(s, 2, kg: 100, reps: 4, done: false);
      // A workout still running is not exported.
      final live = await workout('Live', DateTime(2026, 3, 6), live: true);
      await set(await slot(live, bench, 0), 0, kg: 50, reps: 5);

      final rows = await lines(WeightUnit.kg);
      expect(rows, hasLength(3));
      expect(
        rows[1],
        '2026-03-05,18:05,Push,Bench press,Chest,Barbell,1,Warm-up,40,40,kg,'
        '10,,,,,,',
      );
      expect(
        rows[2],
        '2026-03-05,18:05,Push,Bench press,Chest,Barbell,2,Normal,100,100,kg,'
        '5,8.5,,,Felt heavy,,',
      );
    });

    test('weight in the user’s unit next to kg', () async {
      final e = await exercise('Squat', MuscleGroup.quads);
      final w = await workout('Legs', DateTime(2026, 3, 5, 9));
      final s = await slot(w, e, 0);
      await set(s, 0, kg: 100, reps: 5);
      await set(s, 1, reps: 12);
      final rows = await lines(WeightUnit.lb);
      expect(rows[1], contains(',Normal,100,220.46,lb,5,'));
      // No load, no weight; the unit still says what the column means.
      expect(rows[2], contains(',Normal,,,lb,12,'));
      expect(rows[1].split(',')[5], '', reason: 'no equipment');
    });

    test('quotes commas, quotes and line breaks', () async {
      final e = await exercise('Curl, "EZ" bar', MuscleGroup.biceps);
      final w = await workout(
        'Arms\nday',
        DateTime(2026, 3, 5, 9),
        note: 'a,b',
      );
      final s = await slot(w, e, 0, note: 'say "hi"');
      await set(s, 0, kg: 20, reps: 8, note: 'line 1\r\nline 2');
      final text = utf8.decode(
        await BackupService(db).exportCsv(WeightUnit.kg),
      );
      expect(
        text,
        contains(
          '2026-03-05,09:00,"Arms\nday","Curl, ""EZ"" bar",Biceps,,1,Normal,'
          '20,20,kg,8,,,,"line 1\r\nline 2","say ""hi""","a,b"\r\n',
        ),
      );
    });

    test('orders by workout date, exercise and set position', () async {
      final a = await exercise('A', MuscleGroup.chest);
      final b = await exercise('B', MuscleGroup.back);
      final later = await workout('Later', DateTime(2026, 3, 9, 8));
      final earlier = await workout('Earlier', DateTime(2026, 3, 2, 8));
      // Inserted out of order on purpose.
      final lb = await slot(later, b, 1);
      final la = await slot(later, a, 0);
      await set(lb, 1, kg: 2, reps: 2);
      await set(lb, 0, kg: 1, reps: 1);
      await set(la, 0, kg: 3, reps: 3);
      await set(await slot(earlier, b, 0), 0, kg: 4, reps: 4);
      final order = [
        for (final r in (await lines(WeightUnit.kg)).skip(1))
          '${r.split(',').sublist(2, 4).join('/')}:${r.split(',')[8]}',
      ];
      expect(order, ['Earlier/B:4', 'Later/A:3', 'Later/B:1', 'Later/B:2']);
    });

    test('is UTF-8 without a byte order mark', () async {
      final e = await exercise('Überzüge', MuscleGroup.back);
      final w = await workout('Rücken', DateTime(2026, 3, 5));
      await set(await slot(w, e, 0), 0, kg: 20, reps: 10, note: 'gut – 💪');
      final bytes = await BackupService(db).exportCsv(WeightUnit.kg);
      expect(bytes.take(3), isNot([0xEF, 0xBB, 0xBF]));
      expect(utf8.decode(bytes), contains('Rücken,Überzüge'));
      expect(utf8.decode(bytes), contains('gut – 💪'));
    });

    test('does not count as a backup', () async {
      await BackupService(db).exportCsv(WeightUnit.kg);
      expect((await SettingsRepository(db).get()).lastBackupAt, isNull);
    });

    test('csvField only quotes what needs it', () {
      expect(csvField(null), '');
      expect(csvField('plain text'), 'plain text');
      expect(csvField(' padded '), ' padded ');
      expect(csvField('a"b'), '"a""b"');
      expect(csvField('a,b'), '"a,b"');
    });
  });

  group('import and reset', () {
    late AppDatabase db;
    late BackupService backup;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      backup = BackupService(db);
    });
    tearDown(() => db.close());

    Future<int> seed(AppDatabase d, String name, {bool live = false}) async {
      final e = await ExerciseRepository(d).create(
        name: 'Row',
        muscleGroup: MuscleGroup.back,
        trackingType: TrackingType.weights,
      );
      final repo = WorkoutRepository(d);
      final id = await repo.start(name: name);
      final (_, sets) = await repo.addExercise(id, e.id, position: 0);
      await repo.writeSets([
        sets.first.copyWith(
          loadKg: const Value(60),
          reps: const Value(8),
          isCompleted: true,
        ),
      ]);
      if (!live) await repo.finish(id, bodyweightKg: null);
      return id;
    }

    test('are refused while a workout is live, and change nothing', () async {
      await seed(db, 'Running', live: true);
      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await seed(other, 'From file');
      final file = await BackupService(other).export();

      await expectLater(
        backup.import(file),
        throwsA(isA<BackupBlockedException>()),
      );
      await expectLater(
        backup.deleteAll(),
        throwsA(isA<BackupBlockedException>()),
      );
      final w = await db.select(db.workouts).getSingle();
      expect(w.name, 'Running');
      expect(await db.select(db.exercises).get(), hasLength(1));
    });

    test('the message says why and what to do', () {
      expect(BackupBlockedException.message, contains('workout is running'));
      expect(BackupBlockedException.message, contains('Finish or discard'));
    });

    test('work again once the workout is finished', () async {
      final id = await seed(db, 'Running', live: true);
      await WorkoutRepository(db).finish(id, bodyweightKg: null);
      await backup.deleteAll();
      expect(await db.select(db.workouts).get(), isEmpty);
    });

    test('a file holding an unfinished workout still imports', () async {
      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await seed(other, 'Unfinished', live: true);
      await backup.import(await BackupService(other).export());
      expect((await WorkoutRepository(db).getLive())?.name, 'Unfinished');
    });

    testWidgets('resetAppState drops what the old data left in memory', (
      tester,
    ) async {
      late WidgetRef ref;
      await tester.runAsync(() async {
        final id = await seed(db, 'Old');
        final other = AppDatabase(NativeDatabase.memory());
        await seed(other, 'New');
        await SettingsRepository(
          other,
        ).write(const AppSettingsCompanion(weightUnit: Value(WeightUnit.lb)));
        final file = await BackupService(other).export();
        await other.close();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              initialSettingsProvider.overrideWithValue(
                await SettingsRepository(db).get(),
              ),
            ],
            child: Consumer(
              builder: (context, r, _) {
                ref = r;
                return const SizedBox();
              },
            ),
          ),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(Consumer)),
        );
        final editor = container.listen(workoutEditorProvider(id), (_, _) {});
        expect(
          (await container.read(workoutEditorProvider(id).future)).workout.name,
          'Old',
        );
        ref.read(restTimerProvider.notifier).start(60);
        expect(ref.read(restTimerProvider), isNotNull);
        expect(ref.read(settingsProvider).weightUnit, WeightUnit.kg);
        ref.read(forgottenAskedProvider).add(id);

        await backup.import(file);
        // Nothing has been told yet: the cached copies are stale.
        expect(ref.read(settingsProvider).weightUnit, WeightUnit.kg);

        await resetAppState(ref);
        expect(ref.read(restTimerProvider), isNull);
        expect(ref.read(settingsProvider).weightUnit, WeightUnit.lb);
        expect(ref.read(forgottenAskedProvider), isEmpty);
        final fresh = await container.read(workoutEditorProvider(id).future);
        expect(fresh.workout.name, 'New');
        expect(await RestRepository(db).get(), isNull);
        editor.close();
      });
    });
  });
}
