import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../domain/units.dart';
import 'workout_controller.dart';

final _clock = DateFormat('HH:mm');

String _sets(int n) => n == 1 ? 'set' : 'sets';

/// The finish confirmation. It can mark every unchecked set done first and
/// then reports what that did. True when the user chose to finish.
Future<bool> showFinishDialog(BuildContext context, int workoutId) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _FinishDialog(workoutId: workoutId),
    ) ??
    false;

class _FinishDialog extends ConsumerStatefulWidget {
  const _FinishDialog({required this.workoutId});
  final int workoutId;

  @override
  ConsumerState<_FinishDialog> createState() => _FinishDialogState();
}

class _FinishDialogState extends ConsumerState<_FinishDialog> {
  /// Sets marked done from here, or null before the first tap.
  int? _marked;

  void _mark() {
    final r = ref
        .read(workoutEditorProvider(widget.workoutId).notifier)
        .markAllDone();
    unawaited(HapticFeedback.lightImpact());
    setState(() => _marked = (_marked ?? 0) + r.marked);
  }

  String _message(int unchecked, int completed) {
    final marked = _marked;
    return [
      if (marked != null) 'Marked $marked ${_sets(marked)} done.',
      if (unchecked > 0)
        if (marked != null)
          '$unchecked ${_sets(unchecked)} ${unchecked == 1 ? 'has' : 'have'} '
              'no reps or weight to use and will be dropped.'
        else if (completed == 0)
          'Nothing is checked yet.'
        else
          '$unchecked unchecked ${_sets(unchecked)} will be dropped.',
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(workoutEditorProvider(widget.workoutId)).requireValue;
    final completed = d.completedSets;
    final message = _message(d.uncheckedSets, completed);
    return AlertDialog(
      title: const Text('Finish workout?'),
      content: message.isEmpty
          ? null
          : Semantics(liveRegion: true, child: Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        if (d.markableSets > 0)
          TextButton(onPressed: _mark, child: const Text('Mark all done')),
        if (completed > 0)
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finish'),
          ),
      ],
    );
  }
}

enum EndChoice { lastSet, now }

/// Offers to end the workout at [lastSetAt] when finishing long after it.
/// Null if dismissed.
Future<EndChoice?> askEndTime(
  BuildContext context, {
  required DateTime startedAt,
  required DateTime lastSetAt,
  required DateTime now,
}) {
  final at = _clock.format(lastSetAt);
  return showDialog<EndChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('End at your last set?'),
      content: Text(
        'Your last set was ${fmtDuration(now.difference(lastSetAt))} ago, at '
        '$at. Ending then saves ${fmtDuration(lastSetAt.difference(startedAt))} '
        'instead of ${fmtDuration(now.difference(startedAt))}.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, EndChoice.now),
          child: const Text('End now'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, EndChoice.lastSet),
          child: Text('End at $at'),
        ),
      ],
    ),
  );
}

enum ForgottenChoice { endAtLastSet, keepGoing, discard }

/// Asks whether a workout running for [running] was forgotten. Ends at
/// [lastSetAt] when there is one, else offers to discard. Null if dismissed.
Future<ForgottenChoice?> askForgotten(
  BuildContext context, {
  required Duration running,
  required DateTime? lastSetAt,
}) {
  final last = lastSetAt == null
      ? 'No sets are logged.'
      : 'Your last set was at ${_clock.format(lastSetAt)}.';
  return showDialog<ForgottenChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Still working out?'),
      content: Text(
        'This workout has been running for ${fmtDuration(running)}. $last',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, ForgottenChoice.keepGoing),
          child: const Text('Keep going'),
        ),
        if (lastSetAt != null)
          TextButton(
            onPressed: () => Navigator.pop(ctx, ForgottenChoice.endAtLastSet),
            child: Text('End at ${_clock.format(lastSetAt)}'),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(ctx, ForgottenChoice.discard),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Discard'),
          ),
      ],
    ),
  );
}
