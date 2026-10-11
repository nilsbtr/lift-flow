import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/template_repository.dart';
import 'package:lift_flow/data/workout_repository.dart';
import 'package:lift_flow/domain/shortcuts.dart';
import 'package:lift_flow/services/shortcuts.dart';
import 'package:quick_actions/quick_actions.dart';

WorkoutTemplate template(int id, [String? name]) =>
    WorkoutTemplate(id: id, name: name ?? 'T$id', position: id);

final day = DateTime(2026, 3, 1, 18);

Workout workout(int? templateId, int daysAgo, {int id = 1}) => Workout(
  id: id,
  templateId: templateId,
  name: 'W',
  startedAt: day.subtract(Duration(days: daysAgo)),
  totalSets: 0,
  totalVolumeKg: 0,
  exerciseCount: 0,
);

List<int> ids(List<WorkoutTemplate> ts) => [for (final t in ts) t.id];

class FakeQuickActions implements QuickActions {
  QuickActionHandler? handler;
  final calls = <List<String>>[];

  @override
  Future<void> initialize(QuickActionHandler handler) async =>
      this.handler = handler;

  @override
  Future<void> setShortcutItems(List<ShortcutItem> items) async =>
      calls.add([for (final i in items) '${i.type}=${i.localizedTitle}']);

  @override
  Future<void> clearShortcutItems() async => calls.add([]);
}

void main() {
  group('shortcutTemplates', () {
    final templates = [for (var i = 1; i <= 6; i++) template(i)];

    test('without history it follows template order, four at most', () {
      expect(ids(shortcutTemplates(templates, const [])), [1, 2, 3, 4]);
      expect(ids(shortcutTemplates(templates.take(2).toList(), const [])), [
        1,
        2,
      ]);
      expect(shortcutTemplates(const [], const []), isEmpty);
    });

    test('most recently used first, by the latest workout', () {
      final history = [
        workout(3, 10),
        workout(5, 2),
        workout(3, 1), // Template 3's latest wins over its older workout.
        workout(2, 20),
        workout(null, 0), // Started without a template.
      ];
      expect(ids(shortcutTemplates(templates, history)), [3, 5, 2, 1]);
    });

    test('unused templates fill the rest in template order', () {
      expect(ids(shortcutTemplates(templates, [workout(6, 1)])), [6, 1, 2, 3]);
    });

    test('ties and the limit', () {
      final history = [workout(4, 1), workout(2, 1), workout(3, 1)];
      expect(ids(shortcutTemplates(templates, history)), [2, 3, 4, 1]);
      expect(ids(shortcutTemplates(templates, history, limit: 2)), [2, 3]);
    });

    test('ignores workouts of templates that are gone', () {
      expect(ids(shortcutTemplates(templates, [workout(99, 0)])), [1, 2, 3, 4]);
    });

    test('follows templates being used and deleted', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = TemplateRepository(db);
      final workouts = WorkoutRepository(db);
      for (final name in ['Push', 'Pull', 'Legs']) {
        await repo.save(name: name, items: const []);
      }
      Future<List<String>> offered() async => [
        for (final t in shortcutTemplates(
          [for (final d in await repo.watchAll().first) d.template],
          [?await workouts.getLive()],
        ))
          t.name,
      ];

      expect(await offered(), ['Push', 'Pull', 'Legs']);

      final started = await workouts.start(templateId: 3);
      expect(await offered(), ['Legs', 'Push', 'Pull']);

      await workouts.discard(started);
      await repo.delete(2);
      expect(await offered(), ['Push', 'Legs']);

      await repo.save(id: 1, name: 'Upper', items: const []);
      expect(await offered(), ['Upper', 'Legs']);
    });
  });

  group('ShortcutService', () {
    late FakeQuickActions actions;
    late ShortcutService service;
    var now = day;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      actions = FakeQuickActions();
      now = day;
      service = ShortcutService(actions, () => now);
    });

    test('shortcut types round-trip to template ids', () {
      expect(ShortcutService.typeFor(12), 'template:12');
      expect(ShortcutService.templateIdOf('template:12'), 12);
      expect(ShortcutService.templateIdOf('template:x'), isNull);
      expect(ShortcutService.templateIdOf('other:12'), isNull);
    });

    test('reports taps that are for templates', () async {
      final taps = <int>[];
      await service.init(taps.add);
      actions.handler!('template:7');
      actions.handler!('something else');
      expect(taps, [7]);
    });

    test('a launch that reaches Dart twice starts the template once', () async {
      final taps = <int>[];
      await service.init(taps.add);

      actions.handler!('template:7'); // The launch action...
      actions.handler!('template:7'); // ...and the new-intent callback.
      expect(taps, [7]);

      actions.handler!('template:8');
      expect(taps, [7, 8]);

      now = now.add(const Duration(seconds: 4));
      actions.handler!('template:8'); // A real second tap.
      expect(taps, [7, 8, 8]);
    });

    test('publishes in order and skips unchanged lists', () async {
      await service.sync([template(2, 'Pull'), template(1, ' Push ')]);
      expect(actions.calls.single, ['template:2=Pull', 'template:1=Push']);

      await service.sync([template(2, 'Pull'), template(1, 'Push')]);
      expect(actions.calls, hasLength(1));

      await service.sync([template(1, 'Push'), template(2, 'Pull')]);
      await service.sync([template(1, 'Upper')]);
      expect(actions.calls, hasLength(3));
      expect(actions.calls.last, ['template:1=Upper']);

      await service.sync(const []);
      expect(actions.calls.last, isEmpty);
    });
  });
}
