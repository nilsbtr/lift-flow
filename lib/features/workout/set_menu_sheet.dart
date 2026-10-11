import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../data/enums.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'workout_controller.dart';

enum _SetAction { note, delete }

String _typeHint(SetType t) => switch (t) {
  SetType.normal => 'A regular working set',
  SetType.warmup => 'Left out of totals and records',
  SetType.drop => 'Lighter, right after the set above',
  SetType.failure => 'No more reps were possible',
  SetType.amrap => 'As many reps as possible',
};

/// Set type, note and delete for one set of [exercise].
Future<void> showSetMenu(
  BuildContext context, {
  required WorkoutEditor editor,
  required DraftExercise exercise,
  required int setId,
}) async {
  final index = exercise.sets.indexWhere((s) => s.id == setId);
  if (index < 0) return;
  final set = exercise.sets[index];
  final label = setLabels(exercise.sets.map((s) => s.setType))[index];
  final result = await showAppSheet<Object>(
    context,
    (_) => _SetMenu(set.setType, set.note, setSemantics(set.setType, label)),
  );
  if (!context.mounted) return;
  switch (result) {
    case final SetType type:
      editor.setType(exercise.id, setId, type);
    case _SetAction.note:
      final note = await _askNote(context, set.note ?? '');
      if (note != null) editor.setNote(exercise.id, setId, note);
    case _SetAction.delete:
      removeSetWithUndo(context, editor, exercise.id, setId);
  }
}

/// Removes a set and offers Undo. The delete is written when the snackbar
/// closes, or earlier if the workout is finished or left.
void removeSetWithUndo(
  BuildContext context,
  WorkoutEditor editor,
  int exerciseId,
  int setId,
) {
  final messenger = ScaffoldMessenger.of(context);
  final settled = editor.removeSet(exerciseId, setId);
  var open = true;
  messenger.hideCurrentSnackBar();
  final bar = messenger.showSnackBar(
    SnackBar(
      content: const Text('Set deleted'),
      duration: const Duration(seconds: 4),
      persist: false,
      action: SnackBarAction(label: 'Undo', onPressed: editor.undoDelete),
    ),
  );
  unawaited(
    bar.closed.then((_) {
      open = false;
      return editor.commitDelete(setId);
    }),
  );
  // Undo must not outlive the delete, e.g. after Finish.
  unawaited(
    settled.then((_) {
      if (open) messenger.hideCurrentSnackBar();
    }),
  );
}

/// Asks for a set note. Returns null on cancel and '' to remove the note.
Future<String?> _askNote(BuildContext context, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Set note'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 200,
        minLines: 1,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Grip, tempo, how it felt…',
          counterText: '',
        ),
      ),
      actions: [
        if (initial.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _SetMenu extends StatelessWidget {
  const _SetMenu(this.type, this.note, this.title);
  final SetType type;
  final String? note;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = LiftColors.of(context).muted;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.sm,
              ),
              child: Text(title, style: t.titleLarge),
            ),
            for (final v in SetType.values)
              ListTile(
                selected: v == type,
                leading: SizedBox(
                  width: IconSizes.md,
                  child: Text(
                    v.letter.isEmpty ? '1' : v.letter,
                    textAlign: TextAlign.center,
                    style: t.titleMedium?.copyWith(
                      color: setTypeColor(context, v) ?? muted,
                    ),
                  ),
                ),
                title: Text(v.label),
                subtitle: Text(_typeHint(v)),
                trailing: v == type
                    ? AppIcon(AppIcons.check, color: scheme.primary)
                    : null,
                onTap: () => Navigator.pop(context, v),
              ),
            const Divider(),
            ListTile(
              leading: const AppIcon(AppIcons.note),
              title: Text(note == null ? 'Add note' : 'Edit note'),
              subtitle: note == null
                  ? null
                  : Text(note!, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(context, _SetAction.note),
            ),
            ListTile(
              leading: AppIcon(AppIcons.trash, color: scheme.error),
              title: Text('Delete set', style: TextStyle(color: scheme.error)),
              onTap: () => Navigator.pop(context, _SetAction.delete),
            ),
          ],
        ),
      ),
    );
  }
}
