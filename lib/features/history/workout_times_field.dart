import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../domain/history.dart';
import '../../domain/stats.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import '../workout/workout_controller.dart';

/// Asks for a date and then a time, for a workout that has already happened.
/// Returns null when cancelled or when the result lies in the future.
Future<DateTime?> pickWorkoutStart(
  BuildContext context, {
  DateTime? now,
}) async {
  final n = now ?? DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: n,
    firstDate: DateTime(2000),
    lastDate: n,
    helpText: 'Workout date',
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(n.subtract(const Duration(hours: 1))),
    helpText: 'Start time',
  );
  if (time == null || !context.mounted) return null;
  final start = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  if (start.isAfter(n)) {
    toast(context, 'That’s in the future.');
    return null;
  }
  return start;
}

/// Date, start and end of a past workout. Changes are checked, then saved.
class WorkoutTimesField extends ConsumerWidget {
  const WorkoutTimesField({super.key, required this.workoutId});
  final int workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(
      workoutEditorProvider(workoutId).select((a) => a.value?.workout),
    );
    final end = w?.endedAt;
    if (w == null || end == null) return const SizedBox.shrink();
    final start = w.startedAt;
    final clock = DateFormat('HH:mm');

    Future<void> save(DateTime s, DateTime e) async {
      final error = workoutTimesError(s, e, DateTime.now());
      if (error != null) {
        toast(context, error);
        return;
      }
      await ref.read(workoutEditorProvider(workoutId).notifier).setTimes(s, e);
    }

    Future<TimeOfDay?> pickTime(DateTime initial, String help) =>
        showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(initial),
          helpText: help,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, Space.md),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _TimeTile(
              label: 'Date',
              value: DateFormat('EEE d MMM').format(start),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: start,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().isAfter(start)
                      ? DateTime.now()
                      : start,
                );
                if (d == null || !context.mounted) return;
                final s = DateTime(
                  d.year,
                  d.month,
                  d.day,
                  start.hour,
                  start.minute,
                );
                await save(s, s.add(end.difference(start)));
              },
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            flex: 2,
            child: _TimeTile(
              label: 'Start',
              value: clock.format(start),
              onTap: () async {
                final t = await pickTime(start, 'Start time');
                if (t == null || !context.mounted) return;
                await save(
                  DateTime(
                    start.year,
                    start.month,
                    start.day,
                    t.hour,
                    t.minute,
                  ),
                  end,
                );
              },
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            flex: 2,
            child: _TimeTile(
              label: 'End',
              value:
                  '${clock.format(end)}'
                  '${dayOf(end) == dayOf(start) ? '' : ' (+1)'}',
              onTap: () async {
                final t = await pickTime(end, 'End time');
                if (t == null || !context.mounted) return;
                await save(start, endAtClock(start, t.hour, t.minute));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: FlatCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: t.labelSmall?.copyWith(
                color: LiftColors.of(context).muted,
              ),
            ),
            Text(
              value,
              style: t.bodyLarge?.copyWith(fontFeatures: Fonts.tabular),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
