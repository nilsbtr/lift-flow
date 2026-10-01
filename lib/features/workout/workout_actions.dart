import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../providers.dart';
import 'workout_controller.dart';

/// Starts a workout (optionally from a template), guarding against a live one.
Future<void> startWorkout(
  BuildContext context,
  WidgetRef ref, {
  int? templateId,
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
          '“${live.name}” is still running. Resume it, or discard it '
          'and start a new one.',
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
    if (choice != 'discard') return;
    await repo.discard(live.id);
    ref.invalidate(workoutEditorProvider(live.id));
    ref.read(restTimerProvider.notifier).skip();
  }

  await _maybeRequestPermissions(ref);
  try {
    await repo.start(templateId: templateId);
  } on Exception {
    return;
  }
  if (context.mounted) context.go('/workout');
}

Future<void> _maybeRequestPermissions(WidgetRef ref) async {
  final s = ref.read(settingsProvider);
  if (s.permissionsPrompted) return;
  if (s.restAlerts) await ref.read(notificationsProvider).requestPermission();
  await ref
      .read(settingsProvider.notifier)
      .update(const AppSettingsCompanion(permissionsPrompted: Value(true)));
}
