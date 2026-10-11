import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/bodyweight_repository.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/exercise_repository.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/data/workout_repository.dart';
import 'package:lift_flow/features/progress/progress_screen.dart';
import 'package:lift_flow/providers.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  for (final dark in [false, true]) {
    testWidgets('progress tab at 320 dp (${dark ? 'dark' : 'light'})', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final db = AppDatabase(NativeDatabase.memory());
      final settings = await tester.runAsync(() async {
        final ex = await ExerciseRepository(db).create(
          name: 'Bench press',
          muscleGroup: MuscleGroup.chest,
          trackingType: TrackingType.weights,
        );
        final repo = WorkoutRepository(db);
        for (final kg in [80.0, 90.0, 100.0]) {
          final id = await repo.start();
          final (_, sets) = await repo.addExercise(
            id,
            ex.id,
            position: 0,
            sets: 1,
          );
          await repo.writeSets([
            sets.single.copyWith(
              loadKg: Value(kg),
              reps: const Value(5),
              isCompleted: true,
            ),
          ]);
          await repo.finish(id, bodyweightKg: null);
        }
        final now = DateTime.now();
        final bw = BodyweightRepository(db);
        for (var i = 0; i < 3; i++) {
          await bw.upsertDay(
            DateTime(now.year, now.month, now.day - i),
            80.0 + i,
          );
        }
        return SettingsRepository(db).get();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            initialSettingsProvider.overrideWithValue(settings!),
          ],
          child: MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: const ProgressScreen(),
          ),
        ),
      );
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
      }

      await settle();
      expect(tester.takeException(), isNull);
      for (final title in [
        'Weekly training',
        'Muscle balance',
        'Records',
        'Lifetime',
        'Body weight',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('Bench press'), findsWidgets);
      expect(find.textContaining('Heaviest'), findsNothing);
      expect(find.text('Best e1RM 116.7 kg · +1 more'), findsOneWidget);
      expect(find.textContaining('7-day avg'), findsWidgets);

      // The explanation is one tap away.
      await tester.tap(find.byType(Tooltip).first);
      await tester.pump();
      expect(find.textContaining('Aim for 10–20'), findsOneWidget);

      // Weekly range chips.
      for (final label in ['6M', '1Y', 'All', '3M']) {
        await tester.tap(find.widgetWithText(ChoiceChip, label));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);

      // Year in review.
      await tester.tap(find.text('Year in review'));
      await settle();
      expect(find.text('Training days'), findsOneWidget);
      expect(find.text('Records'), findsNWidgets(2));
      await tester.tapAt(const Offset(160, 20));
      await tester.pumpAndSettle();

      // Entries: edit, delete, undo.
      await tester.tap(find.text('All entries (3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit weigh-in'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '79.5');
      await tester.tap(find.text('Save'));
      await settle();
      expect(find.text('79.5 kg'), findsWidgets);
      expect(
        (await tester.runAsync(() => SettingsRepository(db).get()))!
            .bodyweightKg,
        79.5,
      );

      await tester.tap(find.byTooltip('Delete').first);
      await settle();
      expect(find.textContaining('Deleted'), findsOneWidget);
      expect(find.text('All entries (2)'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await settle();
      expect(find.textContaining('Deleted'), findsNothing);
      expect(find.byTooltip('Delete'), findsNWidgets(3));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      // Closing waits on stream cleanup that never runs in the test zone.
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
