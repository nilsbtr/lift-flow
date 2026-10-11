import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/backup_service.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/domain/backup_nudge.dart';

void main() {
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
}
