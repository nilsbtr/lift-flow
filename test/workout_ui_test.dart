import 'dart:ui' show SemanticsAction;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/exercise_repository.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/data/workout_repository.dart';
import 'package:lift_flow/features/workout/finish_dialogs.dart';
import 'package:lift_flow/features/workout/rest_bar.dart';
import 'package:lift_flow/features/workout/trophy_burst.dart';
import 'package:lift_flow/features/workout/workout_controller.dart';
import 'package:lift_flow/features/workout/workout_screen.dart';
import 'package:lift_flow/providers.dart';
import 'package:lift_flow/services/notifications.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// Rest persistence without a database.
class _MemoryRest implements RestRepository {
  RestStateRow? row;

  @override
  Future<RestStateRow?> get() async => row;

  @override
  Future<void> save(DateTime endsAt, int totalSeconds) async =>
      row = RestStateRow(id: 1, endsAt: endsAt, totalSeconds: totalSeconds);

  @override
  Future<void> clear() async => row = null;
}

class _SoundSpy extends NotificationService {
  int plays = 0;

  @override
  Future<void> playRestSound() async => plays++;
}

RestStateRow _ending(Duration after) =>
    RestStateRow(id: 1, endsAt: DateTime.now().add(after), totalSeconds: 60);

void main() {
  group('rest bar', () {
    late ProviderContainer container;
    late _MemoryRest memory;

    setUp(() {
      memory = _MemoryRest();
      container = ProviderContainer(
        overrides: [
          restRepoProvider.overrideWithValue(memory),
          initialRestProvider.overrideWithValue(
            _ending(const Duration(seconds: 60)),
          ),
        ],
      );
    });

    Future<void> pumpBar(WidgetTester tester, {double width = 360}) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(
              body: SizedBox.expand(),
              bottomNavigationBar: RestBar(),
            ),
          ),
        ),
      );
    }

    // The countdown is the first tappable thing in the bar.
    final countdown = find.byType(InkWell).first;

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    }

    for (final (width, scale) in [(320.0, 1.0), (320.0, 2.0), (360.0, 1.3)]) {
      testWidgets('fits $width dp at text scale $scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpBar(tester, width: width);
        expect(find.text('Skip'), findsOneWidget);
        expect(find.text('Custom'), findsNothing);

        await tester.tap(countdown);
        await tester.pumpAndSettle();
        for (final t in ['1:00', '1:30', '2:00', '3:00', 'Custom']) {
          expect(find.text(t), findsWidgets, reason: t);
        }

        await tester.tap(countdown);
        await tester.pumpAndSettle();
        expect(find.text('Custom'), findsNothing);
        await close(tester);
      });
    }

    testWidgets('a preset restarts the countdown with that total', (
      tester,
    ) async {
      await pumpBar(tester);
      await tester.tap(countdown);
      await tester.pumpAndSettle();
      expect(container.read(restTimerProvider)!.totalSeconds, 60);

      await tester.tap(find.text('2:00'));
      await tester.pump();
      var rest = container.read(restTimerProvider)!;
      expect(rest.totalSeconds, 120);
      expect(rest.remainingSeconds(), inInclusiveRange(119, 120));

      // Kept in sync with what the notification actions read.
      await tester.tap(find.text('3:00'));
      await tester.pump();
      rest = container.read(restTimerProvider)!;
      expect(rest.totalSeconds, 180);
      expect(memory.row!.endsAt, rest.endsAt);
      expect(memory.row!.totalSeconds, 180);
      await close(tester);
    });

    testWidgets('holding the countdown or a preset sets a custom time', (
      tester,
    ) async {
      await pumpBar(tester);

      await tester.longPress(countdown);
      await tester.pumpAndSettle();
      expect(find.text('Custom rest'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1:15');
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(container.read(restTimerProvider)!.totalSeconds, 75);

      await tester.tap(countdown);
      await tester.pumpAndSettle();
      await tester.longPress(find.text('2:00'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0:00');
      await tester.pump();
      expect(find.text('Between 0:01 and 60:00'), findsOneWidget);
      final start = find.widgetWithText(TextButton, 'Start');
      expect(tester.widget<TextButton>(start).onPressed, isNull);
      await tester.enterText(find.byType(TextField), '90');
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(container.read(restTimerProvider)!.totalSeconds, 90);
      await close(tester);
    });

    testWidgets('screen readers get the presets and the long press', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpBar(tester);

      final label = find.bySemanticsLabel(RegExp('^Rest, '));
      final node = tester.getSemantics(label);
      final data = node.getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      expect(node.hintOverrides?.onTapHint, 'Show rest presets');
      expect(node.hintOverrides?.onLongPressHint, 'Set a custom rest time');

      await tester.tap(countdown);
      await tester.pumpAndSettle();
      final preset = tester.getSemantics(find.bySemanticsLabel('Rest 2 min'));
      expect(
        preset.getSemanticsData().hasAction(SemanticsAction.longPress),
        isTrue,
      );
      expect(preset.hintOverrides?.onLongPressHint, 'Set a custom rest time');
      expect(find.bySemanticsLabel('Rest 1 min 30 s'), findsOneWidget);
      expect(find.bySemanticsLabel('Custom rest time'), findsOneWidget);
      await close(tester);
      handle.dispose();
    });
  });

  group('rest sound', () {
    late AppDatabase db;
    late _SoundSpy spy;

    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      spy = _SoundSpy();
      // The end of a rest also buzzes the phone.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await db.close();
    });

    Future<ProviderContainer> endingRest({bool sound = true}) async {
      await SettingsRepository(db)
          .write(AppSettingsCompanion(restSound: Value(sound)));
      final c = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          notificationsProvider.overrideWithValue(spy),
          initialSettingsProvider.overrideWithValue(
            await SettingsRepository(db).get(),
          ),
          initialRestProvider.overrideWithValue(
            _ending(const Duration(milliseconds: 200)),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(restTimerProvider), isNotNull);
      return c;
    }

    Future<void> pastEnd(ProviderContainer c) async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(c.read(restTimerProvider), isNull);
    }

    test('plays once when the rest ends with the app open', () async {
      final c = await endingRest();
      await pastEnd(c);
      expect(spy.plays, 1);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(spy.plays, 1);
    });

    test('stays quiet when switched off', () async {
      final c = await endingRest(sound: false);
      await pastEnd(c);
      expect(spy.plays, 0);
    });

    test('stays quiet in the background, where the alert fires', () async {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.hidden,
      );
      final c = await endingRest();
      await pastEnd(c);
      expect(spy.plays, 0);
    });

    test('skipping does not play it', () async {
      final c = await endingRest();
      c.read(restTimerProvider.notifier).skip();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(spy.plays, 0);
    });

    test('a restart plays for the new end only', () async {
      final c = await endingRest();
      c.read(restTimerProvider.notifier).start(1);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(spy.plays, 0);
      expect(c.read(restTimerProvider), isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(spy.plays, 1);
      expect(c.read(restTimerProvider), isNull);
    });

    test('starting caps the rest at an hour', () async {
      final c = await endingRest();
      c.read(restTimerProvider.notifier).start(99999);
      expect(c.read(restTimerProvider)!.totalSeconds, 3600);
    });
  });

  group('finish dialog', () {
    testWidgets('marks sets done and says what is left', (tester) async {
      late AppDatabase db;
      late ProviderContainer container;
      late int id;
      await tester.runAsync(() async {
        db = AppDatabase(NativeDatabase.memory());
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
        id = await repo.start();
        final (_, b) = await repo.addExercise(
          id,
          bench.id,
          position: 0,
          sets: 2,
        );
        await repo.addExercise(id, squat.id, position: 1, sets: 1);
        await repo.writeSets([
          b[0].copyWith(
            loadKg: const Value(80),
            reps: const Value(5),
            isCompleted: true,
          ),
        ]);
        container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            initialSettingsProvider.overrideWithValue(
              await SettingsRepository(db).get(),
            ),
          ],
        );
        await container.read(workoutEditorProvider(id).future);
      });

      bool? result;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await showFinishDialog(context, id),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('2 unchecked sets will be dropped.'), findsOneWidget);

      await tester.tap(find.text('Mark all done'));
      await tester.pump();
      expect(
        find.text(
          'Marked 1 set done. 1 set has no reps or weight to use and will be dropped.',
        ),
        findsOneWidget,
      );
      // Nothing left to mark: the button is gone, finishing stays possible.
      expect(find.text('Mark all done'), findsNothing);
      expect(container.read(restTimerProvider), isNull);

      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(result, isTrue);

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.runAsync(db.close);
    });
  });

  group('live workout screen', () {
    late AppDatabase db;
    late WorkoutRepository repo;
    late ProviderContainer container;
    late GoRouter router;
    late int id;
    late DateTime lastSet;

    /// A live workout that started [ago], with a set done [lastSetAgo] and
    /// [unchecked] more sets to do.
    Future<void> pump(
      WidgetTester tester, {
      required Duration ago,
      Duration lastSetAgo = const Duration(hours: 4),
      bool logged = true,
      int unchecked = 0,
    }) async {
      // The database keeps whole seconds.
      lastSet = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().subtract(lastSetAgo).millisecondsSinceEpoch ~/
            1000 *
            1000,
      );
      await tester.runAsync(() async {
        db = AppDatabase(NativeDatabase.memory());
        repo = WorkoutRepository(db);
        final bench = await ExerciseRepository(db).create(
          name: 'Bench press',
          muscleGroup: MuscleGroup.chest,
          trackingType: TrackingType.weights,
        );
        id = await repo.start();
        await (db.update(db.workouts)..where((w) => w.id.equals(id))).write(
          WorkoutsCompanion(startedAt: Value(DateTime.now().subtract(ago))),
        );
        final (_, sets) = await repo.addExercise(
          id,
          bench.id,
          position: 0,
          sets: 1 + unchecked,
        );
        if (logged) {
          await repo.writeSets([
            sets[0].copyWith(
              loadKg: const Value(80),
              reps: const Value(5),
              isCompleted: true,
              completedAt: Value(lastSet),
            ),
          ]);
        }
        container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            initialSettingsProvider.overrideWithValue(
              await SettingsRepository(db).get(),
            ),
            liveWorkoutProvider.overrideWithValue(await repo.getLive()),
          ],
        );
      });
      router = GoRouter(
        initialLocation: '/workout',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('home')),
          GoRoute(
            path: '/workout',
            builder: (_, _) => const LiveWorkoutRoute(),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> close(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      container.dispose();
      await tester.runAsync(db.close);
    }

    testWidgets('asks once per session and can keep going', (tester) async {
      await pump(tester, ago: const Duration(hours: 6));
      expect(find.text('Still working out?'), findsOneWidget);
      expect(find.textContaining('running for 6 h'), findsOneWidget);
      expect(find.text('Discard'), findsNothing);
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(find.text('Still working out?'), findsNothing);

      // Opening the workout again in the same session doesn't ask again.
      router.go('/');
      await tester.pumpAndSettle();
      router.go('/workout');
      await tester.pumpAndSettle();
      expect(find.text('Still working out?'), findsNothing);
      expect(find.text('Bench press'), findsOneWidget);
      await close(tester);
    });

    testWidgets('ends at the last set', (tester) async {
      await pump(tester, ago: const Duration(hours: 6));
      final clock = DateFormat('HH:mm').format(lastSet);
      await tester.tap(find.text('End at $clock'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      final w = await tester.runAsync(() => repo.load(id));
      expect(w!.workout.endedAt, lastSet);
      await close(tester);
    });

    testWidgets('offers to discard when nothing is logged', (tester) async {
      await pump(tester, ago: const Duration(hours: 6), logged: false);
      expect(find.textContaining('No sets are logged'), findsOneWidget);
      expect(find.textContaining('End at'), findsNothing);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(await tester.runAsync(() => repo.load(id)), isNull);
      await close(tester);
    });

    Future<void> startFinishing(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
      await tester.pumpAndSettle();
      expect(find.text('Finish workout?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Finish'));
      await tester.pumpAndSettle();
    }

    testWidgets('finishing late offers to end at the last set', (tester) async {
      await pump(tester, ago: const Duration(hours: 5), unchecked: 1);
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
      await tester.pumpAndSettle();
      expect(find.text('1 unchecked set will be dropped.'), findsOneWidget);
      await tester.tap(find.text('Mark all done'));
      await tester.pump();
      expect(find.text('Marked 1 set done.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Finish'));
      await tester.pumpAndSettle();

      expect(find.text('End at your last set?'), findsOneWidget);
      expect(find.textContaining('saves 1 h instead of 5 h'), findsOneWidget);
      final clock = DateFormat('HH:mm').format(lastSet);
      await tester.tap(find.text('End at $clock'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);

      final w = (await tester.runAsync(() => repo.load(id)))!;
      expect(w.workout.endedAt, lastSet);
      expect(w.workout.totalSets, 2);
      expect(w.workout.name, 'Chest');
      await close(tester);
    });

    testWidgets('the end can stay at now', (tester) async {
      await pump(tester, ago: const Duration(hours: 5));
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      await startFinishing(tester);
      await tester.tap(find.text('End now'));
      await tester.pumpAndSettle();
      final w = (await tester.runAsync(() => repo.load(id)))!;
      final off = w.workout.endedAt!.difference(DateTime.now()).inSeconds;
      expect(off.abs(), lessThan(5));
      await close(tester);
    });

    testWidgets('dismissing the end offer keeps the workout running', (
      tester,
    ) async {
      await pump(tester, ago: const Duration(hours: 5));
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      await startFinishing(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsNothing);
      final w = (await tester.runAsync(() => repo.load(id)))!;
      expect(w.workout.endedAt, isNull);
      await close(tester);
    });

    testWidgets('a recent last set finishes straight away', (tester) async {
      await pump(
        tester,
        ago: const Duration(hours: 1),
        lastSetAgo: const Duration(minutes: 20),
      );
      await startFinishing(tester);
      expect(find.text('End at your last set?'), findsNothing);
      expect(find.text('home'), findsOneWidget);
      await close(tester);
    });

    testWidgets('the timer button starts and restarts rest', (tester) async {
      await pump(tester, ago: const Duration(hours: 1));
      expect(find.text('Skip'), findsNothing);
      await tester.tap(find.byTooltip('Start rest timer'));
      await tester.pumpAndSettle();
      expect(container.read(restTimerProvider)!.totalSeconds, 90);
      expect(find.text('Skip'), findsOneWidget);

      container.read(restTimerProvider.notifier).start(30);
      await tester.pump();
      await tester.tap(find.byTooltip('Restart rest timer'));
      await tester.pumpAndSettle();
      expect(container.read(restTimerProvider)!.totalSeconds, 90);
      await close(tester);
    });

    testWidgets('leaves a recent workout alone', (tester) async {
      await pump(tester, ago: const Duration(hours: 3));
      expect(find.text('Still working out?'), findsNothing);
      expect(find.text('Bench press'), findsOneWidget);
      await close(tester);
    });
  });

  group('trophy burst', () {
    Widget host() => MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: Center(child: TrophyBurst())),
    );

    testWidgets('plays once and settles', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('is still when animations are off', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.bySemanticsLabel('New record'), findsOneWidget);
      handle.dispose();
    });
  });
}
