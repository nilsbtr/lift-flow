import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../data/exercise_repository.dart';
import '../../domain/records.dart';
import '../../domain/stats.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'exercise_editor_sheet.dart';
import 'exercise_picker_sheet.dart';
import 'exercise_trend_card.dart';

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.exerciseId});
  final int exerciseId;

  Future<void> _delete(BuildContext context, WidgetRef ref, Exercise e) async {
    final repo = ref.read(exerciseRepoProvider);
    if (await repo.hasLoggedSets(e.id)) {
      if (!context.mounted) return;
      final ok = await confirm(
        context,
        title: 'Archive instead?',
        message:
            'This exercise is part of your history, so it can’t be '
            'deleted. Archiving hides it from lists.',
        action: 'Archive',
      );
      if (ok) await repo.setArchived(e.id, true);
      if (ok && context.mounted) Navigator.pop(context);
      return;
    }
    if (!context.mounted) return;
    final ok = await confirm(
      context,
      title: 'Delete ${e.name}?',
      message: 'It will also be removed from your templates.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await repo.delete(e.id);
      if (context.mounted) Navigator.pop(context);
    } on ExerciseInUseException catch (err) {
      if (context.mounted) toast(context, err.toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercise = ref.watch(exerciseProvider(exerciseId)).value;
    final sessions =
        ref.watch(exerciseSessionsProvider(exerciseId)).value ?? const [];
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);

    if (exercise == null) {
      return Scaffold(appBar: AppBar());
    }

    final bests = ExerciseBests();
    sessionFacts(exercise, sessions).forEach(bests.add);

    String load(double kg) => fmtLoad(
      type: exercise.trackingType,
      mode: exercise.loadMode,
      loadKg: kg,
      unit: unit,
    );

    final stats = <(String, String)>[
      if (exercise.trackingType == TrackingType.weights) ...[
        if (bests.heaviest != null)
          ('Heaviest', '${fmtWeight(bests.heaviest!, unit)} ${unit.label}'),
      ] else ...[
        if (bests.bestLoad != null && exercise.loadMode != LoadMode.none)
          ('Best load', load(bests.bestLoad!)),
        if (bests.mostReps != null) ('Most reps', '${bests.mostReps}'),
      ],
      if (bests.e1rm != null)
        ('Best e1RM', '${fmtWeight(bests.e1rm!, unit)} ${unit.label}'),
      ('Sessions', '${sessions.length}'),
    ];

    final dateFmt = DateFormat('EEE, d MMM y');

    return Scaffold(
      appBar: AppBar(
        title: Text(exercise.name),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () => showExerciseEditor(context, existing: exercise),
            icon: const AppIcon(AppIcons.edit),
          ),
          PopupMenuButton<String>(
            icon: const AppIcon(AppIcons.more),
            onSelected: (v) async {
              final repo = ref.read(exerciseRepoProvider);
              if (v == 'archive') {
                await repo.setArchived(exercise.id, !exercise.isArchived);
              } else if (v == 'delete' && context.mounted) {
                await _delete(context, ref, exercise);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'archive',
                child: Text(exercise.isArchived ? 'Restore' : 'Archive'),
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
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Text(
              '${exercise.muscleGroup.label} · ${exerciseTypeLabel(exercise)}'
              '${exercise.isArchived ? ' · Archived' : ''}',
              style: t.bodyMedium?.copyWith(color: lift.muted),
            ),
          ),
          if ((exercise.notes ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.md,
                Space.lg,
                0,
              ),
              child: Text(exercise.notes!, style: t.bodyMedium),
            ),
          const SizedBox(height: Space.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final (label, value) in stats)
                  _Stat(label: label, value: value),
              ],
            ),
          ),
          if (sessions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.lg,
                Space.lg,
                0,
              ),
              child: ExerciseCharts(
                exercise: exercise,
                sessions: sessions,
                unit: unit,
              ),
            ),
          const SectionLabel('History'),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Text(
                'No sets logged yet.',
                style: t.bodyMedium?.copyWith(color: lift.muted),
              ),
            ),
          for (final s in sessions)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.sm,
              ),
              child: FlatCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateFmt.format(s.workout.startedAt),
                      style: t.titleMedium,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      s.sets
                          .map(
                            (set) =>
                                '${set.isWarmup ? 'W ' : ''}${fmtSet(
                                  type: exercise.trackingType,
                                  mode: exercise.loadMode,
                                  loadKg: set.loadKg,
                                  reps: set.reps,
                                  unit: unit,
                                )}',
                          )
                          .join('   '),
                      style: t.bodyMedium?.copyWith(color: lift.muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 100),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: LiftColors.of(context).raised,
        borderRadius: Radii.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: t.labelSmall?.copyWith(color: LiftColors.of(context).muted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: t.headlineSmall?.copyWith(fontFeatures: Fonts.tabular),
          ),
        ],
      ),
    );
  }
}
