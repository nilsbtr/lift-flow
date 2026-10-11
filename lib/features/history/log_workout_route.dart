import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../workout/workout_controller.dart';
import '../workout/workout_screen.dart';

/// Editor for a workout just created with Log past workout. Leaving without
/// saving drops it, so no empty workout is left in the history.
class LogWorkoutRoute extends ConsumerWidget {
  const LogWorkoutRoute({super.key, required this.workoutId});
  final int workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave(context, ref);
    },
    child: WorkoutScreen(workoutId: workoutId),
  );

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final provider = workoutEditorProvider(workoutId);
    final editor = ref.read(provider.notifier);
    final logged = ref.read(provider).value?.completedSets ?? 0;
    if (logged > 0) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save workout?'),
          content: const Text('Unchecked sets will be dropped.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'save') {
        await editor.finish();
      } else {
        await editor.discard();
      }
    } else {
      await editor.discard();
    }
    if (context.mounted) context.pop();
  }
}
