import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/enums.dart';
import '../../domain/finish.dart';
import '../../domain/loading.dart';
import '../../domain/supersets.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../router.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/periodic_builder.dart';
import '../gym/exercise_editor_sheet.dart';
import '../gym/exercise_picker_sheet.dart';
import '../history/workout_times_field.dart';
import 'finish_dialogs.dart';
import 'finish_summary_sheet.dart';
import 'rest_bar.dart';
import 'set_menu_sheet.dart';
import 'set_row.dart';
import 'workout_controller.dart';

/// `/workout`: resolves the live workout once and keeps its id.
class LiveWorkoutRoute extends ConsumerStatefulWidget {
  const LiveWorkoutRoute({super.key});

  @override
  ConsumerState<LiveWorkoutRoute> createState() => _LiveWorkoutRouteState();
}

class _LiveWorkoutRouteState extends ConsumerState<LiveWorkoutRoute> {
  int? _id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_askIfForgotten()),
    );
  }

  /// Once per app session, asks about a workout that has run for hours.
  Future<void> _askIfForgotten() async {
    final id = _id;
    final live = ref.read(liveWorkoutProvider);
    final asked = ref.read(forgottenAskedProvider);
    if (!mounted || id == null || live?.id != id || asked.contains(id)) return;
    if (!looksForgotten(live!.startedAt, DateTime.now())) return;
    asked.add(id);
    final draft = await ref.read(workoutEditorProvider(id).future);
    final lastSet = draft.lastSetAt;
    if (!mounted || (draft.completedSets > 0 && lastSet == null)) return;
    final choice = await askForgotten(
      context,
      running: DateTime.now().difference(live.startedAt),
      lastSetAt: lastSet,
    );
    if (!mounted) return;
    switch (choice) {
      case ForgottenChoice.endAtLastSet:
        await _finishAndSummarize(context, ref, id, endedAt: lastSet);
      case ForgottenChoice.discard:
        await ref.read(workoutEditorProvider(id).notifier).discard();
        if (mounted) context.go('/');
      case ForgottenChoice.keepGoing || null:
    }
  }

  @override
  Widget build(BuildContext context) {
    _id ??= ref.watch(liveWorkoutProvider)?.id;
    final id = _id;
    if (id == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: AppIcons.dumbbell,
          title: 'No workout running',
          message: 'Start one from Home.',
        ),
      );
    }
    return WorkoutScreen(workoutId: id);
  }
}

