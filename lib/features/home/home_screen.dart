import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../data/template_repository.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/periodic_builder.dart';
import '../gym/gym_screen.dart';
import '../workout/workout_actions.dart';

String relativeDay(DateTime d, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return '$diff days ago';
  return DateFormat('d MMM').format(d);
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider).value ?? const [];
    final history = ref.watch(historyProvider).value ?? const <Workout>[];

    final lastDone = <int, DateTime>{};
    for (final w in history) {
      final tid = w.templateId;
      if (tid != null) lastDone.putIfAbsent(tid, () => w.startedAt);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Lift Flow')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [
          _WeekStrip(history: history),
          const _WeekCaption(),
          const Padding(
            padding: EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 0),
            child: _StartButton(),
          ),
          SectionLabel(
            'Your templates',
            trailing: TextButton(
              onPressed: () => context.go('/gym?tab=templates'),
              child: const Text('Manage'),
            ),
          ),
          if (templates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: FlatCard(
                onTap: () => context.push('/gym/template/new'),
                child: Row(
                  children: [
                    AppIcon(
                      AppIcons.plus,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: Space.md),
                    const Expanded(
                      child: Text(
                        'Create a template, like "Push" or "Legs", to start '
                        'it here with one tap.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          for (final d in templates)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.sm,
              ),
              child: TemplateCard(
                detail: d,
                caption: lastDone[d.template.id] == null
                    ? null
                    : 'Last done ${relativeDay(lastDone[d.template.id]!).toLowerCase()}',
                onTap: () async {
                  final action = await showAppSheet<String>(
                    context,
                    (_) => _TemplatePreviewSheet(detail: d),
                  );
                  if (!context.mounted) return;
                  if (action == 'start') {
                    await startWorkout(context, ref, templateId: d.template.id);
                  } else if (action == 'edit') {
                    await context.push('/gym/template/${d.template.id}');
                  }
                },
                trailing: IconButton(
                  tooltip: 'Start ${d.template.name}',
                  onPressed: () =>
                      startWorkout(context, ref, templateId: d.template.id),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  icon: const AppIcon(AppIcons.playSolid, size: IconSizes.sm),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StartButton extends ConsumerWidget {
  const _StartButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveWorkoutProvider);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      textStyle: t.titleMedium,
      iconSize: IconSizes.md,
    );
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.medium),
      child: live != null
          ? FilledButton.icon(
              key: const ValueKey('resume'),
              style: style.copyWith(
                backgroundColor: WidgetStatePropertyAll(scheme.secondary),
              ),
              onPressed: () => context.go('/workout'),
              icon: const AppIcon(AppIcons.playSolid),
              label: PeriodicBuilder(
                period: const Duration(minutes: 1),
                anchor: live.startedAt,
                builder: (_) => Text(
                  'Resume workout · '
                  '${fmtDuration(DateTime.now().difference(live.startedAt))}',
                ),
              ),
            )
          : FilledButton.icon(
              key: const ValueKey('start'),
              style: style,
              onPressed: () => startWorkout(context, ref),
              icon: const AppIcon(AppIcons.plus),
              label: const Text('Start empty workout'),
            ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.history});
  final List<Workout> history;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final trained = <int>{};
    for (final w in history) {
      final d = w.startedAt;
      final day = DateTime(d.year, d.month, d.day);
      if (day.isBefore(monday)) break;
      trained.add(day.difference(monday).inDays);
    }
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Semantics(
        label: '${trained.length} workouts this week',
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      Text(
                        letters[i],
                        style: t.labelSmall?.copyWith(color: lift.muted),
                      ),
                      const SizedBox(height: Space.xs),
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: trained.contains(i)
                              ? lift.done
                              : Colors.transparent,
                          border: Border.all(
                            color: monday.add(Duration(days: i)) == today
                                ? scheme.primary
                                : trained.contains(i)
                                ? lift.done
                                : scheme.outline,
                            width: monday.add(Duration(days: i)) == today
                                ? 2
                                : 1,
                          ),
                        ),
                        child: Text(
                          '${monday.add(Duration(days: i)).day}',
                          style: t.labelLarge?.copyWith(
                            color: trained.contains(i)
                                ? scheme.surface
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// This week against the goal, and the streak. Opens Progress.
class _WeekCaption extends ConsumerWidget {
  const _WeekCaption();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(weekSummaryProvider);
    if (s.goal == null && s.workouts == 0 && s.streak == 0) {
      return const SizedBox.shrink();
    }
    final parts = [
      s.goal == null
          ? '${s.workouts} this week'
          : '${s.workouts} of ${s.goal} this week',
      if (s.streak > 1) '${s.streak}-week streak',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Center(
        child: TextButton(
          onPressed: () => context.go('/progress'),
          style: TextButton.styleFrom(
            foregroundColor: LiftColors.of(context).muted,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(parts.join(' · '))),
              const SizedBox(width: Space.xs),
              const AppIcon(AppIcons.chevronRight, size: IconSizes.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplatePreviewSheet extends StatelessWidget {
  const _TemplatePreviewSheet({required this.detail});
  final TemplateDetail detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(detail.template.name, style: t.headlineSmall),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'edit'),
                  child: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            if (detail.items.isEmpty)
              Text(
                'No exercises yet.',
                style: t.bodyMedium?.copyWith(color: lift.muted),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final it in detail.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(it.exercise.name, style: t.bodyLarge),
                          ),
                          Text(
                            '${it.targetSets} × '
                            '${it.repsMin == null ? '–' : fmtRepsRange(it.repsMin, it.repsMax)}',
                            style: t.bodyMedium?.copyWith(color: lift.muted),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'start'),
              icon: const AppIcon(AppIcons.playSolid),
              label: Text('Start ${detail.template.name}'),
            ),
          ],
        ),
      ),
    );
  }
}
