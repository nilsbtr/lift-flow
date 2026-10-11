import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/exercise_repository.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/data/workout_repository.dart';
import 'package:lift_flow/domain/records.dart';
import 'package:lift_flow/domain/units.dart';
import 'package:lift_flow/features/workout/set_row.dart';
import 'package:lift_flow/features/workout/workout_controller.dart';
import 'package:lift_flow/features/workout/workout_screen.dart';
import 'package:lift_flow/providers.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:lift_flow/widgets/common.dart';
import 'package:lift_flow/widgets/set_list.dart';
import 'package:material_ui/material_ui.dart';

Exercise exercise({
  TrackingType type = TrackingType.weights,
  LoadMode mode = LoadMode.none,
}) => Exercise(
  id: 1,
  name: 'Bench press',
  muscleGroup: MuscleGroup.chest,
  trackingType: type,
  loadMode: mode,
  isArchived: false,
  createdAt: DateTime(2025),
  equipment: Equipment.barbell,
  perSide: false,
  perDumbbell: false,
  secondaryMuscles: const [],
);

WorkoutSet set(
  int id, {
  double? kg,
  int? reps,
  bool done = false,
  SetType type = SetType.normal,
  double? rpe,
  String? note,
}) => WorkoutSet(
  id: id,
  workoutExerciseId: 1,
  position: id - 1,
  loadKg: kg,
  reps: reps,
  isCompleted: done,
  setType: type,
  rpe: rpe,
  note: note,
);

DraftExercise draft(
  List<WorkoutSet> sets, {
  Exercise? of,
  ExerciseBests? bests,
  List<WorkoutSet> previous = const [],
}) => DraftExercise(
  id: 1,
  exercise: of ?? exercise(),
  sets: sets,
  previous: previous,
  bests: bests,
);

SetFact fact(double kg, int reps, {int workoutId = 1, DateTime? at}) => SetFact(
  workoutId: workoutId,
  startedAt: at ?? DateTime(2025, 1, workoutId),
  exerciseId: 1,
  type: TrackingType.weights,
  mode: LoadMode.none,
  loadKg: kg,
  reps: reps,
  bodyweightKg: null,
);

