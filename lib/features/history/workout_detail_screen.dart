import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/records.dart';
import '../../domain/supersets.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/set_list.dart';
import '../workout/workout_actions.dart';
import 'session_card.dart';

class WorkoutDetailScreen extends ConsumerWidget {
  const WorkoutDetailScreen({super.key, required this.workoutId});
  final int workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(workoutDetailProvider(workoutId));
    final loaded = async.value;
    final prs = ref.watch(workoutPrsProvider(workoutId)).value ?? const {};
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final effort = ref.watch(settingsProvider.select((s) => s.effortMode));
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    // Shown under History and Progress; links stay in whichever tab it's in.
    final here = GoRouterState.of(context).matchedLocation;

    if (loaded == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const SizedBox.shrink()
            : const EmptyState(
                icon: AppIcons.history,
                title: 'Workout not found',
              ),
      );
    }

    final w = loaded.workout;
    final spans = supersetSpans([
      for (final ex in loaded.exercises) ex.row.supersetGroup,
    ]);
    bool linked(int i) {
      final span = spans[i];
      return span != null && span.index < span.count - 1;
    }

    final end = w.endedAt ?? w.startedAt;
    final stats = [
      DateFormat('EEE d MMM y · HH:mm').format(w.startedAt),
      fmtDuration(end.difference(w.startedAt)),
      '${w.totalSets} sets',
      if (w.totalVolumeKg > 0) fmtVolume(w.totalVolumeKg, unit),
      if (w.bodyweightKg != null)
        'BW ${fmtWeight(w.bodyweightKg!, unit)} ${unit.label}',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(w.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () async {
              final deleted = await context.push<bool>('$here/edit');
              if ((deleted ?? false) && context.mounted) Navigator.pop(context);
            },
            icon: const AppIcon(AppIcons.edit),
          ),
          PopupMenuButton<String>(
            icon: const AppIcon(AppIcons.more),
            onSelected: (v) async {
              if (v == 'again') {
                await startWorkout(context, ref, repeat: w);
              } else if (v == 'template') {
                final items = await ref
                    .read(templateRepoProvider)
                    .itemsFromWorkout(workoutId);
                if (!context.mounted) return;
                await context.push('/gym/template/new', extra: items);
              } else if (v == 'delete') {
                final ok = await confirm(
                  context,
                  title: 'Delete workout?',
                  message: 'This can’t be undone.',
                  action: 'Delete',
                  destructive: true,
                );
                if (!ok) return;
                await ref.read(workoutRepoProvider).deleteWorkout(workoutId);
                if (context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'again', child: Text('Do again')),
              const PopupMenuItem(
                value: 'template',
                child: Text('Save as template'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
        children: [
          Text(
            stats.join(' · '),
            style: t.bodyMedium?.copyWith(color: lift.muted),
          ),
          if (w.note case final note?)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(note, style: t.bodyMedium),
            ),
          const SizedBox(height: Space.lg),
          SessionCard(workout: loaded),
          const SizedBox(height: Space.sm),
          for (final (i, ex) in loaded.exercises.indexed) ...[
            Padding(
              // Cards of a superset are joined instead of spaced.
              padding: EdgeInsets.only(bottom: linked(i) ? 0 : Space.sm),
              child: FlatCard(
                onTap: () => context.go('$here/exercise/${ex.exercise.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (spans[i] case final span?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Space.xs),
                        child: Tag(
                          '${supersetLabel(span.count)} · '
                          '${span.index + 1} of ${span.count}',
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(ex.exercise.name, style: t.titleMedium),
                        ),
                        if (prs[ex.exercise.id] case final kinds?)
                          Wrap(
                            spacing: Space.xs,
                            children: [
                              for (final k in PrKind.values)
                                if (kinds.contains(k))
                                  Tag(
                                    k.label,
                                    color: lift.record,
                                    icon: AppIcons.trophySolid,
                                  ),
                            ],
                          ),
                      ],
                    ),
                    if (ex.row.note case final note?)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Text(note, style: t.bodyMedium),
                      ),
                    const SizedBox(height: Space.sm),
                    SetList(
                      exercise: ex.exercise,
                      sets: ex.sets,
                      unit: unit,
                      effort: effort,
                    ),
                  ],
                ),
              ),
            ),
            if (linked(i)) const SupersetLink(),
          ],
        ],
      ),
    );
  }
}
