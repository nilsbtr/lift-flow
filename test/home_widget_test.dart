import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/template_repository.dart';
import 'package:lift_flow/data/workout_repository.dart';
import 'package:lift_flow/domain/home_widget.dart';
import 'package:lift_flow/features/gym/template_folders.dart';
import 'package:lift_flow/services/home_widget.dart';

WorkoutTemplate template(int id, {int? folder, String? name}) =>
    WorkoutTemplate(
      id: id,
      name: name ?? 'T$id',
      position: id,
      folderId: folder,
    );

TemplateFolder folder(int id) =>
    TemplateFolder(id: id, name: 'F$id', position: id, isCollapsed: false);

final now = DateTime(2026, 3, 11, 18); // A Wednesday.

Workout workout(
  int? templateId,
  int daysAgo, {
  bool finished = true,
  int hour = 18,
}) {
  final start = DateTime(now.year, now.month, now.day - daysAgo, hour);
  return Workout(
    id: 1,
    templateId: templateId,
    name: 'W',
    startedAt: start,
    endedAt: finished ? start.add(const Duration(minutes: 30)) : null,
    totalSets: 0,
    totalVolumeKg: 0,
    exerciseCount: 0,
  );
}

class FakeBackend implements HomeWidgetBackend {
  final published = <String>[];
  final controller = StreamController<Uri?>.broadcast(sync: true);
  Uri? launch;
  bool fail = false;

  @override
  Future<void> publish(String snapshot) async {
    if (fail) throw StateError('no plugin');
    published.add(snapshot);
  }

  @override
  Future<Uri?> launchUri() async =>
      fail ? throw StateError('no plugin') : launch;

  @override
  Stream<Uri?> get taps => controller.stream;
}