class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key, required this.workoutId});
  final int workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = workoutEditorProvider(workoutId);
    final async = ref.watch(provider);
    final draft = async.value;

    if (draft == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.hasError
            ? const EmptyState(
                icon: AppIcons.warning,
                title: 'Workout not found',
              )
            : const SizedBox.shrink(),
      );
    }

    final ids = [for (final e in draft.exercises) e.id];
    final spans = supersetSpans([
      for (final e in draft.exercises) e.supersetGroup,
    ]);
    final live = draft.isLive;
    final note = draft.workout.note;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _Title(workoutId: workoutId),
        actions: [
          if (live) _RestButton(workoutId: workoutId),
          FilledButton(
            onPressed: () => _finish(context, ref),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, kCompactTap),
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            ),
            child: Text(live ? 'Finish' : 'Save'),
          ),
          PopupMenuButton<String>(
            icon: const AppIcon(AppIcons.more),
            onSelected: (v) async {
              if (v == 'rename') await _rename(context, ref, draft);
              if (v == 'note' && context.mounted) {
                await _editNote(context, ref, draft);
              }
              if (v == 'discard' && context.mounted) {
                await _discard(context, ref, live);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(
                value: 'note',
                child: Text(note == null ? 'Add note' : 'Edit note'),
              ),
              PopupMenuItem(
                value: 'discard',
                child: Text(
                  live ? 'Discard workout' : 'Delete workout',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: live ? const RestBar() : null,
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, 120),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        buildDefaultDragHandles: false,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: _NoteLine(
                  note,
                  semanticsHint: 'Edit workout note',
                  onTap: () => _editNote(context, ref, draft),
                ),
              ),
            if (!live) ...[
              WorkoutTimesField(workoutId: workoutId),
              _BodyweightField(workoutId: workoutId),
            ],
          ],
        ),
        footer: Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: ids.isEmpty
              ? EmptyState(
                  icon: AppIcons.addExercise,
                  title: 'Add your first exercise',
                  action: FilledButton.icon(
                    onPressed: () => _addExercises(context, ref, draft),
                    icon: const AppIcon(AppIcons.plus),
                    label: const Text('Add exercise'),
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: () => _addExercises(context, ref, draft),
                  icon: const AppIcon(AppIcons.plus),
                  label: const Text('Add exercise'),
                ),
        ),
        itemCount: ids.length,
        onReorderItem: (from, to) =>
            ref.read(provider.notifier).reorder(from, to),
        itemBuilder: (context, i) {
          final span = spans[i];
          final linked = span != null && span.index < span.count - 1;
          return Padding(
            key: ValueKey(ids[i]),
            padding: EdgeInsets.only(bottom: linked ? 0 : Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ExerciseCard(
                  workoutId: workoutId,
                  exerciseId: ids[i],
                  index: i,
                  superset: span,
                  canLink: i < ids.length - 1 && !linked,
                ),
                if (linked) const SupersetLink(),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _addExercises(
    BuildContext context,
    WidgetRef ref,
    WorkoutDraft draft,
  ) async {
    final picked = await showExercisePicker(
      context,
      exclude: {for (final e in draft.exercises) e.exercise.id},
    );
    if (picked == null || picked.isEmpty) return;
    await ref
        .read(workoutEditorProvider(workoutId).notifier)
        .addExercises(picked);
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    WorkoutDraft draft,
  ) async {
    final name = await promptText(
      context,
      title: 'Rename workout',
      initial: draft.workout.name,
      action: 'Save',
    );
    if (name == null || name.isEmpty) return;
    await ref.read(workoutEditorProvider(workoutId).notifier).rename(name);
  }

  Future<void> _editNote(
    BuildContext context,
    WidgetRef ref,
    WorkoutDraft draft,
  ) async {
    final note = await askNote(
      context,
      title: 'Workout note',
      hint: 'How it went, how you felt…',
      initial: draft.workout.note ?? '',
    );
    if (note == null) return;
    await ref
        .read(workoutEditorProvider(workoutId).notifier)
        .setWorkoutNote(note);
  }

  Future<void> _discard(BuildContext context, WidgetRef ref, bool live) async {
    final ok = await confirm(
      context,
      title: live ? 'Discard workout?' : 'Delete workout?',
      message: 'This can’t be undone.',
      action: live ? 'Discard' : 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(workoutEditorProvider(workoutId).notifier).discard();
    if (!context.mounted) return;
    // A past workout's detail page pops itself when this returns true.
    if (live) {
      context.go('/');
    } else {
      context.pop(true);
    }
  }

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final editor = ref.read(workoutEditorProvider(workoutId).notifier);
    final draft = ref.read(workoutEditorProvider(workoutId)).requireValue;
    final completed = draft.completedSets;

    if (!draft.isLive) {
      if (completed == 0) {
        await _discard(context, ref, false);
        return;
      }
      await editor.finish();
      if (context.mounted) context.pop();
      return;
    }

    if (completed == 0 && draft.markableSets == 0) {
      final ok = await confirm(
        context,
        title: 'Nothing logged yet',
        message: 'Complete a set with ✓ to log it. Discard this workout?',
        action: 'Discard',
        destructive: true,
      );
      if (!ok) return;
      await editor.discard();
      if (context.mounted) context.go('/');
      return;
    }

    if (!await showFinishDialog(context, workoutId) || !context.mounted) return;
    final latest = ref.read(workoutEditorProvider(workoutId)).requireValue;
    final now = DateTime.now();
    final started = latest.workout.startedAt;
    final lastSet = staleEnd(latest.lastSetAt, startedAt: started, now: now);
    DateTime? endedAt;
    if (lastSet != null) {
      final choice = await askEndTime(
        context,
        startedAt: started,
        lastSetAt: lastSet,
        now: now,
      );
      if (choice == null || !context.mounted) return;
      if (choice == EndChoice.lastSet) endedAt = lastSet;
    }
    await _finishAndSummarize(context, ref, workoutId, endedAt: endedAt);
  }
}

/// Finishes the live workout, goes home and shows its summary.
Future<void> _finishAndSummarize(
  BuildContext context,
  WidgetRef ref,
  int workoutId, {
  DateTime? endedAt,
}) async {
  final saved = await ref
      .read(workoutEditorProvider(workoutId).notifier)
      .finish(endedAt: endedAt);
  if (!context.mounted) return;
  context.go('/');
  if (!saved) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final root = rootNavigatorKey.currentContext;
    if (root == null) return;
    showAppSheet<void>(root, (_) => FinishSummarySheet(workoutId: workoutId));
  });
}

class _RestButton extends ConsumerWidget {
  const _RestButton({required this.workoutId});
  final int workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(restTimerProvider.select((r) => r != null));
    return IconButton(
      tooltip: running ? 'Restart rest timer' : 'Start rest timer',
      icon: AppIcon(
        AppIcons.timer,
        color: running ? LiftColors.of(context).rest : null,
      ),
      onPressed: () =>
          ref.read(workoutEditorProvider(workoutId).notifier).startRest(),
    );
  }
}