void main() {
  test('effort is stored as RPE and shown as RPE or RIR', () {
    expect(parseEffort('8,5', EffortMode.rpe), 8.5);
    expect(parseEffort('7.3', EffortMode.rpe), 7.5);
    expect(parseEffort('2', EffortMode.rir), 8);
    expect(parseEffort('0', EffortMode.rir), 10);
    expect(parseEffort('0', EffortMode.rpe), isNull);
    expect(parseEffort('11', EffortMode.rpe), isNull);
    expect(parseEffort('', EffortMode.rpe), isNull);
    expect(fmtEffort(8.5, EffortMode.rpe), '8.5');
    expect(fmtEffort(8.5, EffortMode.rir), '1.5');
    expect(fmtEffort(null, EffortMode.rir), '');
    expect(fmtEffortLabel(9, EffortMode.rpe), 'RPE 9');
    expect(fmtEffortLabel(9, EffortMode.rir), '1 RIR');
  });

  group('live records', () {
    test('bestsBefore ignores this and later workouts', () {
      final bests = bestsBefore(
        [fact(80, 5), fact(100, 5, workoutId: 2), fact(120, 5, workoutId: 3)],
        2,
        DateTime(2025, 1, 2),
      );
      expect(bests[1]!.heaviest, 80);
      expect(
        bestsBefore([fact(100, 5, workoutId: 2)], 2, DateTime(2025)),
        isEmpty,
      );
    });

    test('a set must beat the earlier best and the sets above it', () {
      final before = ExerciseBests()..add(fact(80, 5));
      final kinds = liveRecords(before, [
        fact(80, 5),
        null,
        fact(85, 5),
        fact(85, 5),
        fact(85, 6),
      ]);
      expect(kinds[0], isEmpty);
      expect(kinds[1], isEmpty);
      expect(kinds[2], {PrKind.heaviest, PrKind.e1rm});
      expect(kinds[3], isEmpty);
      expect(kinds[4], {PrKind.e1rm});
      expect(before.heaviest, 80);
    });

    test('warm-ups, open sets and exercises without history never count', () {
      final sets = [
        set(1, kg: 200, reps: 5, done: true, type: SetType.warmup),
        set(2, kg: 200, reps: 5),
        set(3, kg: 90, reps: 5, done: true, type: SetType.failure),
      ];
      final bests = ExerciseBests()..add(fact(80, 5));
      expect(draft(sets, bests: bests).records(null).keys, [3]);
      expect(draft(sets).records(null), isEmpty);
    });

    test('bodyweight records use the body weight of the workout', () {
      final ex = exercise(type: TrackingType.bodyweight, mode: LoadMode.added);
      final bests = ExerciseBests()
        ..add(
          SetFact(
            workoutId: 1,
            startedAt: DateTime(2025),
            exerciseId: 1,
            type: ex.trackingType,
            mode: ex.loadMode,
            loadKg: 10,
            reps: 8,
            bodyweightKg: 80,
          ),
        );
      final d = draft(
        [set(1, kg: 10, reps: 9, done: true)],
        of: ex,
        bests: bests,
      );
      expect(d.records(80)[1], {PrKind.e1rm, PrKind.mostReps});
      expect(d.records(null)[1], {PrKind.mostReps});
    });
  });

  test('nextField picks the first empty field of the next open set', () {
    final ex = draft([
      set(1, kg: 80, reps: 8, done: true),
      set(2, kg: 80, reps: 8, done: true),
      set(3),
      set(4, kg: 80),
    ]);
    expect(nextField(ex, 0), (setId: 3, field: SetField.load));
    expect(nextField(ex, 2), isNull, reason: 'set 3 is not completed');
    final filled = draft([set(1, kg: 80, reps: 8, done: true), set(2, kg: 80)]);
    expect(nextField(filled, 0), (setId: 2, field: SetField.reps));
    expect(nextField(filled, 1), isNull);
    final bodyweight = draft([
      set(1, reps: 8, done: true),
      set(2),
    ], of: exercise(type: TrackingType.bodyweight));
    expect(nextField(bodyweight, 0), (setId: 2, field: SetField.reps));
    final last = draft([set(1), set(2, kg: 80, reps: 8, done: true)]);
    expect(nextField(last, 1), isNull);
  });

  group('SetCols.fit', () {
    test('keeps today’s widths at normal text size', () {
      final w = SetCols.fit(336, textScale: 1, load: true);
      expect((w.set, w.load, w.reps), (32, 76, 64));
      expect(w.previous, 336 - 32 - 8 - 76 - 8 - 64 - 48);
      expect(w.inputScale, 1);
    });

    test('Previous shrinks before the inputs do', () {
      final roomy = SetCols.fit(400, textScale: 1.3, load: true, effort: true);
      expect(roomy.load, closeTo(76 * 1.3, 1e-9));
      expect(roomy.inputScale, 1.3);
      expect(roomy.previous, greaterThan(0));

      final tight = SetCols.fit(272, textScale: 2, load: true, effort: true);
      expect(tight.previous, 0);
      expect(tight.load, lessThan(76 * 2));
      expect(tight.inputScale, inInclusiveRange(1, 2));
      expect(
        tight.set + tight.load + tight.reps + tight.effort + 48 + 3 * 8,
        closeTo(272, 1e-9),
      );
    });
  });

  group('editor', () {
    late AppDatabase db;
    late ProviderContainer container;
    late WorkoutRepository repo;
    late Exercise bench;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = WorkoutRepository(db);
      bench = await ExerciseRepository(db).create(
        name: 'Bench press',
        muscleGroup: MuscleGroup.chest,
        trackingType: TrackingType.weights,
      );
      await SettingsRepository(db)
          .write(const AppSettingsCompanion(autoStartRest: Value(false)));
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(
            await SettingsRepository(db).get(),
          ),
        ],
      );
    });
    tearDown(() async {
      container.dispose();
      await pumpEventQueue();
      await db.close();
    });

    /// A live workout with [kg] × 5 logged on each bench set.
    Future<(int, WorkoutEditor)> open(List<double> kg) async {
      final id = await repo.start();
      final (_, sets) = await repo.addExercise(
        id,
        bench.id,
        position: 0,
        sets: kg.length,
      );
      await repo.writeSets([
        for (final (i, s) in sets.indexed)
          s.copyWith(
            loadKg: Value(kg[i]),
            reps: const Value(5),
            isCompleted: true,
          ),
      ]);
      container.listen(workoutEditorProvider(id), (_, _) {});
      await container.read(workoutEditorProvider(id).future);
      return (id, container.read(workoutEditorProvider(id).notifier));
    }

    DraftExercise only(int id) =>
        container.read(workoutEditorProvider(id)).requireValue.exercises.single;

    Future<List<WorkoutSet>> stored(int id) async =>
        (await repo.load(id))!.exercises.single.sets;

    test('undo puts a deleted set back with its values', () async {
      final (id, editor) = await open([60, 70, 80]);
      final ex = only(id);
      final removed = ex.sets[1];

      final settled = editor.removeSet(ex.id, removed.id);
      expect([for (final s in only(id).sets) s.loadKg], [60, 80]);
      expect([for (final s in only(id).sets) s.position], [0, 1]);
      await pumpEventQueue();
      expect(await stored(id), hasLength(3), reason: 'not written yet');

      expect(editor.undoDelete(), isTrue);
      await settled;
      expect(only(id).sets[1], removed);
      expect([for (final s in only(id).sets) s.position], [0, 1, 2]);
      await pumpEventQueue();
      expect([for (final s in await stored(id)) s.loadKg], [60, 70, 80]);
      expect(editor.undoDelete(), isFalse);
    });

    test('a committed delete is written and can’t be undone', () async {
      final (id, editor) = await open([60, 70, 80]);
      final ex = only(id);

      final settled = editor.removeSet(ex.id, ex.sets[0].id);
      await editor.commitDelete(ex.sets[2].id);
      expect(await stored(id), hasLength(3), reason: 'another set’s snackbar');
      await editor.commitDelete(ex.sets[0].id);
      await settled;
      await pumpEventQueue();
      expect([for (final s in await stored(id)) s.loadKg], [70, 80]);
      expect([for (final s in await stored(id)) s.position], [0, 1]);
      expect(editor.undoDelete(), isFalse);
      expect(only(id).sets, hasLength(2));
    });

    test('a second delete commits the first', () async {
      final (id, editor) = await open([60, 70, 80]);
      final ex = only(id);

      final first = editor.removeSet(ex.id, ex.sets[0].id);
      unawaited(editor.removeSet(ex.id, ex.sets[2].id));
      await first;
      expect([for (final s in await stored(id)) s.loadKg], [70, 80]);
      expect(editor.undoDelete(), isTrue);
      expect([for (final s in only(id).sets) s.loadKg], [70, 80]);
    });

    test('finish commits a pending delete', () async {
      final (id, editor) = await open([60, 70]);
      final ex = only(id);

      unawaited(editor.removeSet(ex.id, ex.sets[1].id));
      expect(await editor.finish(), isTrue);
      expect([for (final s in await stored(id)) s.loadKg], [60]);
      expect((await repo.load(id))!.workout.totalSets, 1);
    });

    test('leaving the workout commits a pending delete', () async {
      final (id, editor) = await open([60, 70]);
      final ex = only(id);

      unawaited(editor.removeSet(ex.id, ex.sets[1].id));
      container.invalidate(workoutEditorProvider(id));
      await pumpEventQueue();
      expect([for (final s in await stored(id)) s.loadKg], [60]);
    });

    test('type, effort and note are written', () async {
      final (id, editor) = await open([60]);
      final ex = only(id);
      final s = ex.sets.single;

      editor
        ..setType(ex.id, s.id, SetType.amrap)
        ..setRpe(ex.id, s.id, 9.5)
        ..setNote(ex.id, s.id, ' Paused ');
      editor.flush();
      await pumpEventQueue();
      final saved = (await stored(id)).single;
      expect(
        (saved.setType, saved.rpe, saved.note),
        (SetType.amrap, 9.5, 'Paused'),
      );
      editor.setNote(ex.id, s.id, '');
      expect(only(id).sets.single.note, isNull);
    });

    test('bests come from before the workout and flag a record', () async {
      final (first, editor) = await open([80]);
      expect(only(first).bests, isNull);
      expect(only(first).records(null), isEmpty, reason: 'no earlier history');
      await editor.finish();

      final curls = await ExerciseRepository(db).create(
        name: 'Curl',
        muscleGroup: MuscleGroup.biceps,
        trackingType: TrackingType.weights,
      );
      final (second, live) = await open([80, 85]);
      final ex = only(second);
      expect(ex.bests!.heaviest, 80);
      expect(ex.records(null), {
        ex.sets[1].id: {PrKind.heaviest, PrKind.e1rm},
      });

      live.toggleDone(ex.id, ex.sets[1].id);
      expect(only(second).records(null), isEmpty, reason: 'set reopened');
      live.setType(ex.id, ex.sets[1].id, SetType.warmup);
      live.toggleDone(ex.id, ex.sets[1].id);
      expect(only(second).records(null), isEmpty, reason: 'warm-up');

      await live.addExercises([bench, curls]);
      final added = container
          .read(workoutEditorProvider(second))
          .requireValue
          .exercises;
      expect(added[1].bests!.heaviest, 80);
      expect(added[2].bests, isNull);

      // Editing the first workout still sees no earlier history.
      await live.finish();
      container.listen(workoutEditorProvider(first), (_, _) {});
      await container.read(workoutEditorProvider(first).future);
      expect(only(first).bests, isNull);
    });
  });

  group('large text', () {
    final sets = [
      set(1, kg: 40, reps: 10, done: true, type: SetType.warmup),
      set(2, kg: 102.5, reps: 100, done: true, rpe: 9.5, note: 'Paused'),
      set(3),
    ];
    final ex = draft(
      sets,
      previous: [set(1, kg: 102.5, reps: 12), set(2, kg: 102.5, reps: 12)],
    );

    Widget host(double width, double scale, EffortMode effort, Widget child) =>
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 800),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    // The card sits inside the list's Space.md padding.
                    width: width - 24,
                    child: SingleChildScrollView(child: child),
                  ),
                ),
              ),
            ),
          ),
        );

    for (final effort in EffortMode.values) {
      for (final (width, scale) in [(320.0, 2.0), (320.0, 1.0), (411.0, 1.3)]) {
        testWidgets(
          'set rows fit at $width dp, $scale$kTimes, ${effort.name}',
          (tester) async {
            await tester.pumpWidget(
              host(
                width,
                scale,
                effort,
                Column(
                  children: [
                    SetHeader(
                      exercise: ex,
                      unit: WeightUnit.kg,
                      effort: effort,
                    ),
                    for (var i = 0; i < sets.length; i++)
                      SetRow(
                        workoutId: 1,
                        exercise: ex,
                        index: i,
                        unit: WeightUnit.kg,
                        effort: effort,
                        records: i == 1
                            ? const {PrKind.heaviest, PrKind.e1rm}
                            : const {},
                      ),
                  ],
                ),
              ),
            );
            expect(tester.takeException(), isNull);
            expect(find.text('W'), findsOneWidget);
            expect(find.text('Paused'), findsOneWidget);
            expect(find.text('Heaviest'), findsOneWidget);
            expect(
              find.text('9.5'),
              effort == EffortMode.rpe ? findsOneWidget : findsNothing,
            );
            expect(
              find.text('0.5'),
              effort == EffortMode.rir ? findsOneWidget : findsNothing,
            );
            // Every input keeps a usable width.
            for (final field in tester.widgetList<TextField>(
              find.byType(TextField),
            )) {
              expect(field.controller, isNotNull);
            }
            for (final e in find.byType(TextField).evaluate()) {
              expect(e.size!.width, greaterThanOrEqualTo(36));
            }
          },
        );
      }
    }

    testWidgets('set lists show type, effort and note', (tester) async {
      for (final compact in [false, true]) {
        await tester.pumpWidget(
          host(
            320,
            2,
            EffortMode.rir,
            SetList(
              exercise: exercise(),
              sets: sets.sublist(0, 2),
              unit: WeightUnit.kg,
              effort: EffortMode.rir,
              compact: compact,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining('0.5 RIR', findRichText: true), findsOne);
        expect(find.textContaining('Paused'), findsOne);
      }
      expect(setLabels(sets.map((s) => s.setType)), ['W', '1', '2']);
    });
  });

  testWidgets('logging a workout from the keyboard', (tester) async {
    late AppDatabase db;
    late WorkoutRepository repo;
    late UserSettings settings;
    late int id;
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = WorkoutRepository(db);
      final bench = await ExerciseRepository(db).create(
        name: 'Bench press',
        muscleGroup: MuscleGroup.chest,
        trackingType: TrackingType.weights,
      );
      await SettingsRepository(db)
          .write(const AppSettingsCompanion(autoStartRest: Value(false)));
      settings = await SettingsRepository(db).get();
      id = await repo.start();
      await repo.addExercise(id, bench.id, position: 0, sets: 2);
    });
    Future<void> settle() async {
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(settings),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: WorkoutScreen(workoutId: id),
        ),
      ),
    );
    await settle();
    bool focused(int field) => tester
        .widget<TextField>(find.byType(TextField).at(field))
        .focusNode!
        .hasFocus;
    bool typing() => [0, 1, 2, 3].any(focused);
    final complete = find.byTooltip('Complete set');

    expect(find.text('0 / 2 sets · 0 min'), findsOneWidget);
    expect(find.textContaining('Tap a set number'), findsOneWidget);

    // With the keyboard closed, completing a set leaves it closed.
    await tester.enterText(find.byType(TextField).at(0), '80');
    await tester.enterText(find.byType(TextField).at(1), '8');
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();
    await tester.tap(complete.first);
    await settle();
    expect(find.text('1 / 2 sets · 0 min'), findsOneWidget);
    expect(typing(), isFalse);
    await tester.tap(find.byTooltip('Mark not done'));
    await settle();

    // With it open, the next set's first empty field takes the focus.
    await tester.showKeyboard(find.byType(TextField).at(1));
    await tester.tap(complete.first);
    await settle();
    expect(focused(2), isTrue);

    // Done on the last set closes the keyboard and collapses the card.
    await tester.showKeyboard(find.byType(TextField).at(3));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle();
    expect(find.text('2 / 2 sets · 0 min'), findsOneWidget);
    expect(find.textContaining('2 sets done'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Add set'), findsNothing);

    await tester.tap(find.textContaining('2 sets done'));
    await settle();
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.text('Hide sets'), findsOneWidget);

    // The set number opens the menu, which also retires the hint.
    await tester.tap(find.text('1'));
    await settle();
    await tester.tap(find.text('Warm-up'));
    await settle();
    expect(find.text('W'), findsOneWidget);
    expect(find.textContaining('Tap a set number'), findsNothing);

    await tester.tap(find.text('W'));
    await settle();
    await tester.tap(find.text('Delete set'));
    await settle();
    expect(find.text('Set deleted'), findsOneWidget);
    expect(find.text('1 / 1 sets · 0 min'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle();
    expect(find.text('W'), findsOneWidget);
    expect(find.text('2 / 2 sets · 0 min'), findsOneWidget);

    // Left alone, the snackbar closes and the delete is written.
    await tester.tap(find.text('W'));
    await settle();
    await tester.tap(find.text('Delete set'));
    await settle();
    await tester.pump(const Duration(seconds: 5));
    await settle();
    expect(find.text('Set deleted'), findsNothing);
    final stored = await tester.runAsync(() => repo.load(id));
    expect(stored!.exercises.single.sets.single.setType, SetType.normal);
    expect(
      (await tester.runAsync(SettingsRepository(db).get))!.setMenuHintSeen,
      isTrue,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await pumpEventQueue();
      await db.close();
    });
  });
}
