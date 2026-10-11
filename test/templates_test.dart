import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/exercise_repository.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/data/template_repository.dart';
import 'package:lift_flow/domain/superset_groups.dart';
import 'package:lift_flow/domain/units.dart';
import 'package:lift_flow/features/gym/gym_screen.dart';
import 'package:lift_flow/features/gym/template_editor_screen.dart';
import 'package:lift_flow/features/gym/template_folders.dart';
import 'package:lift_flow/providers.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

Future<Exercise> exercise(
  AppDatabase db,
  String name, {
  TrackingType type = TrackingType.weights,
  LoadMode mode = LoadMode.none,
}) => ExerciseRepository(db).create(
  name: name,
  muscleGroup: MuscleGroup.chest,
  trackingType: type,
  loadMode: mode,
);

void narrow(WidgetTester tester, {double scale = 1, double height = 1400}) {
  tester.view.physicalSize = Size(320, height);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  group('rep fields', () {
    test('parse min and max', () {
      expect(parseRepsFields('', ''), (min: null, max: null, error: null));
      expect(parseRepsFields('8', ''), (min: 8, max: null, error: null));
      expect(parseRepsFields('8', '8'), (min: 8, max: null, error: null));
      expect(parseRepsFields(' 8 ', '12'), (min: 8, max: 12, error: null));
    });

    test('explain what is wrong', () {
      expect(parseRepsFields('', '12').error, 'Enter the min reps first');
      expect(parseRepsFields('12', '8').error, 'Max must be at least min');
      expect(parseRepsFields('0', '').error, 'Use 1–100 reps');
      expect(parseRepsFields('8', '101').error, 'Use 1–100 reps');
      expect(parseRepsFields('8', '-').error, 'Use 1–100 reps');
      expect(parseRepsFields('x', '').error, 'Use 1–100 reps');
    });
  });

  group('superset groups', () {
    test('normalize drops singletons, splits and renumbers', () {
      expect(normalizeGroups([1, null, 2, 2, 3]), [null, null, 1, 1, null]);
      expect(normalizeGroups([1, 2, 1]), [null, null, null]);
      expect(normalizeGroups([5, 5, null, 5, 5]), [1, 1, null, 2, 2]);
      expect(normalizeGroups(const []), isEmpty);
    });

    test('toggle links, merges and unlinks', () {
      expect(toggleLinkWithNext([null, null, null], 0), [1, 1, null]);
      expect(toggleLinkWithNext([1, 1, null], 1), [1, 1, 1]);
      expect(toggleLinkWithNext([1, 1, null, 2, 2], 2), [1, 1, 2, 2, 2]);
      expect(toggleLinkWithNext([1, 1, 1, 2, 2], 2), [1, 1, 1, 1, 1]);
      expect(toggleLinkWithNext([1, 1, 1], 0), [null, 1, 1]);
      // The left part is a pair, the right part alone and cleaned up.
      expect(toggleLinkWithNext([1, 1, 1], 1), [1, 1, null]);
      expect(toggleLinkWithNext([1, 1], 0), [null, null]);
      // The last exercise has no next one.
      expect(toggleLinkWithNext([null, 1, 1], 2), [null, 1, 1]);
    });

    test('reorder keeps supersets together', () {
      final g = <int?>[null, 1, 1, null];
      expect(reorderGroupIndices(g, 3, 0), [3, 0, 1, 2]);
      // Inside the superset: reorders its members.
      expect(reorderGroupIndices(g, 1, 2), [0, 2, 1, 3]);
      // Dragging a member out moves the whole superset.
      expect(reorderGroupIndices(g, 1, 0), [1, 2, 0, 3]);
      expect(reorderGroupIndices(g, 2, 3), [0, 3, 1, 2]);
      // Dropping inside another superset snaps to its nearer edge.
      expect(reorderGroupIndices(g, 0, 1), [0, 1, 2, 3]);
      expect(reorderGroupIndices(g, 0, 2), [1, 2, 0, 3]);
      expect(reorderGroupIndices([1, 1, 2, 2, null], 4, 1), [4, 0, 1, 2, 3]);
      expect(reorderGroupIndices([1, 1, 2, 2, null], 4, 2), [0, 1, 4, 2, 3]);
    });

    test('items are cleaned up with their exercises', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final a = await exercise(db, 'A');
      final b = await exercise(db, 'B');
      final c = await exercise(db, 'C');
      final items = [
        TemplateItem(exercise: a, targetSets: 3, supersetGroup: 4),
        TemplateItem(exercise: b, targetSets: 3, supersetGroup: 4),
        TemplateItem(exercise: c, targetSets: 3, supersetGroup: 9),
      ];
      expect(
        [for (final i in normalizedSupersets(items)) i.supersetGroup],
        [1, 1, null],
      );
      // Removing one member of a pair leaves no superset.
      expect(
        [
          for (final i in normalizedSupersets(items.sublist(1)))
            i.supersetGroup,
        ],
        [null, null],
      );
    });
  });

  group('duplicate names', () {
    test('add copy, then count', () {
      expect(duplicateName('Push A', const []), 'Push A copy');
      expect(duplicateName('Push A', ['Push A copy']), 'Push A copy 2');
      expect(
        duplicateName('Push A', ['push a copy', 'Push A copy 2']),
        'Push A copy 3',
      );
      // A copy of a copy does not stack suffixes.
      expect(
        duplicateName('Push A copy', ['Push A', 'Push A copy']),
        'Push A copy 2',
      );
      expect(
        duplicateName('Push A copy 2', ['Push A', 'Push A copy 2']),
        'Push A copy',
      );
    });

    test('fit the name length limit', () {
      final long = 'L' * 60;
      final first = duplicateName(long, const []);
      expect(first.length, 60);
      expect(first.endsWith(' copy'), isTrue);
      final second = duplicateName(long, [first]);
      expect(second.length, 60);
      expect(second.endsWith(' copy 2'), isTrue);
      expect(second, isNot(first));
    });
  });

  group('repository', () {
    late AppDatabase db;
    late TemplateRepository repo;
    late Exercise bench;
    late Exercise row;
    late Exercise curl;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = TemplateRepository(db);
      bench = await exercise(db, 'Bench press');
      row = await exercise(db, 'Row');
      curl = await exercise(db, 'Curl');
    });
    tearDown(() => db.close());

    Future<List<String>> names() async => [
      for (final d in await repo.watchAll().first) d.template.name,
    ];

    test('new fields survive the editor save path', () async {
      final items = normalizedSupersets([
        TemplateItem(
          exercise: bench,
          targetSets: 4,
          repsMin: 6,
          repsMax: 10,
          restSeconds: 150,
          targetWeightKg: 82.5,
          supersetGroup: 7,
        ),
        TemplateItem(exercise: row, targetSets: 3, supersetGroup: 7),
        // A group of one is cleaned up.
        TemplateItem(exercise: curl, targetSets: 2, supersetGroup: 8),
      ]);
      final id = await repo.save(name: 'Upper', items: items);
      final got = (await repo.get(id))!.items;
      expect(got[0].restSeconds, 150);
      expect(got[0].targetWeightKg, 82.5);
      expect((got[0].repsMin, got[0].repsMax), (6, 10));
      expect([for (final i in got) i.supersetGroup], [1, 1, null]);
      expect(got[1].restSeconds, isNull);
      expect(got[1].targetWeightKg, isNull);
    });

    test('target weight converts at the UI edge only', () {
      final kg = unitToKg(185, WeightUnit.lb);
      expect(kg, closeTo(83.91, 0.01));
      expect(fmtWeight(kg, WeightUnit.lb), '185');
    });

    test('duplicate copies everything next to the original', () async {
      final folder = await repo.createFolder('Upper/lower');
      final a = await repo.save(
        name: 'Push A',
        folderId: folder,
        items: [
          TemplateItem(
            exercise: bench,
            targetSets: 4,
            repsMin: 5,
            restSeconds: 180,
            targetWeightKg: 100,
            supersetGroup: 1,
          ),
          TemplateItem(exercise: row, targetSets: 2, supersetGroup: 1),
        ],
      );
      await repo.save(name: 'Legs', items: const []);
      await repo.save(name: 'Pull', items: const []);

      final copy = (await repo.duplicate(a))!;
      expect(await names(), ['Push A', 'Push A copy', 'Legs', 'Pull']);
      final got = (await repo.get(copy))!;
      expect(got.template.folderId, folder);
      expect(got.items.length, 2);
      expect(got.items[0].exercise.id, bench.id);
      expect(got.items[0].restSeconds, 180);
      expect(got.items[0].targetWeightKg, 100);
      expect((got.items[0].repsMin, got.items[0].targetSets), (5, 4));
      expect([for (final i in got.items) i.supersetGroup], [1, 1]);

      // Positions stay a clean sequence, so Home and Gym agree on the order.
      final all = await repo.watchAll().first;
      expect([for (final d in all) d.template.position], [0, 1, 2, 3]);

      // Another copy lands right after the original, with a new name.
      await repo.duplicate(a);
      expect(await names(), [
        'Push A',
        'Push A copy 2',
        'Push A copy',
        'Legs',
        'Pull',
      ]);
      // The original is untouched.
      expect((await repo.get(a))!.items.length, 2);
      expect(await repo.duplicate(9999), isNull);
    });

    test('folders keep, move and release templates', () async {
      final upper = await repo.createFolder('Upper');
      final home = await repo.createFolder('Home gym');
      final t1 = await repo.save(name: 'T1', items: const []);
      final t2 = await repo.save(name: 'T2', items: const [], folderId: upper);
      final t3 = await repo.save(name: 'T3', items: const [], folderId: upper);
      await repo.moveToFolder(t1, home);

      var s = groupTemplates(
        await repo.watchAll().first,
        await repo.watchFolders().first,
      );
      expect(s.unfiled, isEmpty);
      expect([for (final f in s.folders) f.folder.name], ['Upper', 'Home gym']);
      expect([for (final d in s.folders[0].templates) d.template.id], [t2, t3]);
      expect([for (final d in s.folders[1].templates) d.template.id], [t1]);

      await repo.reorderFolders([home, upper]);
      await repo.setFolderCollapsed(home, true);
      final folders = await repo.watchFolders().first;
      expect([for (final f in folders) f.name], ['Home gym', 'Upper']);
      expect([for (final f in folders) f.isCollapsed], [true, false]);

      await repo.moveToFolder(t2, null);
      await repo.deleteFolder(upper);
      s = groupTemplates(
        await repo.watchAll().first,
        await repo.watchFolders().first,
      );
      expect([for (final d in s.unfiled) d.template.id], [t2, t3]);
      expect(s.folders.single.folder.id, home);
      expect(await names(), ['T1', 'T2', 'T3']);
    });

    test('without folders the list is flat', () async {
      await repo.save(name: 'A', items: const []);
      await repo.save(name: 'B', items: const []);
      final s = groupTemplates(await repo.watchAll().first, const []);
      expect([for (final d in s.unfiled) d.template.name], ['A', 'B']);
      expect(s.folders, isEmpty);
    });

    test('reorder within a section leaves the others in place', () {
      expect(reorderWithin([1, 2, 3, 4, 5], [2, 4, 5], [5, 2, 4]), [
        1,
        5,
        3,
        2,
        4,
      ]);
      expect(reorderWithin([1, 2, 3], [1, 2, 3], [3, 1, 2]), [3, 1, 2]);
    });

    test('summary joins superset members', () {
      final items = [
        TemplateItem(exercise: bench, targetSets: 3, supersetGroup: 1),
        TemplateItem(exercise: row, targetSets: 3, supersetGroup: 1),
        TemplateItem(exercise: curl, targetSets: 3),
      ];
      expect(templateSummary(items), 'Bench press + Row · Curl');
      expect(templateSummary(const []), '');
    });
  });

  group('screens at 320 dp', () {
    late AppDatabase db;
    late TemplateRepository repo;
    late UserSettings settings;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Widget app(
      Widget home, {
      List<TemplateFolder> folders = const [],
      List<TemplateDetail> templates = const [],
    }) => ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(settings),
        templateFoldersProvider.overrideWith((ref) => Stream.value(folders)),
        templatesProvider.overrideWith((ref) => Stream.value(templates)),
        exercisesProvider.overrideWith(
          (ref) => Stream.value(const <Exercise>[]),
        ),
        archivedExercisesProvider.overrideWith(
          (ref) => Stream.value(const <Exercise>[]),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: home),
    );

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump();
    }

    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('template editor row, text ×$scale', (tester) async {
        narrow(tester, scale: scale, height: 2400);
        final items = (await tester.runAsync(() async {
          repo = TemplateRepository(db);
          settings = await SettingsRepository(db).get();
          final a = await exercise(db, 'Bench press');
          final b = await exercise(db, 'Row');
          final c = await exercise(db, 'Curl');
          return [
            TemplateItem(
              exercise: a,
              targetSets: 3,
              repsMin: 6,
              restSeconds: 120,
              targetWeightKg: 82.5,
              supersetGroup: 1,
            ),
            TemplateItem(exercise: b, targetSets: 1, supersetGroup: 1),
            TemplateItem(exercise: c, targetSets: 3),
          ];
        }))!;
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => TemplateEditorScreen(initialItems: items),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Superset'), findsOneWidget);
        expect(find.text('Rest 2:00 · 82.5 kg'), findsOneWidget);
        expect(find.text('1 set'), findsOneWidget);

        // An unusable range is explained and blocks saving.
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'Upper');
        await tester.enterText(fields.at(2), '4');
        await tester.pump();
        expect(find.text('Max must be at least min'), findsOneWidget);
        await tester.tap(find.text('Save'));
        await tester.pump();
        expect(find.text('Fix the rep ranges first'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Fixing it clears the message.
        await tester.enterText(fields.at(2), '10');
        await tester.pump();
        expect(find.text('Max must be at least min'), findsNothing);

        // Options: more rest and a target weight, then unlink.
        await tester.tap(find.byTooltip('Exercise options').first);
        await tester.pumpAndSettle();
        expect(find.text('Rest after each set'), findsOneWidget);
        expect(find.text('Target weight'), findsOneWidget);
        await tester.tap(find.byTooltip('More rest'));
        await tester.pump();
        expect(find.text('2:15'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, '90');
        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();
        await tester.ensureVisible(find.text('Done'));
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Rest 2:15 · 90 kg'), findsOneWidget);
        expect(find.text('Superset'), findsNothing);

        // Link it again from the sheet.
        await tester.tap(find.byTooltip('Exercise options').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();
        await tester.ensureVisible(find.text('Done'));
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Superset'), findsOneWidget);

        await tester.tap(find.text('Save'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Open'), findsOneWidget);
        expect(tester.takeException(), isNull);

        final saved = (await tester.runAsync(() => repo.watchAll().first))!;
        expect(saved.single.template.name, 'Upper');
        final got = saved.single.items;
        expect((got[0].repsMin, got[0].repsMax), (6, 10));
        expect((got[0].restSeconds, got[0].targetWeightKg), (135, 90.0));
        expect([for (final i in got) i.supersetGroup], [1, 1, null]);
      });
    }

    testWidgets('options sheet shows no weight for bodyweight', (tester) async {
      narrow(tester, scale: 1.6, height: 640);
      final items = (await tester.runAsync(() async {
        settings = await SettingsRepository(db).get();
        return [
          TemplateItem(
            exercise: await exercise(
              db,
              'Pull-up',
              type: TrackingType.bodyweight,
            ),
            targetSets: 3,
          ),
        ];
      }))!;
      await tester.pumpWidget(app(TemplateEditorScreen(initialItems: items)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Exercise options'));
      await tester.pumpAndSettle();
      expect(find.text('Target weight'), findsNothing);
      expect(find.text('Rest after each set'), findsOneWidget);
      // The last exercise has nothing to link with.
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 1.6]) {
      testWidgets('gym templates with folders, text ×$scale', (tester) async {
        narrow(tester, scale: scale, height: 1600);
        final (folders, details) = (await tester.runAsync(() async {
          repo = TemplateRepository(db);
          settings = await SettingsRepository(db).get();
          final a = await exercise(db, 'Bench press');
          final b = await exercise(db, 'Row');
          final f1 = await repo.createFolder('Upper/lower with a long name');
          final f2 = await repo.createFolder('Home gym');
          final item = TemplateItem(exercise: a, targetSets: 3);
          final pair = [
            TemplateItem(exercise: a, targetSets: 3, supersetGroup: 1),
            TemplateItem(exercise: b, targetSets: 3, supersetGroup: 1),
          ];
          await repo.save(name: 'Free', items: [item]);
          await repo.save(name: 'Push', items: pair, folderId: f1);
          await repo.save(name: 'Pull', items: [item], folderId: f1);
          await repo.save(name: 'Hidden', items: [item], folderId: f2);
          await repo.setFolderCollapsed(f2, true);
          return (await repo.watchFolders().first, await repo.watchAll().first);
        }))!;
        await tester.pumpWidget(
          app(
            const GymScreen(tab: GymTab.templates),
            folders: folders,
            templates: details,
          ),
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(FolderHeader), findsNWidgets(2));
        expect(find.text('Free'), findsOneWidget);
        expect(find.text('Push'), findsOneWidget);
        expect(find.text('Bench press + Row'), findsOneWidget);
        expect(find.text('Hidden'), findsNothing);

        // Tapping a header stores the new state for Home and Gym alike.
        await tester.tap(find.text('Home gym'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        final now = (await tester.runAsync(() => repo.watchFolders().first))!;
        expect([for (final f in now) f.isCollapsed], [false, false]);

        await tester.tap(find.byTooltip('Folder options').first);
        await tester.pumpAndSettle();
        expect(find.text('Rename'), findsOneWidget);
        expect(find.text('Move up'), findsNothing);
        expect(find.text('Move down'), findsOneWidget);
        await tester.tapAt(Offset.zero);
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Template options').first);
        await tester.pumpAndSettle();
        expect(find.text('Duplicate'), findsOneWidget);
        expect(find.text('Move to folder'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('gym templates without folders are a flat list', (
      tester,
    ) async {
      narrow(tester, scale: 1.6, height: 800);
      final details = (await tester.runAsync(() async {
        repo = TemplateRepository(db);
        settings = await SettingsRepository(db).get();
        final a = await exercise(db, 'Bench press');
        await repo.save(
          name: 'Push',
          items: [TemplateItem(exercise: a, targetSets: 3)],
        );
        await repo.save(name: 'Pull', items: const []);
        return repo.watchAll().first;
      }))!;
      await tester.pumpWidget(
        app(const GymScreen(tab: GymTab.templates), templates: details),
      );
      await settle(tester);
      expect(find.byType(FolderHeader), findsNothing);
      expect(find.text('Push'), findsOneWidget);
      expect(find.text('Pull'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