class _Title extends ConsumerWidget {
  const _Title({required this.workoutId});
  final int workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(
      workoutEditorProvider(workoutId).select((a) => a.value?.workout),
    );
    final (done, total) = ref.watch(
      workoutEditorProvider(
        workoutId,
      ).select((a) => (a.value?.completedSets ?? 0, a.value?.totalSets ?? 0)),
    );
    if (w == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    final progress = total == 0 ? null : '$done / $total sets';
    Text sub(String state) => Text(
      [?progress, state].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.bodySmall?.copyWith(color: muted),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(w.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (w.endedAt == null)
          PeriodicBuilder(
            period: const Duration(minutes: 1),
            anchor: w.startedAt,
            builder: (_) =>
                sub(fmtDuration(DateTime.now().difference(w.startedAt))),
          )
        else
          sub('Editing'),
      ],
    );
  }
}

class _BodyweightField extends ConsumerStatefulWidget {
  const _BodyweightField({required this.workoutId});
  final int workoutId;

  @override
  ConsumerState<_BodyweightField> createState() => _BodyweightFieldState();
}

class _BodyweightFieldState extends ConsumerState<_BodyweightField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final unit = ref.read(settingsProvider).weightUnit;
    final kg = ref
        .read(workoutEditorProvider(widget.workoutId))
        .value
        ?.bodyweightKg;
    _ctrl = TextEditingController(text: kg == null ? '' : fmtWeight(kg, unit));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xs, 0, Space.xs, Space.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Body weight for this workout',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _ctrl,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                hintText: '–',
                suffixText: unit.label,
              ),
              onChanged: (v) {
                final n = parseNumber(v);
                ref
                    .read(workoutEditorProvider(widget.workoutId).notifier)
                    .setBodyweight(n == null ? null : unitToKg(n, unit));
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A note of this workout or of an exercise in it. Tap to edit.
class _NoteLine extends StatelessWidget {
  const _NoteLine(this.note, {required this.semanticsHint, this.onTap});
  final String note;
  final String semanticsHint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final muted = LiftColors.of(context).muted;
    return Semantics(
      button: true,
      hint: semanticsHint,
      child: InkWell(
        borderRadius: Radii.smAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(AppIcons.note, size: IconSizes.xs, color: muted),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(note, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the rest after a set of one exercise. Returns null on cancel and
/// a null `seconds` to go back to [fallback], the default from settings.
Future<({int? seconds})?> _askRest(
  BuildContext context, {
  required String exercise,
  required int? current,
  required int fallback,
}) {
  var seconds = current ?? fallback;
  return showDialog<({int? seconds})>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Rest after $exercise'),
      content: StatefulBuilder(
        builder: (ctx, setState) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Shorter',
              onPressed: seconds > 15
                  ? () => setState(() => seconds -= 15)
                  : null,
              icon: const AppIcon(AppIcons.minus),
            ),
            SizedBox(
              width: 72,
              child: Text(
                fmtClock(seconds),
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.headlineSmall
                    ?.copyWith(fontFeatures: Fonts.tabular),
              ),
            ),
            IconButton(
              tooltip: 'Longer',
              onPressed: seconds < 600
                  ? () => setState(() => seconds += 15)
                  : null,
              icon: const AppIcon(AppIcons.plus),
            ),
          ],
        ),
      ),
      actions: [
        if (current != null)
          TextButton(
            onPressed: () => Navigator.pop(ctx, (seconds: null)),
            child: Text('Use default (${fmtClock(fallback)})'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, (seconds: seconds)),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _ExerciseCard extends ConsumerStatefulWidget {
  const _ExerciseCard({
    required this.workoutId,
    required this.exerciseId,
    required this.index,
    this.superset,
    this.canLink = false,
  });

  final int workoutId;
  final int exerciseId;
  final int index;

  /// Its place in a superset, if it is in one.
  final ({int index, int count})? superset;

  /// Whether the exercise below can be linked to this one.
  final bool canLink;

  @override
  ConsumerState<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends ConsumerState<_ExerciseCard> {
  bool? _allDone;
  bool _collapsed = false;

  WorkoutEditor get _editor =>
      ref.read(workoutEditorProvider(widget.workoutId).notifier);

  Future<void> _editNote(DraftExercise ex) async {
    final note = await askNote(
      context,
      title: 'Note for this workout',
      hint: 'Only for today, e.g. left knee sore',
      initial: ex.note ?? '',
    );
    if (note != null) _editor.setExerciseNote(ex.id, note);
  }

  Future<void> _replace(DraftExercise ex) async {
    final draft = ref.read(workoutEditorProvider(widget.workoutId)).value;
    final picked = await pickExercise(
      context,
      exclude: {
        for (final e in draft?.exercises ?? const <DraftExercise>[])
          e.exercise.id,
      },
    );
    if (picked == null) return;
    final cleared = await _editor.replaceExercise(ex.id, picked);
    if (cleared && mounted) {
      toast(context, 'Loads cleared to fit ${picked.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final workoutId = widget.workoutId;
    final provider = workoutEditorProvider(workoutId);
    final ex = ref.watch(
      provider.select((a) => a.value?.byId(widget.exerciseId)),
    );
    final live = ref.watch(provider.select((a) => a.value?.isLive ?? true));
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final effort = ref.watch(settingsProvider.select((s) => s.effortMode));
    final bodyweight = live
        ? ref.watch(settingsProvider.select((s) => s.bodyweightKg))
        : ref.watch(provider.select((a) => a.value?.bodyweightKg));
    if (ex == null) return const SizedBox.shrink();

    // Collapses when the last set is completed and opens again as soon as a
    // set is open. A past workout starts expanded, since it is there to edit.
    final allDone = ex.sets.isNotEmpty && ex.sets.every((s) => s.isCompleted);
    if (allDone != _allDone) {
      _collapsed = allDone && (live || _allDone != null);
      _allDone = allDone;
    }
    final collapsed = _collapsed;
    final records = ex.records(bodyweight);
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final editor = ref.read(provider.notifier);
    final target = fmtRepsRange(ex.repsMin, ex.repsMax);
    final (barKg, plates) = ref.watch(
      settingsProvider.select((s) => (s.barWeightKg, s.plates)),
    );
    final bar = BarSetup.of(barKg, plates, unit);
    final barbell =
        ex.type == TrackingType.weights &&
        ex.exercise.equipment == Equipment.barbell;
    final warmups = ex.warmups(barKg: bar.barKg);
    final increase = ex.increaseKg;
    final superset = widget.superset;
    final meta = [
      if (target.isNotEmpty) 'Target $target reps',
      if (ex.restSeconds case final rest?) 'Rest ${fmtClock(rest)}',
    ].join(' · ');

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.mdAll,
        side: BorderSide(color: scheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, 0, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ex.exercise.name,
                          style: t.titleMedium?.copyWith(color: scheme.primary),
                        ),
                        if (superset != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Tag(
                              '${supersetLabel(superset.count)} · '
                              '${superset.index + 1} of ${superset.count}',
                              color: scheme.primary,
                            ),
                          ),
                        if (meta.isNotEmpty)
                          Text(
                            meta,
                            style: t.bodySmall?.copyWith(color: lift.muted),
                          ),
                        if (increase != null)
                          Text(
                            'Every set reached ${ex.repsMax} reps last time. '
                            'Try +${fmtWeight(increase, unit)} ${unit.label}.',
                            style: t.bodySmall?.copyWith(color: scheme.primary),
                          ),
                        if (ex.exercise.notes case final notes?
                            when notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              notes,
                              style: t.bodySmall?.copyWith(
                                color: lift.muted,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        if (ex.note case final note?)
                          _NoteLine(
                            note,
                            semanticsHint: 'Edit note',
                            onTap: () => _editNote(ex),
                          ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: AppIcon(AppIcons.more, color: lift.muted),
                  tooltip: 'Exercise options',
                  onSelected: (v) async {
                    if (v == 'edit') {
                      final updated = await showExerciseEditor(
                        context,
                        existing: ex.exercise,
                      );
                      if (updated != null) editor.refreshExercise(updated);
                    } else if (v == 'note') {
                      await _editNote(ex);
                    } else if (v == 'rest') {
                      final rest = await _askRest(
                        context,
                        exercise: ex.exercise.name,
                        current: ex.restSeconds,
                        fallback: ref.read(settingsProvider).defaultRestSeconds,
                      );
                      if (rest != null) editor.setRest(ex.id, rest.seconds);
                    } else if (v == 'replace') {
                      await _replace(ex);
                    } else if (v == 'link') {
                      await editor.linkWithNext(ex.id);
                    } else if (v == 'unlink') {
                      await editor.unlink(ex.id);
                    } else if (v == 'remove') {
                      final hasDone = ex.sets.any((s) => s.isCompleted);
                      if (hasDone &&
                          !(context.mounted &&
                              await confirm(
                                context,
                                title: 'Remove ${ex.exercise.name}?',
                                message: 'Its logged sets will be removed.',
                                action: 'Remove',
                                destructive: true,
                              ))) {
                        return;
                      }
                      await editor.removeExercise(ex.id);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit exercise'),
                    ),
                    PopupMenuItem(
                      value: 'note',
                      child: Text(ex.note == null ? 'Add note' : 'Edit note'),
                    ),
                    const PopupMenuItem(
                      value: 'rest',
                      child: Text('Rest time'),
                    ),
                    const PopupMenuItem(
                      value: 'replace',
                      child: Text('Replace exercise'),
                    ),
                    if (widget.canLink)
                      PopupMenuItem(
                        value: 'link',
                        child: Text(
                          superset == null
                              ? 'Superset with next'
                              : 'Add next to superset',
                        ),
                      ),
                    if (superset != null)
                      const PopupMenuItem(
                        value: 'unlink',
                        child: Text('Remove from superset'),
                      ),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(
                        'Remove',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ],
                ),
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: AppIcon(AppIcons.drag, color: lift.muted),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: Motion.of(context, Motion.medium),
            curve: Motion.curve,
            alignment: Alignment.topCenter,
            child: collapsed
                ? _DoneSummary(
                    exercise: ex,
                    unit: unit,
                    record: records.isNotEmpty,
                    onTap: () => setState(() => _collapsed = false),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: Space.xs),
                      if (widget.index == 0) const SetMenuHint(),
                      SetHeader(exercise: ex, unit: unit, effort: effort),
                      const SizedBox(height: Space.xs),
                      for (var i = 0; i < ex.sets.length; i++)
                        Dismissible(
                          key: ValueKey(ex.sets[i].id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: scheme.error.withValues(alpha: 0.9),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: Space.xl),
                            child: AppIcon(
                              AppIcons.trash,
                              color: scheme.onError,
                            ),
                          ),
                          onDismissed: (_) => removeSetWithUndo(
                            context,
                            editor,
                            ex.id,
                            ex.sets[i].id,
                          ),
                          child: SetRow(
                            key: ValueKey('row-${ex.sets[i].id}'),
                            workoutId: workoutId,
                            exercise: ex,
                            index: i,
                            unit: unit,
                            effort: effort,
                            records: records[ex.sets[i].id] ?? const {},
                            bar: barbell ? bar : null,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.xs,
                          0,
                          Space.xs,
                          Space.xs,
                        ),
                        child: Row(
                          children: [
                            Flexible(
                              child: TextButton.icon(
                                onPressed: () => editor.addSet(ex.id),
                                icon: const AppIcon(
                                  AppIcons.plus,
                                  size: IconSizes.sm,
                                ),
                                label: const Text('Add set'),
                              ),
                            ),
                            if (warmups.isNotEmpty)
                              Flexible(
                                child: Tooltip(
                                  message: [
                                    for (final w in warmups)
                                      '${fmtWeight(w.loadKg, unit)} '
                                          '$kTimes ${w.reps}',
                                  ].join(', '),
                                  child: TextButton.icon(
                                    onPressed: () => editor.addWarmups(ex.id),
                                    icon: const AppIcon(
                                      AppIcons.plus,
                                      size: IconSizes.sm,
                                    ),
                                    label: const Text('Warm-up sets'),
                                  ),
                                ),
                              ),
                            const Spacer(),
                            if (allDone)
                              TextButton(
                                onPressed: () =>
                                    setState(() => _collapsed = true),
                                child: const Text('Hide sets'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// What a collapsed exercise card shows instead of its sets.
class _DoneSummary extends StatelessWidget {
  const _DoneSummary({
    required this.exercise,
    required this.unit,
    required this.record,
    required this.onTap,
  });

  final DraftExercise exercise;
  final WeightUnit unit;
  final bool record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lift = LiftColors.of(context);
    final n = exercise.sets.length;
    final sets = [
      for (final s in exercise.sets)
        fmtSet(
          type: exercise.type,
          mode: exercise.mode,
          loadKg: s.loadKg,
          reps: s.reps,
          unit: unit,
        ),
    ].join(', ');
    return Semantics(
      button: true,
      hint: 'Show sets',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.lg,
            Space.sm,
            Space.lg,
            Space.md,
          ),
          child: Row(
            children: [
              AppIcon(
                AppIcons.checkSolid,
                size: IconSizes.sm,
                color: lift.done,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  '$n ${n == 1 ? 'set' : 'sets'} done · $sets',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: lift.muted),
                ),
              ),
              if (record) ...[
                const SizedBox(width: Space.sm),
                AppIcon(
                  AppIcons.trophySolid,
                  size: IconSizes.sm,
                  color: lift.record,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
