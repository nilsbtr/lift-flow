import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../history/workout_times_field.dart';
import 'workout_controller.dart';

/// Starts a workout (optionally from a template, or repeating [repeat]),
/// guarding against a live one.
Future<void> startWorkout(
  BuildContext context,
  WidgetRef ref, {
  int? templateId,
  Workout? repeat,
}) async {
  final repo = ref.read(workoutRepoProvider);
  final live = await repo.getLive();
  if (!context.mounted) return;
  if (live != null) {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Workout in progress'),
        content: Text(
          '“${live.name}” is still running. Resume it, finish it to save it, '
          'or discard it and start a new one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'finish'),
            child: const Text('Finish'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'resume'),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'resume') {
      context.go('/workout');
      return;
    }
    if (choice == 'finish') {
      // The editor flushes edits, snapshots body weight and clears the rest
      // timer, like the Finish button. An empty workout is dropped.
      await ref.read(workoutEditorProvider(live.id).future);
      final saved = await ref
          .read(workoutEditorProvider(live.id).notifier)
          .finish();
      if (saved && context.mounted) toast(context, 'Saved “${live.name}”');
    } else if (choice == 'discard') {
      await repo.discard(live.id);
      ref.invalidate(workoutEditorProvider(live.id));
      ref.read(restTimerProvider.notifier).skip();
    } else {
      return;
    }
  }

  await _maybeRequestPermissions(ref);
  try {
    if (repeat == null) {
      await repo.start(templateId: templateId);
    } else {
      final items = await ref
          .read(templateRepoProvider)
          .itemsFromWorkout(repeat.id);
      await repo.start(
        templateId: repeat.templateId,
        name: repeat.name,
        items: items,
      );
    }
  } on Exception {
    return;
  }
  if (context.mounted) context.go('/workout');
}

/// Asks for a date and time, then opens an empty past workout in the editor.
/// The workout is not live, so this also works during a running one.
Future<void> logPastWorkout(BuildContext context, WidgetRef ref) async {
  final now = DateTime.now();
  final start = await pickWorkoutStart(context, now: now);
  if (start == null || !context.mounted) return;
  var end = start.add(const Duration(hours: 1));
  if (end.isAfter(now)) end = now;
  if (!end.isAfter(start)) end = start.add(const Duration(minutes: 1));
  final id = await ref
      .read(workoutRepoProvider)
      .createPast(
        start,
        end,
        bodyweightKg: ref.read(settingsProvider).bodyweightKg,
      );
  if (context.mounted) await context.push('/history/log/$id');
}

Future<void> _maybeRequestPermissions(WidgetRef ref) async {
  final s = ref.read(settingsProvider);
  if (s.permissionsPrompted) return;
  if (s.restAlerts) await ref.read(notificationsProvider).requestPermission();
  await ref
      .read(settingsProvider.notifier)
      .update(const AppSettingsCompanion(permissionsPrompted: Value(true)));
}
