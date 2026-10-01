import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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
import 'finish_summary_sheet.dart';
import 'rest_bar.dart';
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
    final live = draft.isLive;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _Title(workoutId: workoutId),
        actions: [
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
              if (v == 'discard' && context.mounted) {
                await _discard(context, ref, live);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
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
        header: live ? null : _BodyweightField(workoutId: workoutId),
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
        itemBuilder: (context, i) => Padding(
          key: ValueKey(ids[i]),
          padding: const EdgeInsets.only(bottom: Space.md),
          child: _ExerciseCard(
            workoutId: workoutId,
            exerciseId: ids[i],
            index: i,
          ),
        ),
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
    final total = draft.exercises.fold(0, (n, e) => n + e.sets.length);

    if (!draft.isLive) {
      if (completed == 0) {
        await _discard(context, ref, false);
        return;
      }
      await editor.finish();
      if (context.mounted) context.pop();
      return;
    }

    if (completed == 0) {
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

    final unchecked = total - completed;
    final ok = await confirm(
      context,
      title: 'Finish workout?',
      message: unchecked > 0
          ? '$unchecked unchecked ${unchecked == 1 ? 'set' : 'sets'} will be dropped.'
          : null,
      action: 'Finish',
    );
    if (!ok) return;
    final saved = await editor.finish();
    if (!context.mounted) return;
    context.go('/');
    if (!saved) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final root = rootNavigatorKey.currentContext;
      if (root == null) return;
      showAppSheet<void>(root, (_) => FinishSummarySheet(workoutId: workoutId));
    });
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
    if (w == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(w.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (w.endedAt == null)
          PeriodicBuilder(
            period: const Duration(minutes: 1),
            anchor: w.startedAt,
            builder: (_) => Text(
              fmtDuration(DateTime.now().difference(w.startedAt)),
              style: t.bodySmall?.copyWith(color: muted),
            ),
          )
        else
          Text('Editing', style: t.bodySmall?.copyWith(color: muted)),
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

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({
    required this.workoutId,
    required this.exerciseId,
    required this.index,
  });

  final int workoutId;
  final int exerciseId;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = workoutEditorProvider(workoutId);
    final ex = ref.watch(provider.select((a) => a.value?.byId(exerciseId)));
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    if (ex == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final editor = ref.read(provider.notifier);
    final target = fmtRepsRange(ex.repsMin, ex.repsMax);

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
                          style: t.titleMedium?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                        if (target.isNotEmpty)
                          Text(
                            'Target $target reps',
                            style: t.bodySmall?.copyWith(color: lift.muted),
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
                      value: 'remove',
                      child: Text(
                        'Remove',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ],
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: AppIcon(AppIcons.drag, color: lift.muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.xs),
          SetHeader(exercise: ex, unit: unit),
          const SizedBox(height: Space.xs),
          for (var i = 0; i < ex.sets.length; i++)
            Dismissible(
              key: ValueKey(ex.sets[i].id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: scheme.error.withValues(alpha: 0.9),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: Space.xl),
                child: AppIcon(AppIcons.trash, color: scheme.onError),
              ),
              onDismissed: (_) => editor.removeSet(ex.id, ex.sets[i].id),
              child: SetRow(
                key: ValueKey('row-${ex.sets[i].id}'),
                workoutId: workoutId,
                exercise: ex,
                index: i,
                unit: unit,
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.xs, 0, 0, Space.xs),
              child: TextButton.icon(
                onPressed: () => editor.addSet(ex.id),
                icon: const AppIcon(AppIcons.plus, size: IconSizes.sm),
                label: const Text('Add set'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
