import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/exercise_repository.dart';
import 'package:lift_flow/data/photo_storage.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/data/workout_repository.dart';
import 'package:lift_flow/features/gym/exercise_detail_screen.dart';
import 'package:lift_flow/features/gym/gym_screen.dart';
import 'package:lift_flow/features/history/history_screen.dart';
import 'package:lift_flow/features/history/workout_detail_screen.dart';
import 'package:lift_flow/features/home/home_screen.dart';
import 'package:lift_flow/features/lock/lock_gate.dart';
import 'package:lift_flow/features/workout/workout_screen.dart';
import 'package:lift_flow/providers.dart';
import 'package:lift_flow/router.dart';
import 'package:lift_flow/services/notifications.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:lift_flow/widgets/adaptive.dart';
import 'package:lift_flow/widgets/common.dart';
import 'package:material_ui/material_ui.dart';

/// Settings asks the plugin about exact alarms when it opens.
class _NoNotifications extends NotificationService {
  @override
  Future<bool> canScheduleExact() async => true;
}

const phone = Size(400, 800);
const medium = Size(700, 900);
const tablet = Size(1280, 800);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late GoRouter router;
  late Directory photoDir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    photoDir = Directory.systemTemp.createTempSync('lift_flow_tablet_');
  });
  tearDown(() async {
    await db.close();
    if (photoDir.existsSync()) photoDir.deleteSync(recursive: true);
  });

  void resize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
  }

  /// Lets the database streams deliver, then runs the transitions out.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  /// Two finished workouts: "Push day" (bench press) and "Leg day" (squat).
  /// With [live], a third one is still running.
  Future<void> pumpApp(
    WidgetTester tester,
    Size size, {
    double textScale = 1,
    bool live = false,
  }) async {
    resize(tester, size);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final settings = (await tester.runAsync(() async {
      final exercises = ExerciseRepository(db);
      final repo = WorkoutRepository(db);
      for (final (name, exercise, group) in [
        ('Push day', 'Bench press', MuscleGroup.chest),
        ('Leg day', 'Squat', MuscleGroup.quads),
      ]) {
        final ex = await exercises.create(
          name: exercise,
          muscleGroup: group,
          trackingType: TrackingType.weights,
        );
        final id = await repo.start(name: name);
        final (_, sets) = await repo.addExercise(
          id,
          ex.id,
          position: 0,
          sets: 1,
        );
        await repo.writeSets([
          sets.single.copyWith(
            loadKg: const Value(80),
            reps: const Value(5),
            isCompleted: true,
          ),
        ]);
        await repo.finish(id, bodyweightKg: null);
      }
      if (live) await repo.start(name: 'Pull day');
      return SettingsRepository(db).get();
    }))!;

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(settings),
        notificationsProvider.overrideWithValue(_NoNotifications()),
        photoStorageProvider.overrideWithValue(PhotoStorage.at(photoDir)),
      ],
    );
    addTearDown(container.dispose);
    router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (_, child) => AppLockGate(child: child!),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // Closing waits on stream cleanup that never runs in the test zone.
    await tester.pump(const Duration(seconds: 1));
  }

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  Future<void> go(WidgetTester tester, String path) async {
    router.go(path);
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  /// A tab in the bar or rail. The bar slides unselected labels below its
  /// edge, so there it is the whole destination.
  Finder tab(String label) {
    final destination = find.ancestor(
      of: find.text(label),
      matching: find.byType(NavigationDestination),
    );
    return destination.evaluate().isNotEmpty
        ? destination
        : find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text(label),
          );
  }

  double left(WidgetTester tester, Type type) =>
      tester.getTopLeft(find.byType(type)).dx;

  testWidgets('a tab screen makes room for the keyboard once', (tester) async {
    await pumpApp(tester, phone);
    await tap(tester, tab('History'));
    await tap(tester, find.byTooltip('Search'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 380);
    await settle(tester);
    // The list fills the space above the keyboard, and the search field,
    // filters and rows can still be reached.
    expect(
      tester.getBottomLeft(find.byType(HistoryScreen)).dy,
      phone.height - 380,
    );
    await tap(tester, find.text('Leg day'));
    expect(location(), '/history/2');
    await back(tester);
    await tap(tester, find.text('Template'));
    expect(find.text('Nothing to choose from yet.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('history filters by exercise', (tester) async {
    await pumpApp(tester, phone);
    // Straight to History: nothing else has loaded the exercise lists yet.
    await tap(tester, tab('History'));
    await tap(tester, find.byTooltip('Search'));
    await tap(tester, find.text('Exercise'));
    expect(find.text('Bench press'), findsOneWidget);
    await tap(tester, find.text('Squat'));
    expect(find.text('Leg day'), findsOneWidget);
    expect(find.text('Push day'), findsNothing);
    await close(tester);
  });

  testWidgets('a phone keeps the bottom bar and a single pane', (tester) async {
    await pumpApp(tester, phone);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.getSize(find.byType(HomeScreen)).width, phone.width);

    await tap(tester, tab('History'));
    expect(tester.getSize(find.byType(HistoryScreen)).width, phone.width);
    expect(find.byType(DetailPlaceholder), findsNothing);
    // Only the selected tab shows its label; the others are faded out.
    double opacity(String text) => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.descendant(
                  of: find.byType(NavigationBar),
                  matching: find.text(text),
                ),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    expect(opacity('History'), 1);
    expect(opacity('Home'), 0);

    await tap(tester, find.text('Push day'));
    expect(location(), '/history/1');
    expect(find.byType(WorkoutDetailScreen), findsOneWidget);
    expect(find.byType(HistoryScreen), findsNothing); // Covered.

    await back(tester);
    expect(location(), '/history');
    expect(find.byType(HistoryScreen), findsOneWidget);
    await back(tester);
    expect(location(), '/');

    await tap(tester, tab('Gym'));
    await tap(tester, find.text('Squat'));
    expect(location(), '/gym/exercise/2');
    expect(find.byType(GymScreen), findsNothing);
    // Tapping the current tab pops to its root.
    await tap(tester, tab('Gym'));
    expect(location(), '/gym');
    await close(tester);
  });

  testWidgets('a medium window swaps the bar for a rail', (tester) async {
    await pumpApp(tester, medium);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    // One readable column, not edge to edge.
    final rail = tester.getSize(find.byType(NavigationRail)).width;
    expect(tester.getSize(find.byType(HomeScreen)).width, medium.width - rail);

    for (final label in ['Progress', 'Settings', 'History']) {
      await tap(tester, tab(label));
      expect(location(), '/${label.toLowerCase()}');
    }
    // Still one pane: the detail covers the list.
    expect(find.byType(DetailPlaceholder), findsNothing);
    await tap(tester, find.text('Leg day'));
    expect(location(), '/history/2');
    expect(find.byType(WorkoutDetailScreen), findsOneWidget);
    expect(find.byType(HistoryScreen), findsNothing);

    await tap(tester, tab('History'));
    expect(location(), '/history');
    await back(tester);
    expect(location(), '/');
    await close(tester);
  });

  testWidgets('an expanded window shows history beside the workout', (
    tester,
  ) async {
    await pumpApp(tester, tablet);
    await tap(tester, tab('History'));
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.text('Select a workout'), findsOneWidget);
    expect(find.byType(WorkoutDetailScreen), findsNothing);

    bool selected(String name) => tester
        .widget<WorkoutSummaryCard>(
          find.widgetWithText(WorkoutSummaryCard, name),
        )
        .selected;
    expect(selected('Push day'), isFalse);

    await tap(tester, find.text('Push day'));
    expect(location(), '/history/1');
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.byType(WorkoutDetailScreen), findsOneWidget);
    expect(find.text('Select a workout'), findsNothing);
    expect(
      left(tester, HistoryScreen),
      lessThan(left(tester, WorkoutDetailScreen)),
    );
    expect(
      tester.getSize(find.byType(WorkoutDetailScreen)).width,
      kMaxContentWidth,
    );
    expect(selected('Push day'), isTrue);
    expect(selected('Leg day'), isFalse);

    // Another row swaps the detail in place.
    await tap(tester, find.widgetWithText(WorkoutSummaryCard, 'Leg day'));
    expect(location(), '/history/2');
    expect(selected('Leg day'), isTrue);
    expect(
      tester
          .widget<WorkoutDetailScreen>(find.byType(WorkoutDetailScreen))
          .workoutId,
      2,
    );

    // The workout links to its exercise inside the detail pane.
    await tap(
      tester,
      find.descendant(
        of: find.byType(WorkoutDetailScreen),
        matching: find.text('Squat'),
      ),
    );
    expect(location(), '/history/2/exercise/2');
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    expect(selected('Leg day'), isTrue);
    await close(tester);
  });

  testWidgets('an expanded window shows exercises beside the exercise', (
    tester,
  ) async {
    await pumpApp(tester, tablet);
    await tap(tester, tab('Gym'));
    expect(find.byType(GymScreen), findsOneWidget);
    expect(find.text('Select an exercise'), findsOneWidget);

    ListTile row(String name) =>
        tester.widget(find.widgetWithText(ListTile, name));
    await tap(tester, find.text('Bench press'));
    expect(location(), '/gym/exercise/1');
    expect(find.byType(GymScreen), findsOneWidget);
    expect(find.byType(ExerciseDetailScreen), findsOneWidget);
    expect(
      left(tester, GymScreen),
      lessThan(left(tester, ExerciseDetailScreen)),
    );
    expect(row('Bench press').selected, isTrue);
    expect(row('Squat').selected, isFalse);

    // A session links to its workout, which stays in the detail pane.
    await tap(
      tester,
      find
          .descendant(
            of: find.byType(ExerciseDetailScreen),
            matching: find.byType(FlatCard),
          )
          .last,
    );
    expect(location(), '/gym/exercise/1/workout/1');
    expect(find.byType(GymScreen), findsOneWidget);
    expect(find.byType(WorkoutDetailScreen), findsOneWidget);
    expect(
      left(tester, GymScreen),
      lessThan(left(tester, WorkoutDetailScreen)),
    );
    expect(row('Bench press').selected, isTrue);

    await back(tester);
    expect(location(), '/gym/exercise/1');
    expect(find.byType(GymScreen), findsOneWidget);

    // Templates have no detail pane.
    await tap(tester, find.text('Templates'));
    expect(location(), '/gym?tab=templates');
    expect(find.byType(DetailPlaceholder), findsNothing);
    expect(tester.getSize(find.byType(GymScreen)).width, kMaxContentWidth);
    expect(find.text('No templates yet'), findsOneWidget);
    await tap(tester, find.text('Exercises'));
    expect(find.text('Select an exercise'), findsOneWidget);
    await close(tester);
  });

  testWidgets('home and progress details open over the tab', (tester) async {
    await pumpApp(tester, tablet);
    await go(tester, '/workouts/1');
    expect(find.byType(WorkoutDetailScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(DetailPlaceholder), findsNothing);

    await go(tester, '/progress/exercise/1/workout/1');
    expect(find.byType(WorkoutDetailScreen), findsOneWidget);
    await back(tester);
    expect(location(), '/progress/exercise/1');
    await close(tester);
  });

  testWidgets('back closes the detail, then the tab, on a wide window', (
    tester,
  ) async {
    await pumpApp(tester, tablet);
    await go(tester, '/history/1');
    expect(find.byType(WorkoutDetailScreen), findsOneWidget);

    // The detail's own back button closes it too.
    await tap(tester, find.byType(BackButton));
    expect(location(), '/history');
    expect(find.text('Select a workout'), findsOneWidget);

    await go(tester, '/history/1/exercise/1');
    await back(tester);
    expect(location(), '/history/1');
    await back(tester);
    expect(location(), '/history');
    expect(find.byType(HistoryScreen), findsOneWidget);
    await back(tester);
    expect(location(), '/');
    expect(find.byType(HomeScreen), findsOneWidget);
    await close(tester);
  });

  testWidgets('resizing across the breakpoints keeps the place', (
    tester,
  ) async {
    await pumpApp(tester, tablet);
    await go(tester, '/history/1');
    // List state that has to survive the switch between pane and page.
    await tap(tester, find.byTooltip('Search'));
    await tester.enterText(find.byType(TextField), 'day');
    await tester.pump();

    for (final size in [phone, tablet, medium, tablet]) {
      resize(tester, size);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '$size');
      expect(location(), '/history/1', reason: '$size');
      expect(find.byType(WorkoutDetailScreen), findsOneWidget);
      expect(
        find.byType(HistoryScreen),
        size == tablet ? findsOneWidget : findsNothing,
        reason: '$size',
      );
      expect(find.byType(HistoryScreen, skipOffstage: false), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'day', skipOffstage: false),
        findsOneWidget,
        reason: '$size',
      );
    }

    // And on the phone, back still leads to the list.
    resize(tester, phone);
    await settle(tester);
    await back(tester);
    expect(location(), '/history');
    expect(find.widgetWithText(TextField, 'day'), findsOneWidget);
    expect(find.byType(DetailPlaceholder), findsNothing);
    resize(tester, tablet);
    await settle(tester);
    expect(find.text('Select a workout'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'day'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a live workout survives a resize and shows beside the rail', (
    tester,
  ) async {
    await pumpApp(tester, phone, live: true);
    expect(find.text('Pull day'), findsWidgets);
    final bar = find.descendant(
      of: find.byType(AppShell),
      matching: find.textContaining('Rest').hitTestable(),
    );
    expect(bar, findsNothing);

    resize(tester, tablet);
    await settle(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    await tap(tester, tab('History'));
    // The bar sits under both panes, right of the rail.
    final live = find.text('Pull day');
    expect(live, findsOneWidget);
    expect(
      tester.getTopLeft(live).dx,
      greaterThan(tester.getSize(find.byType(NavigationRail)).width),
    );
    expect(
      tester.getTopLeft(live).dy,
      greaterThan(tester.getBottomLeft(find.byType(HistoryScreen)).dy),
    );

    await tap(tester, live);
    expect(location(), '/workout');
    expect(find.byType(WorkoutScreen), findsOneWidget);
    expect(tester.getSize(find.byType(WorkoutScreen)).width, kMaxContentWidth);

    resize(tester, phone);
    await settle(tester);
    expect(location(), '/workout');
    expect(find.byType(WorkoutScreen), findsOneWidget);
    await close(tester);
  });

  testWidgets('the rail layout keeps clear of the system insets', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(left: 40, top: 30, bottom: 20);
    addTearDown(tester.view.resetPadding);
    await pumpApp(tester, tablet, live: true);
    await tap(tester, tab('History'));

    // The rail starts after the cut-out and below the status bar.
    expect(tester.getTopLeft(tab('Home')).dx, greaterThan(40));
    expect(tester.getTopLeft(tab('Home')).dy, greaterThan(30));
    // The list's app bar clears the status bar; nothing sits in the gesture bar.
    expect(tester.getTopLeft(find.text('History').last).dy, greaterThan(30));
    expect(tester.getTopLeft(find.byType(HistoryScreen)).dy, 0);
    expect(
      tester.getBottomLeft(find.text('Pull day')).dy,
      lessThan(tablet.height - 20),
    );
    // The inset is used once: the list starts right after the rail.
    expect(
      tester.getTopLeft(find.byType(HistoryScreen)).dx,
      tester.getTopRight(find.byType(NavigationRail)).dx,
    );
    await close(tester);
  });

  for (final size in [tablet, const Size(840, 600), const Size(800, 360)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'nothing overflows at ${size.width.round()}×${size.height.round()}, '
        'text scale $scale',
        (tester) async {
          await pumpApp(tester, size, textScale: scale, live: true);
          for (final path in [
            '/',
            '/history',
            '/history/1',
            '/history/1/exercise/1',
            '/progress',
            '/progress/workout/2',
            '/progress/photos',
            '/progress/photos/compare',
            '/gym',
            '/gym/exercise/2',
            '/gym/exercise/2/workout/2',
            '/gym?tab=templates',
            '/settings',
            '/workout',
          ]) {
            await go(tester, path);
            expect(tester.takeException(), isNull, reason: path);
            expect(location(), path);
          }
          await close(tester);
        },
      );
    }
  }
}