void main() {
  group('nextTemplate', () {
    // Home lists 1 and 4 (no folder), then folder 2 (5, 6), then folder 1
    // (2, 3), as the folders are ordered 2, 1.
    final templates = [
      template(1),
      template(2, folder: 1),
      template(3, folder: 1),
      template(4),
      template(5, folder: 2),
      template(6, folder: 2),
    ];
    final folders = [folder(2), folder(1)];
    int? next(List<Workout> workouts) =>
        nextTemplate(templates, folders, workouts)?.id;

    test('no templates', () {
      expect(nextTemplate(const [], folders, [workout(1, 0)]), isNull);
    });

    test('nothing started yet: the first one Home shows', () {
      expect(next(const []), 1);
      expect(next([workout(null, 0)]), 1);
      // Only folders: the first folder's first template.
      expect(
        nextTemplate(templates.where((t) => t.folderId != null).toList(), [
          folder(2),
          folder(1),
        ], const [])?.id,
        5,
      );
    });

    test('follows the most recently started one within its section', () {
      expect(next([workout(2, 1), workout(5, 3)]), 3);
      expect(next([workout(5, 1), workout(2, 3)]), 6);
      expect(next([workout(1, 0)]), 4);
      // A live workout counts like a finished one.
      expect(next([workout(2, 0, finished: false), workout(5, 1)]), 3);
    });

    test('wraps around at the end of the section', () {
      expect(next([workout(3, 0)]), 2);
      expect(next([workout(4, 0)]), 1);
      expect(nextTemplate([template(7)], const [], [workout(7, 0)])?.id, 7);
    });

    test('a folder that is gone counts as no folder', () {
      expect(nextTemplate(templates, [folder(2)], [workout(1, 0)])?.id, 2);
    });

    test('ignores workouts of deleted templates', () {
      expect(next([workout(99, 0)]), 1);
      expect(next([workout(99, 0), workout(5, 4)]), 6);
    });

    test('uses the order of Home and Gym', () {
      final sections = groupTemplates([
        for (final t in templates) TemplateDetail(t, const []),
      ], folders);
      final shown = [
        ...sections.unfiled,
        for (final s in sections.folders) ...s.templates,
      ];
      expect(next(const []), shown.first.template.id);
      for (final s in [
        sections.unfiled,
        ...sections.folders.map((f) => f.templates),
      ]) {
        for (final (i, d) in s.indexed) {
          expect(
            next([workout(d.template.id, 0)]),
            s[(i + 1) % s.length].template.id,
          );
        }
      }
    });

    test('follows the database', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = TemplateRepository(db);
      final workouts = WorkoutRepository(db);
      final ppl = await repo.createFolder('PPL');
      for (final name in ['Push', 'Pull', 'Legs']) {
        await repo.save(name: name, items: const [], folderId: ppl);
      }
      Future<String?> offered() async => nextTemplate(
        [for (final d in await repo.watchAll().first) d.template],
        await repo.watchFolders().first,
        [?await workouts.getLive(), ...await workouts.watchHistory().first],
      )?.name;

      expect(await offered(), 'Push');
      final started = await workouts.start(templateId: 1);
      expect(await offered(), 'Pull');
      await workouts.discard(started);
      expect(await offered(), 'Push');

      await workouts.start(templateId: 3);
      expect(await offered(), 'Push');
      await repo.delete(1);
      expect(await offered(), 'Pull');
    });
  });

  group('widgetSnapshot', () {
    test('lists the days with a finished workout, oldest first', () {
      final s = widgetSnapshot(
        history: [
          workout(1, 0, hour: 7),
          workout(1, 0),
          workout(null, 2),
          workout(1, 1, finished: false),
          workout(1, 9),
        ],
        firstDay: DateTime.sunday,
        now: now,
      );
      expect(s.days, ['2026-03-02', '2026-03-09', '2026-03-11']);
      expect(s.firstDay, DateTime.sunday);
    });

    test('keeps the last 21 days, across a month', () {
      final s = widgetSnapshot(
        history: [workout(1, 20, hour: 0), workout(1, 21, hour: 23)],
        firstDay: DateTime.monday,
        now: now,
      );
      expect(s.days, ['2026-02-19']);
      expect(
        widgetSnapshot(
          history: [workout(1, 1)],
          firstDay: 1,
          now: now,
          days: 1,
        ).days,
        isEmpty,
      );
    });

    test('carries the next template and the live state', () {
      final idle = widgetSnapshot(
        history: const [],
        firstDay: DateTime.monday,
        now: now,
        next: template(12, name: ' Push '),
      );
      expect(
        (idle.templateId, idle.templateName, idle.live),
        (12, 'Push', false),
      );

      final live = widgetSnapshot(
        history: const [],
        firstDay: DateTime.monday,
        now: now,
        live: workout(null, 0, finished: false),
      );
      expect(
        (live.templateId, live.templateName, live.live),
        (null, null, true),
      );
    });

    test('encodes what the native side reads', () {
      final s = widgetSnapshot(
        history: [workout(1, 0)],
        firstDay: DateTime.saturday,
        now: now,
        next: template(12, name: 'Push'),
      );
      expect(jsonDecode(s.encode()), {
        'firstDay': 6,
        'days': ['2026-03-11'],
        'templateId': 12,
        'templateName': 'Push',
        'live': false,
      });
      expect(
        jsonDecode(
          widgetSnapshot(history: const [], firstDay: 1, now: now).encode(),
        ),
        {'firstDay': 1, 'days': <String>[], 'live': false},
      );
    });
  });

  group('parseWidgetUri', () {
    WidgetAction? parse(String uri) => parseWidgetUri(Uri.parse(uri));

    test('reads the widget’s taps', () {
      expect(parse('liftflow://widget/open'), (
        tap: WidgetTap.open,
        templateId: null,
      ));
      expect(parse('liftflow://widget/workout'), (
        tap: WidgetTap.resume,
        templateId: null,
      ));
      expect(parse('liftflow://widget/start'), (
        tap: WidgetTap.start,
        templateId: null,
      ));
      expect(parse('liftflow://widget/start?template=12'), (
        tap: WidgetTap.start,
        templateId: 12,
      ));
    });

    test('ignores everything else', () {
      expect(parseWidgetUri(null), isNull);
      expect(parseWidgetUri(Uri()), isNull);
      expect(parse('liftflow://widget/start?template=x'), isNull);
      expect(parse('liftflow://widget/start?template=0'), isNull);
      expect(parse('liftflow://widget/delete'), isNull);
      expect(parse('liftflow://other/start'), isNull);
      expect(parse('https://widget/start'), isNull);
    });
  });

  group('HomeWidgetService', () {
    late FakeBackend backend;
    late HomeWidgetService service;
    late DateTime clock;
    final start12 = Uri.parse('liftflow://widget/start?template=12');
    final open = Uri.parse('liftflow://widget/open');

    HomeWidgetSnapshot snapshot({String? name, bool live = false}) =>
        HomeWidgetSnapshot(
          firstDay: DateTime.monday,
          days: const ['2026-03-11'],
          templateId: name == null ? null : 1,
          templateName: name,
          live: live,
        );

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      backend = FakeBackend();
      clock = now;
      service = HomeWidgetService(backend, () => clock);
      addTearDown(service.dispose);
    });

    test('pushes changes and skips unchanged snapshots', () async {
      await service.sync(snapshot(name: 'Push'));
      await service.sync(snapshot(name: 'Push'));
      expect(backend.published, [snapshot(name: 'Push').encode()]);

      await service.sync(snapshot(name: 'Pull'));
      await service.sync(snapshot(name: 'Pull', live: true));
      expect(backend.published, hasLength(3));
    });

    test('survives a plugin that throws, and retries', () async {
      backend.fail = true;
      await service.sync(snapshot(name: 'Push'));
      final taps = <WidgetAction>[];
      await service.init(taps.add);
      expect(backend.published, isEmpty);
      expect(taps, isEmpty);

      backend.fail = false;
      await service.sync(snapshot(name: 'Push'));
      expect(backend.published, hasLength(1));
    });

    test('reports the launch tap and later ones', () async {
      final taps = <WidgetAction>[];
      backend.launch = start12;
      await service.init(taps.add);
      expect(taps, [(tap: WidgetTap.start, templateId: 12)]);

      backend.controller.add(open);
      backend.controller.add(Uri.parse('liftflow://elsewhere'));
      backend.controller.add(null);
      expect(taps.map((a) => a.tap), [WidgetTap.start, WidgetTap.open]);
    });

    test('a tap that reaches Dart twice counts once', () async {
      final taps = <WidgetAction>[];
      backend.launch = start12;
      await service.init(taps.add);
      backend.controller.add(start12); // The same launch, as a new intent.
      expect(taps, hasLength(1));

      backend.controller.add(open);
      expect(taps, hasLength(2));

      clock = clock.add(const Duration(seconds: 4));
      backend.controller.add(open); // A real second tap.
      expect(taps, hasLength(3));
    });

    test('does nothing off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      backend.launch = start12;
      final taps = <WidgetAction>[];
      await service.init(taps.add);
      await service.sync(snapshot(name: 'Push'));
      expect(taps, isEmpty);
      expect(backend.published, isEmpty);
    });
  });
}
