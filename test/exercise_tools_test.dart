import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/exercise_repository.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/data/template_repository.dart';
import 'package:lift_flow/data/workout_repository.dart';
import 'package:lift_flow/domain/loading.dart';
import 'package:lift_flow/domain/supersets.dart';
import 'package:lift_flow/domain/units.dart';
import 'package:lift_flow/features/settings/barbell_settings.dart';
import 'package:lift_flow/features/workout/workout_controller.dart';
import 'package:lift_flow/features/workout/workout_screen.dart';
import 'package:lift_flow/providers.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

Exercise exercise({
  int id = 1,
  TrackingType type = TrackingType.weights,
  LoadMode mode = LoadMode.none,
  Equipment equipment = Equipment.barbell,
}) => Exercise(
  id: id,
  name: 'Exercise $id',
  muscleGroup: MuscleGroup.chest,
  trackingType: type,
  loadMode: mode,
  isArchived: false,
  createdAt: DateTime(2025),
  equipment: equipment,
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
}) => WorkoutSet(
  id: id,
  workoutExerciseId: 1,
  position: 0,
  loadKg: kg,
  reps: reps,
  isCompleted: done,
  setType: type,
);

DraftExercise draft(
  List<WorkoutSet> sets, {
  int id = 1,
  Exercise? of,
  List<WorkoutSet> previous = const [],
  int? repsMin,
  int? repsMax,
  double? stepKg = 2.5,
  double? targetWeightKg,
  int? supersetGroup,
}) => DraftExercise(
  id: id,
  exercise: of ?? exercise(id: id),
  sets: sets,
  previous: previous,
  repsMin: repsMin,
  repsMax: repsMax,
  stepKg: stepKg,
  targetWeightKg: targetWeightKg,
  supersetGroup: supersetGroup,
);

WorkoutDraft workout(List<DraftExercise> exercises) => WorkoutDraft(
  workout: Workout(
    id: 1,
    name: 'Workout',
    startedAt: DateTime(2025),
    totalSets: 0,
    totalVolumeKg: 0,
    exerciseCount: 0,
  ),
  exercises: exercises,
);

