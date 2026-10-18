import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/data/workout_repository.dart';
import 'package:lift_flow/features/history/history_screen.dart';
import 'package:lift_flow/features/history/month_calendar.dart';
import 'package:lift_flow/features/history/workout_times_field.dart';
import 'package:lift_flow/features/history/workout_day_sheet.dart';
import 'package:lift_flow/providers.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

Workout workout(int id, DateTime start, String name) => Workout(
  id: id,
  name: name,
  startedAt: start,
  endedAt: start.add(const Duration(hours: 1)),
  totalSets: 12,
  totalVolumeKg: 4200,
  exerciseCount: 4,
);

void narrow(WidgetTester tester, {double scale = 1}) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets('month calendar at 320 dp, text ×$scale', (tester) async {
      narrow(tester, scale: scale);
      DateTime? tapped;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MonthCalendar(
              now: DateTime(2026, 10, 14),
              firstDay: DateTime.sunday,
              workouts: [
                workout(2, DateTime(2026, 10, 13, 18), 'Legs'),
                workout(1, DateTime(2026, 8, 30, 18), 'Push'),
              ],
              onTapDay: (d) => tapped = d,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('1 workout'), findsWidgets);
      // No paging arrows: the months scroll.
      expect(find.byType(IconButton), findsNothing);
      // Sunday first.
      final october = find.ancestor(
        of: find.text('October 2026'),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_Month',
        ),
      );
      Finder inOctober(String text) =>
          find.descendant(of: october, matching: find.text(text));
      expect(inOctober('S'), findsNWidgets(2));
      expect(
        tester.getTopLeft(inOctober('S').first).dx,
        lessThan(tester.getTopLeft(inOctober('M')).dx),
      );

      await tester.tap(inOctober('13'));
      expect(tapped, DateTime(2026, 10, 13));
      tapped = null;
      await tester.tap(inOctober('12'));
      expect(tapped, isNull);

      // Older months follow below, back to the first one with a workout.
      await tester.scrollUntilVisible(find.text('August 2026'), 200);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('No workouts'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();
      expect(find.text('July 2026'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('history search, empty result and calendar at 320 dp', (
    tester,
  ) async {
    narrow(tester);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = (await tester.runAsync(
      () => SettingsRepository(db).get(),
    ))!;
    final now = DateTime.now();
    final list = [
      workout(
        2,
        now.subtract(const Duration(days: 1)),
        'Legs and a very long workout name',
      ),
      workout(1, now.subtract(const Duration(days: 3)), 'Push'),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(settings),
          historyProvider.overrideWith((ref) => Stream.value(list)),
          templatesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const HistoryScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Push'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'push');
    await tester.pump();
    expect(find.text('Push'), findsOneWidget);
    expect(find.textContaining('Legs'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No matching workouts'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.text('No matching workouts'), findsNothing);
    expect(find.text('Push'), findsOneWidget);

    await tester.tap(find.byTooltip('Show calendar'));
    await tester.pump();
    expect(find.byType(MonthCalendar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('times field shows and edits a past workout at 320 dp', (
    tester,
  ) async {
    narrow(tester, scale: 1.6);
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day - 3);
    final label = DateFormat('EEE d MMM').format(day);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final (settings, id) = (await tester.runAsync(() async {
      final repo = WorkoutRepository(db);
      return (
        await SettingsRepository(db).get(),
        await repo.createPast(
          DateTime(day.year, day.month, day.day, 23, 30),
          DateTime(day.year, day.month, day.day + 1, 0, 30),
        ),
      );
    }))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(settings),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: WorkoutTimesField(workoutId: id)),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text(label), findsOneWidget);
    expect(find.text('23:30'), findsOneWidget);
    expect(find.text('00:30 (+1)'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('day sheet lists the workouts of a day', (tester) async {
    narrow(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: WorkoutDaySheet(
            day: DateTime(2026, 10, 13),
            workouts: [
              workout(1, DateTime(2026, 10, 13, 8), 'Push'),
              workout(2, DateTime(2026, 10, 13, 18), 'Legs'),
            ],
            workoutPath: (id) => '/history/$id',
          ),
        ),
      ),
    );
    expect(find.text('Tue, 13 Oct 2026'), findsOneWidget);
    expect(find.text('Push'), findsOneWidget);
    expect(find.textContaining('12 sets'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
