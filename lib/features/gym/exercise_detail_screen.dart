import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import '../../widgets/charts/chart_card.dart';
import '../../widgets/common.dart';
import 'exercise_editor_sheet.dart';
import 'exercise_picker_sheet.dart';
import 'exercise_trend_card.dart';

class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({
    super.key,
    required this.exerciseId,
    this.canOpenWorkouts = true,
  });
  final int exerciseId;

  /// Whether the current route has a nested workout route to link to.
  final bool canOpenWorkouts;

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

    final facts = sessionFacts(exercise, sessions);
    final bests = ExerciseBests();
    facts.forEach(bests.add);
    final repTable = hasRepMaxes(exercise.trackingType, exercise.loadMode)
        ? repMaxes(facts)
        : const <RepMax>[];

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
              [
                exercise.muscleGroup.label,
                exerciseSubtitle(exercise),
                if (exercise.perSide) 'Per side',
                if (exercise.perDumbbell) 'Per dumbbell',
                if (exercise.isArchived) 'Archived',
              ].join(' · '),
              style: t.bodyMedium?.copyWith(color: lift.muted),
            ),
          ),
          if (exercise.secondaryMuscles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.xs,
                Space.lg,
                0,
              ),
              child: Text(
                'Also works '
                '${exercise.secondaryMuscles.map((g) => g.label).join(', ')}',
                style: t.bodyMedium?.copyWith(color: lift.muted),
              ),
            ),
          if (exercise.muscleGroup.isLegacy)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.xs,
                Space.lg,
                0,
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Space.sm,
                children: [
                  Text(
                    'Filed under the old ${exercise.muscleGroup.label} group.',
                    style: t.bodyMedium?.copyWith(color: lift.rest),
                  ),
                  TextButton(
                    onPressed: () =>
                        showExerciseEditor(context, existing: exercise),
                    child: const Text('Refile'),
                  ),
                ],
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
          if (repTable.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.md,
                Space.lg,
                0,
              ),
              child: _RepMaxCard(
                exercise: exercise,
                rows: repTable,
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
                onTap: canOpenWorkouts
                    ? () => context.go(
                        '${GoRouterState.of(context).matchedLocation}'
                        '/workout/${s.workout.id}',
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dateFmt.format(s.workout.startedAt),
                            style: t.titleMedium,
                          ),
                        ),
                        if (canOpenWorkouts)
                          AppIcon(AppIcons.chevronRight, color: lift.muted),
                      ],
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      s.sets
                          .map(
                            (set) =>
                                '${set.setType.isWarmup ? 'W ' : ''}${fmtSet(
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

/// Best load at each rep count the exercise has been done for.
class _RepMaxCard extends StatelessWidget {
  const _RepMaxCard({
    required this.exercise,
    required this.rows,
    required this.unit,
  });
  final Exercise exercise;
  final List<RepMax> rows;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    final head = t.labelSmall?.copyWith(color: muted);
    final body = t.bodyMedium?.copyWith(fontFeatures: Fonts.tabular);
    final date = DateFormat('d MMM y');
    final weights = exercise.trackingType == TrackingType.weights;

    String load(double kg) {
      final v = fmtLoad(
        type: exercise.trackingType,
        mode: exercise.loadMode,
        loadKg: kg,
        unit: unit,
      );
      return weights || kg != 0 ? '$v ${unit.label}' : v;
    }

    Widget row(String reps, String best, String when, TextStyle? style) =>
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kCompactTap),
          child: Row(
            children: [
              Expanded(flex: 2, child: Text(reps, style: style)),
              Expanded(flex: 3, child: Text(best, style: style)),
              Expanded(
                flex: 3,
                child: Text(when, style: style, textAlign: TextAlign.end),
              ),
            ],
          ),
        );

    return ChartCard(
      title: 'Rep maxes',
      caption: 'Best ${weights ? 'weight' : 'load'} for an exact rep count.',
      child: Column(
        children: [
          row('REPS', weights ? 'WEIGHT' : 'LOAD', 'DATE', head),
          for (final r in rows)
            row('${r.reps}', load(r.loadKg), date.format(r.date), body),
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