void main() {
  group('plates', () {
    final kg = defaultPlatesKg(WeightUnit.kg);
    PlateLoad load(double total) => platesFor(total, barKg: 20, plates: kg);

    test('takes the heaviest plates first, per side', () {
      expect(load(100).perSide, [25, 15]);
      expect(load(102.5).perSide, [25, 15, 1.25]);
      expect(load(180).perSide, [25, 25, 25, 5]);
      expect(load(100).remainderKg, 0);
      expect(fmtPlates(load(180), WeightUnit.kg), '3 $kTimes 25 · 5');
      expect(fmtPlates(load(20), WeightUnit.kg), 'Empty bar');
    });

    test('reports what can’t be loaded', () {
      final odd = load(101);
      expect(odd.perSide, [25, 15]);
      expect(odd.remainderKg, closeTo(1, 1e-9));
      expect(fmtPlates(odd, WeightUnit.kg), '25 · 15 · 1 kg left over');
      expect(fmtPlates(load(21), WeightUnit.kg), 'Empty bar · 1 kg left over');

      final light = load(15);
      expect(light.perSide, isEmpty);
      expect(light.remainderKg, -5);
      expect(fmtPlates(light, WeightUnit.kg), 'Lighter than the bar');

      final few = platesFor(100, barKg: 20, plates: [20, 10]);
      expect(few.perSide, [20, 20]);
      expect(few.remainderKg, 0);
      expect(platesFor(100, barKg: 20, plates: []).remainderKg, 80);
    });

    test('pound defaults work on values stored in kg', () {
      const lb = WeightUnit.lb;
      final bar = BarSetup.of(null, null, lb);
      expect(kgToUnit(bar.barKg, lb), closeTo(45, 1e-9));
      final l = bar.load(unitToKg(225, lb));
      expect(fmtPlates(l, lb), '2 $kTimes 45');
      expect(l.remainderKg, 0);
      expect(fmtPlates(bar.load(unitToKg(140, lb)), lb), '45 · 2.5');
      expect(fmtPlates(bar.load(unitToKg(137, lb)), lb), '45 · 2 lb left over');
    });

    test('settings are parsed, with defaults per unit', () {
      expect(barWeightKg(null, WeightUnit.kg), 20);
      expect(barWeightKg(15, WeightUnit.lb), 15);
      expect(parsePlates(null, WeightUnit.kg), kg);
      expect(parsePlates('5, 20,x,-1,10,20', WeightUnit.kg), [20, 10, 5]);
      expect(parsePlates('', WeightUnit.kg), isEmpty);
      expect(encodePlates([5, 20, 10, 20]), '20.0,10.0,5.0');
      final lb = defaultPlatesKg(WeightUnit.lb);
      expect(parsePlates(encodePlates(lb), WeightUnit.kg), lb);
      for (final unit in WeightUnit.values) {
        expect(
          plateChoicesKg(unit),
          containsAll(defaultPlatesKg(unit)),
          reason: unit.name,
        );
      }
    });
  });

  group('loads', () {
    test('the step follows the equipment and the unit', () {
      const kg = WeightUnit.kg;
      const lb = WeightUnit.lb;
      expect(loadStep(Equipment.barbell, kg, defaultPlatesKg(kg)), 2.5);
      expect(loadStep(Equipment.barbell, kg, [20, 2.5]), 5);
      expect(loadStep(Equipment.barbell, kg, []), 2.5);
      expect(loadStep(Equipment.dumbbell, kg, [20]), 2.5);
      expect(loadStep(Equipment.kettlebell, kg, [20]), 4);
      expect(
        kgToUnit(loadStep(Equipment.barbell, lb, defaultPlatesKg(lb)), lb),
        closeTo(5, 1e-9),
      );
      expect(
        kgToUnit(loadStep(Equipment.machine, lb, const []), lb),
        closeTo(5, 1e-9),
      );
    });

    test('rounding stays on loadable weights', () {
      expect(roundLoad(51.2, 2.5), 50);
      expect(roundLoad(51.3, 2.5), 52.5);
      expect(roundLoad(43, 5, base: 20), 45);
      expect(roundLoad(12, 5, base: 20), 20);
    });

    test('warm-ups ramp from the bar to 85 %', () {
      expect(warmupSets(100, step: 2.5, barKg: 20), [
        (loadKg: 20.0, reps: 10),
        (loadKg: 50.0, reps: 5),
        (loadKg: 70.0, reps: 3),
        (loadKg: 85.0, reps: 2),
      ]);
      // Without a bar there is no empty-bar set.
      expect(
        [for (final w in warmupSets(30, step: 2.5)) w.loadKg],
        [15, 20, 25],
      );
      // Steps that round to the same load, or to the working weight, go.
      expect(
        [for (final w in warmupSets(30, step: 2.5, barKg: 20)) w.loadKg],
        [20, 25],
      );
      expect(warmupSets(20, step: 2.5, barKg: 20), isEmpty);
      expect(warmupSets(2.5, step: 2.5), isEmpty);
    });

    test('warm-ups are offered for weights with a known working weight', () {
      final open = [set(1), set(2)];
      expect(draft(open).warmups(barKg: 20), isEmpty, reason: 'no weight');
      expect(draft([set(1, kg: 100), set(2)]).warmups(barKg: 20), hasLength(4));
      final hinted = draft(open, previous: [set(9, kg: 60, reps: 8)]);
      expect(
        [for (final w in hinted.warmups(barKg: 20)) w.loadKg],
        [20, 30, 42.5, 50],
      );
      final dumbbell = draft([
        set(1, kg: 30),
      ], of: exercise(equipment: Equipment.dumbbell));
      expect(dumbbell.warmups(barKg: 20).first.loadKg, 15);

      expect(
        draft([set(1, kg: 40, type: SetType.warmup), set(2, kg: 100)])
            .warmups(barKg: 20),
        isEmpty,
        reason: 'has warm-ups',
      );
      expect(
        draft([set(1, kg: 100, reps: 5, done: true)]).warmups(barKg: 20),
        isEmpty,
        reason: 'already working',
      );
      expect(
        draft(
          [set(1, kg: 10)],
          of: exercise(type: TrackingType.bodyweight, mode: LoadMode.added),
        ).warmups(barKg: 20),
        isEmpty,
        reason: 'bodyweight',
      );
    });
  });

  group('hints', () {
    final open = [set(1), set(2), set(3)];
    List<WorkoutSet> last(List<int> reps, {double kg = 60}) => [
      for (final (i, r) in reps.indexed) set(10 + i, kg: kg, reps: r),
    ];

    test('suggest the next weight once every set reached the top', () {
      final ex = draft(
        [...open, set(4)],
        previous: last([12, 12, 13]),
        repsMin: 8,
        repsMax: 12,
      );
      expect(ex.increaseKg, 2.5);
      expect(ex.hintFor(0), (load: 62.5, reps: 8, increase: true));
      expect(ex.hintFor(2), (load: 62.5, reps: 8, increase: true));
      // A set the last session didn't have follows the one above.
      expect(ex.hintFor(3), (load: 62.5, reps: 8, increase: true));
    });

    test('copy the last session otherwise', () {
      final short = draft(
        open,
        previous: last([12, 12, 11]),
        repsMin: 8,
        repsMax: 12,
      );
      expect(short.increaseKg, isNull);
      expect(short.hintFor(2), (load: 60.0, reps: 11, increase: false));

      final top = last([12, 12, 12]);
      expect(draft(open, previous: top).increaseKg, isNull);
      expect(draft(open, previous: top, repsMin: 12).increaseKg, isNull);
      expect(
        draft(
          open,
          previous: top,
          repsMin: 8,
          repsMax: 12,
          stepKg: null,
        ).increaseKg,
        isNull,
      );
      expect(
        draft(
          open,
          previous: top,
          repsMin: 8,
          repsMax: 12,
          of: exercise(type: TrackingType.bodyweight, mode: LoadMode.added),
        ).hintFor(0),
        (load: 60.0, reps: 12, increase: false),
      );
      expect(draft(open, repsMin: 8, repsMax: 12).increaseKg, isNull);
    });

    test('line up warm-ups with warm-ups', () {
      final previous = [
        set(10, kg: 20, reps: 10, type: SetType.warmup),
        set(11, kg: 60, reps: 12),
        set(12, kg: 60, reps: 12),
      ];
      final mirrored = draft(
        [set(1, type: SetType.warmup), set(2), set(3)],
        previous: previous,
        repsMin: 8,
        repsMax: 12,
      );
      expect(mirrored.hintFor(0), (load: 20.0, reps: 10, increase: false));
      expect(mirrored.hintFor(1), (load: 62.5, reps: 8, increase: true));

      // No warm-up this time: the first set repeats the first working set.
      final plain = draft([set(1), set(2)], previous: previous);
      expect(plain.previousFor(0)!.id, 11);
      expect(plain.hintFor(0).load, 60);
      // A warm-up the last session didn't have gets no working-set values.
      final extra = draft([
        set(1, type: SetType.warmup),
        set(2, type: SetType.warmup),
        set(3),
      ], previous: previous);
      expect(extra.previousFor(1), isNull);
      expect(extra.hintFor(1), (load: 20.0, reps: 10, increase: false));
      expect(extra.hintFor(2).load, 60);
    });

    test('fall back to the target weight without a previous session', () {
      final ex = draft(open, repsMin: 8, repsMax: 12, targetWeightKg: 40);
      expect(ex.hintFor(0), (load: 40.0, reps: 8, increase: false));
      expect(ex.hintFor(2), (load: 40.0, reps: 8, increase: false));
      final typed = draft([set(1, kg: 50), set(2)], targetWeightKg: 40);
      expect(typed.hintFor(1).load, 50);
      final known = draft(open, previous: last([8]), targetWeightKg: 40);
      expect(known.hintFor(0).load, 60);
      expect(
        draft(
          open,
          targetWeightKg: 40,
          of: exercise(type: TrackingType.bodyweight),
        ).hintFor(0).load,
        isNull,
      );
    });
  });

  group('supersets', () {
    test('are runs of neighbours with the same group', () {
      final groups = [1, 1, null, 2, 3, 3, 3, 1];
      expect(supersetSpans(groups), [
        (index: 0, count: 2),
        (index: 1, count: 2),
        null,
        null,
        (index: 0, count: 3),
        (index: 1, count: 3),
        (index: 2, count: 3),
        null,
      ]);
      expect(dropLoneGroups(groups), [1, 1, null, null, 3, 3, 3, null]);
      expect(supersetLabel(2), 'Superset');
      expect(supersetLabel(3), 'Circuit');
    });

    test('link with the exercise below', () {
      expect(linkGroups([null, null, null], 0), [1, 1, null]);
      expect(linkGroups([1, 1, null], 1), [2, 2, 2]);
      expect(linkGroups([1, 1, 4, 4], 1), [5, 5, 5, 5]);
      expect(linkGroups([1, 1, null], 0), [1, 1, null], reason: 'linked');
      expect(linkGroups([null, null], 1), [null, null], reason: 'last');
    });

    test('stay together when reordering', () {
      const a = ('A', 1), b = ('B', 1), c = ('C', null), d = ('D', null);
      String move(List<(String, int?)> list, int from, int to) =>
          moveGrouped(list, from, to, (x) => x.$2).map((x) => x.$1).join();
      const list = [a, b, c, d];
      expect(move(list, 0, 1), 'BACD', reason: 'inside its superset');
      expect(move(list, 0, 3), 'CDAB', reason: 'the superset moves along');
      expect(move(list, 1, 2), 'CABD');
      expect(move(list, 2, 1), 'CABD', reason: 'not into a superset');
      expect(move(list, 3, 1), 'DABC');
      expect(move(list, 3, 2), 'ABDC');
      expect(move(list, 2, 2), 'ABCD');
      const two = [a, b, ('C', 2), ('D', 2)];
      expect(move(two, 0, 2), 'CDAB');
      expect(move(two, 3, 1), 'CDAB');
      expect(move(two, 2, 3), 'ABDC');
      expect(move([c], 0, 0), 'C');
    });

    DraftExercise a(List<WorkoutSet> sets) => draft(sets, supersetGroup: 1);
    DraftExercise b(List<WorkoutSet> sets) =>
        draft(sets, id: 2, supersetGroup: 1);

    test('focus alternates and rest waits for the round', () {
      var d = workout([
        a([set(11, kg: 60, reps: 8, done: true), set(12)]),
        b([set(21), set(22, kg: 20)]),
      ]);
      expect(nextFocus(d, 1, 0), (setId: 21, field: SetField.load));
      expect(roundOpen(d, 1, 0), isTrue);

      d = workout([
        a([set(11, kg: 60, reps: 8, done: true), set(12)]),
        b([set(21, kg: 20, reps: 8, done: true), set(22, kg: 20)]),
      ]);
      expect(nextFocus(d, 2, 0), (setId: 12, field: SetField.load));
      expect(roundOpen(d, 2, 0), isFalse);

      // Done out of order, the round still ends with its last open set.
      d = workout([
        a([set(11), set(12)]),
        b([set(21, kg: 20, reps: 8, done: true), set(22, kg: 20)]),
      ]);
      expect(nextFocus(d, 2, 0), (setId: 11, field: SetField.load));
      expect(roundOpen(d, 2, 0), isTrue);

      d = workout([
        a([
          set(11, kg: 60, reps: 8, done: true),
          set(12, kg: 60, reps: 8, done: true),
        ]),
        b([set(21, kg: 20, reps: 8, done: true)]),
      ]);
      expect(nextFocus(d, 1, 1), isNull, reason: 'last set of the superset');
      expect(roundOpen(d, 1, 1), isFalse, reason: 'no partner set');
      expect(nextFocus(d, 1, 0), isNull);
    });

    test('warm-ups and single exercises keep the plain order', () {
      final warm = workout([
        a([
          set(10, kg: 20, reps: 10, done: true, type: SetType.warmup),
          set(11, kg: 60, reps: 8, done: true),
          set(12),
        ]),
        b([set(21), set(22)]),
      ]);
      expect(nextFocus(warm, 1, 0), (setId: 12, field: SetField.load));
      expect(roundOpen(warm, 1, 0), isFalse);
      // The first working set is round one in both exercises.
      expect(nextFocus(warm, 1, 1), (setId: 21, field: SetField.load));

      final ex = draft([set(1, kg: 60, reps: 8, done: true), set(2, kg: 60)]);
      final alone = workout([
        ex,
        draft([set(21)], id: 2),
      ]);
      expect(nextFocus(alone, 1, 0), nextField(ex, 0));
      expect(nextFocus(alone, 1, 0), (setId: 2, field: SetField.reps));
      expect(roundOpen(alone, 1, 0), isFalse);
      expect(alone.supersetOf(1), [ex]);
    });
  });

  group('editor', () {
    late AppDatabase db;
    late ProviderContainer container;
    late WorkoutRepository repo;
    late ExerciseRepository exercises;
    late Exercise bench;
    late Exercise row;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = WorkoutRepository(db);
      exercises = ExerciseRepository(db);
      bench = await exercises.create(
        name: 'Bench press',
        muscleGroup: MuscleGroup.chest,
        trackingType: TrackingType.weights,
        equipment: Equipment.barbell,
      );
      row = await exercises.create(
        name: 'Row',
        muscleGroup: MuscleGroup.back,
        trackingType: TrackingType.weights,
        equipment: Equipment.cable,
      );
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

    /// A live workout with [sets] open sets of each of [list].
    Future<(int, WorkoutEditor)> open(
      List<Exercise> list, {
      int sets = 2,
    }) async {
      final id = await repo.start();
      for (final (i, e) in list.indexed) {
        await repo.addExercise(id, e.id, position: i, sets: sets);
      }
      container.listen(workoutEditorProvider(id), (_, _) {});
      await container.read(workoutEditorProvider(id).future);
      return (id, container.read(workoutEditorProvider(id).notifier));
    }

    List<DraftExercise> drafts(int id) =>
        container.read(workoutEditorProvider(id)).requireValue.exercises;

    void log(WorkoutEditor editor, DraftExercise ex, int index, double kg) {
      final s = ex.sets[index];
      editor
        ..setLoad(ex.id, s.id, kg)
        ..setReps(ex.id, s.id, 8);
      expect(editor.toggleDone(ex.id, s.id), CompleteResult.ok);
    }

    Future<List<LoadedExercise>> stored(int id) async =>
        (await repo.load(id))!.exercises;

    /// Finishes a workout and dates it [days] back, so "last session" is
    /// never a tie between workouts started in the same second.
    Future<void> finish(WorkoutEditor editor, int id, int days) async {
      container.read(restTimerProvider.notifier).skip();
      expect(await editor.finish(), isTrue);
      final start = DateTime.now().subtract(Duration(days: days));
      await repo.setTimes(id, start, start.add(const Duration(hours: 1)));
    }

    test('rest starts after the last exercise of a round', () async {
      final (id, editor) = await open([bench, row]);
      final [a, b] = drafts(id);
      await editor.linkWithNext(a.id);
      expect(drafts(id).map((e) => e.supersetGroup), [1, 1]);
      expect((await stored(id)).map((e) => e.row.supersetGroup), [1, 1]);

      log(editor, a, 0, 60);
      expect(container.read(restTimerProvider), isNull);
      log(editor, b, 0, 40);
      expect(container.read(restTimerProvider)!.totalSeconds, 90);

      container.read(restTimerProvider.notifier).skip();
      editor.setRest(b.id, 150);
      log(editor, b, 1, 40);
      expect(container.read(restTimerProvider), isNull);
      log(editor, a, 1, 60);
      expect(
        container.read(restTimerProvider)!.totalSeconds,
        90,
        reason: 'the rest of the exercise that ends the round',
      );
      container.read(restTimerProvider.notifier).skip();
    });

    test(
      'a single exercise rests after every set, with its own time',
      () async {
        final (id, editor) = await open([bench]);
        final a = drafts(id).single;
        editor.setRest(a.id, 150);
        log(editor, a, 0, 60);
        expect(container.read(restTimerProvider)!.totalSeconds, 150);
        editor.setRest(a.id, null);
        log(editor, a, 1, 60);
        expect(container.read(restTimerProvider)!.totalSeconds, 90);
        await pumpEventQueue();
        expect((await stored(id)).single.row.restSeconds, isNull);
        container.read(restTimerProvider.notifier).skip();
      },
    );

    test('unlinking and removing clean up the superset', () async {
      final curl = await exercises.create(
        name: 'Curl',
        muscleGroup: MuscleGroup.biceps,
        trackingType: TrackingType.weights,
      );
      final (id, editor) = await open([bench, row, curl]);
      final [a, b, c] = drafts(id);
      await editor.linkWithNext(a.id);
      await editor.linkWithNext(b.id);
      expect(drafts(id).map((e) => e.supersetGroup).toSet(), {2});

      // From the middle, the exercise moves below the others.
      await editor.unlink(b.id);
      expect(drafts(id).map((e) => e.id), [a.id, c.id, b.id]);
      expect(drafts(id).map((e) => e.supersetGroup), [2, 2, null]);
      expect((await stored(id)).map((e) => (e.row.id, e.row.supersetGroup)), [
        (a.id, 2),
        (c.id, 2),
        (b.id, null),
      ]);

      // Dragging one of them out takes the other along.
      await editor.reorder(0, 2);
      expect(drafts(id).map((e) => e.id), [b.id, a.id, c.id]);
      expect((await stored(id)).map((e) => e.row.id), [b.id, a.id, c.id]);

      await editor.removeExercise(c.id);
      expect(drafts(id).map((e) => e.supersetGroup), [null, null]);
      expect((await stored(id)).map((e) => e.row.supersetGroup), [null, null]);
    });

    test('finishing drops the group of a lone partner', () async {
      final (id, editor) = await open([bench, row]);
      final [a, _] = drafts(id);
      await editor.linkWithNext(a.id);
      log(editor, a, 0, 60);
      container.read(restTimerProvider.notifier).skip();
      expect(await editor.finish(), isTrue);
      final left = (await stored(id)).single;
      expect(left.exercise.id, bench.id);
      expect(left.row.supersetGroup, isNull);
    });

    test('a finished superset keeps its group', () async {
      final (id, editor) = await open([bench, row], sets: 1);
      final [a, b] = drafts(id);
      await editor.linkWithNext(a.id);
      log(editor, a, 0, 60);
      log(editor, b, 0, 40);
      await editor.finish();
      expect((await stored(id)).map((e) => e.row.supersetGroup), [1, 1]);
    });

    test('notes are kept and shown with the session', () async {
      final (id, editor) = await open([bench]);
      final a = drafts(id).single;
      await editor.setWorkoutNote(' Short on sleep ');
      editor.setExerciseNote(a.id, ' Left knee sore ');
      expect(drafts(id).single.note, 'Left knee sore');
      log(editor, a, 0, 60);
      container.read(restTimerProvider.notifier).skip();
      await editor.finish();

      final loaded = (await repo.load(id))!;
      expect(loaded.workout.note, 'Short on sleep');
      expect(loaded.exercises.single.row.note, 'Left knee sore');
      final session = (await repo.watchExerciseSessions(bench.id).first).single;
      expect(session.note, 'Left knee sore');

      container.listen(workoutEditorProvider(id), (_, _) {});
      await container.read(workoutEditorProvider(id).future);
      final again = container.read(workoutEditorProvider(id).notifier);
      expect(drafts(id).single.note, 'Left knee sore');
      again.setExerciseNote(a.id, '');
      await again.setWorkoutNote('');
      await pumpEventQueue();
      final cleared = (await repo.load(id))!;
      expect(cleared.workout.note, isNull);
      expect(cleared.exercises.single.row.note, isNull);
      expect(
        (await repo.watchExerciseSessions(bench.id).first).single.note,
        isNull,
      );
    });

    test('replace keeps place, sets and superset', () async {
      // Row has history, bench has none.
      final (first, before) = await open([row], sets: 1);
      log(before, drafts(first).single, 0, 40);
      await finish(before, first, 1);

      final (id, editor) = await open([bench, row]);
      final [a, b] = drafts(id);
      await editor.linkWithNext(a.id);
      editor.setExerciseNote(a.id, 'Rack taken');
      editor.setRest(a.id, 120);
      log(editor, a, 0, 60);
      editor.setLoad(a.id, a.sets[1].id, 62.5);
      expect(a.previous, isEmpty);

      final curl = await exercises.create(
        name: 'Curl',
        muscleGroup: MuscleGroup.biceps,
        trackingType: TrackingType.weights,
        equipment: Equipment.kettlebell,
      );
      expect(await editor.replaceExercise(a.id, curl), isFalse);
      var now = drafts(id).first;
      expect(now.id, a.id);
      expect(now.exercise.id, curl.id);
      expect(
        (now.note, now.restSeconds, now.supersetGroup),
        ('Rack taken', 120, 1),
      );
      expect(now.sets.map((s) => (s.loadKg, s.reps, s.isCompleted)), [
        (60.0, 8, true),
        (62.5, null, false),
      ]);
      expect(now.stepKg, 4, reason: 'kettlebell');
      await pumpEventQueue();
      var saved = await stored(id);
      expect(saved.map((e) => e.exercise.id), [curl.id, row.id]);
      expect(saved.first.sets.map((s) => s.loadKg), [60, 62.5]);

      // Hints and bests come from the new exercise.
      await editor.removeExercise(b.id);
      expect(await editor.replaceExercise(a.id, row), isFalse);
      now = drafts(id).single;
      expect(now.previous.single.loadKg, 40);
      expect(now.bests!.heaviest, 40);
      expect(now.supersetGroup, isNull);

      // A different way to track load clears the loads.
      final pullUp = await exercises.create(
        name: 'Pull-up',
        muscleGroup: MuscleGroup.back,
        trackingType: TrackingType.bodyweight,
      );
      expect(await editor.replaceExercise(a.id, pullUp), isTrue);
      now = drafts(id).single;
      expect(now.previous, isEmpty);
      expect(now.bests, isNull);
      expect(now.sets.map((s) => (s.loadKg, s.reps, s.isCompleted)), [
        (null, 8, true),
        (null, null, false),
      ]);

      // Weights need a load, so a completed set is opened again.
      expect(await editor.replaceExercise(a.id, bench), isFalse);
      now = drafts(id).single;
      expect(now.sets.map((s) => (s.loadKg, s.reps, s.isCompleted)), [
        (null, 8, false),
        (null, null, false),
      ]);
      await pumpEventQueue();
      saved = await stored(id);
      expect(saved.single.exercise.id, bench.id);
      expect(saved.single.sets.map((s) => s.isCompleted), [false, false]);

      final dip = await exercises.create(
        name: 'Dip',
        muscleGroup: MuscleGroup.chest,
        trackingType: TrackingType.bodyweight,
        loadMode: LoadMode.added,
      );
      log(editor, now, 0, 60);
      container.read(restTimerProvider.notifier).skip();
      expect(await editor.replaceExercise(a.id, dip), isTrue);
      expect(drafts(id).single.sets.map((s) => (s.loadKg, s.isCompleted)), [
        (0.0, true),
        (null, false),
      ]);
    });

    test('warm-up sets go before the first working set', () async {
      final (id, editor) = await open([bench]);
      final a = drafts(id).single;
      expect(a.warmups(barKg: 20), isEmpty);
      await editor.addWarmups(a.id);
      expect(drafts(id).single.sets, hasLength(2), reason: 'no weight yet');

      editor.setLoad(a.id, a.sets[0].id, 100);
      await editor.addWarmups(a.id);
      final now = drafts(id).single;
      expect(now.sets.map((s) => (s.setType.letter, s.loadKg, s.reps)), [
        ('W', 20.0, 10),
        ('W', 50.0, 5),
        ('W', 70.0, 3),
        ('W', 85.0, 2),
        ('', 100.0, null),
        ('', null, null),
      ]);
      expect(now.sets.every((s) => !s.isCompleted), isTrue);
      expect(now.warmups(barKg: 20), isEmpty);
      await pumpEventQueue();
      final saved = (await stored(id)).single.sets;
      expect(saved.map((s) => s.position), [0, 1, 2, 3, 4, 5]);
      expect(saved.map((s) => s.loadKg), [20, 50, 70, 85, 100, null]);
      expect(saved.take(4).every((s) => s.setType.isWarmup), isTrue);
    });

    test('the bar and plates from settings shape warm-ups and steps', () async {
      final (id, editor) = await open([bench, row]);
      final a = drafts(id).first;
      expect(drafts(id).map((e) => e.stepKg), [2.5, 2.5]);
      await container
          .read(settingsProvider.notifier)
          .update(
            const AppSettingsCompanion(
              barWeightKg: Value(15),
              plates: Value('20,10,5'),
            ),
          );
      expect(drafts(id).map((e) => e.stepKg), [10, 2.5]);
      editor.setLoad(a.id, a.sets[0].id, 100);
      await editor.addWarmups(a.id);
      expect(drafts(id).first.sets.take(4).map((s) => s.loadKg), [
        15,
        55,
        75,
        85,
      ]);

      await container
          .read(settingsProvider.notifier)
          .update(
            const AppSettingsCompanion(
              weightUnit: Value(WeightUnit.lb),
              plates: Value(null),
            ),
          );
      expect(
        kgToUnit(drafts(id).first.stepKg!, WeightUnit.lb),
        closeTo(5, 1e-9),
      );
    });

    test('a template’s range and target weight drive the hints', () async {
      final tid = await TemplateRepository(db).save(
        name: 'Push',
        items: [
          TemplateItem(
            exercise: bench,
            targetSets: 2,
            repsMin: 8,
            repsMax: 12,
            targetWeightKg: 50,
            restSeconds: 120,
          ),
        ],
      );
      Future<(int, WorkoutEditor)> start() async {
        final id = await repo.start(templateId: tid);
        container.listen(workoutEditorProvider(id), (_, _) {});
        await container.read(workoutEditorProvider(id).future);
        return (id, container.read(workoutEditorProvider(id).notifier));
      }

      final (first, one) = await start();
      var ex = drafts(first).single;
      expect(ex.hintFor(0), (load: 50.0, reps: 8, increase: false));
      expect(ex.restSeconds, 120);
      for (final s in ex.sets) {
        one.setReps(ex.id, s.id, 12);
        expect(one.toggleDone(ex.id, s.id), CompleteResult.ok);
      }
      expect(container.read(restTimerProvider)!.totalSeconds, 120);
      expect(drafts(first).single.sets.map((s) => s.loadKg), [50, 50]);
      await finish(one, first, 2);

      final (second, two) = await start();
      ex = drafts(second).single;
      expect(ex.increaseKg, 2.5);
      expect(ex.hintFor(1), (load: 52.5, reps: 8, increase: true));
      // Completing an empty set takes the suggestion.
      expect(two.toggleDone(ex.id, ex.sets[0].id), CompleteResult.ok);
      final done = drafts(second).single.sets.first;
      expect((done.loadKg, done.reps), (52.5, 8));
      two.setReps(ex.id, ex.sets[1].id, 9);
      two.toggleDone(ex.id, ex.sets[1].id);
      await finish(two, second, 1);

      final (third, _) = await start();
      ex = drafts(third).single;
      expect(ex.increaseKg, isNull);
      expect(ex.hintFor(0), (load: 52.5, reps: 8, increase: false));
      expect(ex.hintFor(1), (load: 52.5, reps: 9, increase: false));
    });
  });

  group('widgets', () {
    late AppDatabase db;
    late UserSettings settings;
    late int id;

    /// Bench and row as a superset from a template, after a session that
    /// reached the top of the bench range.
    Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory());
      final repo = WorkoutRepository(db);
      final exercises = ExerciseRepository(db);
      final bench = await exercises.create(
        name: 'Incline dumbbell bench press',
        muscleGroup: MuscleGroup.chest,
        trackingType: TrackingType.weights,
        equipment: Equipment.barbell,
        notes: 'Elbows tucked',
      );
      final row = await exercises.create(
        name: 'Row',
        muscleGroup: MuscleGroup.back,
        trackingType: TrackingType.weights,
      );
      final tid = await TemplateRepository(db).save(
        name: 'Upper',
        items: [
          TemplateItem(
            exercise: bench,
            targetSets: 2,
            repsMin: 8,
            repsMax: 12,
            restSeconds: 120,
            supersetGroup: 1,
          ),
          TemplateItem(exercise: row, targetSets: 2, supersetGroup: 1),
        ],
      );
      await SettingsRepository(db).write(
        const AppSettingsCompanion(
          autoStartRest: Value(false),
          setMenuHintSeen: Value(true),
        ),
      );
      settings = await SettingsRepository(db).get();
      final first = await repo.start(templateId: tid);
      await repo.writeSets([
        for (final e in (await repo.load(first))!.exercises)
          for (final s in e.sets)
            s.copyWith(
              loadKg: const Value(60),
              reps: const Value(12),
              isCompleted: true,
            ),
      ]);
      await repo.finish(first, bodyweightKg: null);
      id = await repo.start(templateId: tid);
      final live = (await repo.load(id))!;
      await repo.setNote(id, 'Short on sleep');
      await repo.updateExercise(
        live.exercises.first.row.id,
        const WorkoutExercisesCompanion(note: Value('Left knee sore')),
      );
    });

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await pumpEventQueue();
        await db.close();
      });
    }

    Widget app(Widget home) => ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    );

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('superset cards fit at 320 dp, text ×$scale', (tester) async {
        tester.view.physicalSize = const Size(320, 2400);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await seed(tester);
        await tester.pumpWidget(app(WorkoutScreen(workoutId: id)));
        await settle(tester);

        expect(tester.takeException(), isNull);
        expect(find.text('Superset · 1 of 2'), findsOneWidget);
        expect(find.text('Superset · 2 of 2'), findsOneWidget);
        expect(find.text('Target 8-12 reps · Rest 2:00'), findsOneWidget);
        expect(find.textContaining('Try +2.5 kg'), findsOneWidget);
        expect(find.text('Left knee sore'), findsOneWidget);
        expect(find.text('Short on sleep'), findsOneWidget);
        expect(find.text('Elbows tucked'), findsOneWidget);
        // Both exercises know a working weight and have no warm-ups.
        expect(find.text('Warm-up sets'), findsNWidgets(2));

        await tester.tap(find.byTooltip('Exercise options').first);
        await settle(tester);
        expect(tester.takeException(), isNull);
        for (final item in [
          'Edit note',
          'Rest time',
          'Replace exercise',
          'Remove from superset',
        ]) {
          expect(find.text(item), findsOneWidget, reason: item);
        }
        expect(find.text('Superset with next'), findsNothing);
        await tester.tap(find.text('Rest time'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('2:00'), findsOneWidget);
        await tester.tap(find.byTooltip('Longer'));
        await tester.pump();
        await tester.tap(find.text('Save'));
        await settle(tester);
        expect(find.text('Target 8-12 reps · Rest 2:15'), findsOneWidget);

        await tester.tap(find.text('Warm-up sets').first);
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('W'), findsNWidgets(4));
        expect(find.text('Warm-up sets'), findsOneWidget);
        await close(tester);
      });
    }

    testWidgets('typing moves through a superset and shows plates', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await seed(tester);
      await tester.pumpWidget(app(WorkoutScreen(workoutId: id)));
      await settle(tester);
      bool focused(int field) => tester
          .widget<TextField>(find.byType(TextField).at(field))
          .focusNode!
          .hasFocus;

      // Bench fields are 0–3, row fields 4–7.
      expect(find.textContaining('Per side'), findsNothing);
      await tester.showKeyboard(find.byType(TextField).at(0));
      await tester.pump();
      expect(find.text('Per side: 20 · 1.25'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), '100');
      await tester.pump();
      expect(find.text('Per side: 25 · 15'), findsOneWidget);

      await tester.showKeyboard(find.byType(TextField).at(1));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(focused(4), isTrue, reason: 'row, set 1');
      expect(find.textContaining('Per side'), findsNothing, reason: 'no bar');

      await tester.showKeyboard(find.byType(TextField).at(5));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(focused(2), isTrue, reason: 'bench, set 2');
      expect(find.text('2 / 4 sets · 0 min'), findsOneWidget);
      await close(tester);
    });

    testWidgets('bar and plates are set in Settings', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await seed(tester);
      await tester.pumpWidget(
        app(
          const Scaffold(body: SingleChildScrollView(child: BarbellSettings())),
        ),
      );
      await settle(tester);
      expect(find.text('20 kg'), findsOneWidget);
      expect(find.text('25, 20, 15, 10, 5, 2.5, 1.25 kg'), findsOneWidget);

      await tester.tap(find.text('Bar weight'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), '15');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('15 kg'), findsOneWidget);
      expect(find.text('Default'), findsNothing);

      await tester.tap(find.text('Plates'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(FilterChip, '1.25'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilterChip, '0.5'));
      await settle(tester);
      final s = (await tester.runAsync(SettingsRepository(db).get))!;
      expect(s.barWeightKg, 15);
      expect(parsePlates(s.plates, WeightUnit.kg), [
        25,
        20,
        15,
        10,
        5,
        2.5,
        0.5,
      ]);
      await tester.tap(find.text('Use default'));
      await settle(tester);
      expect(
        (await tester.runAsync(SettingsRepository(db).get))!.plates,
        isNull,
      );
      await close(tester);
    });
  });
}
