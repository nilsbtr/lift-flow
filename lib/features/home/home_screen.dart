import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../data/template_repository.dart';
import '../../domain/history.dart';
import '../../domain/stats.dart';
import '../../domain/superset_groups.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/periodic_builder.dart';
import '../gym/gym_screen.dart';
import '../gym/template_folders.dart';
import '../history/history_screen.dart';
import '../history/workout_day_sheet.dart';
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

    Widget templateCard(TemplateDetail d) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
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
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundColor: Theme.of(context).colorScheme.primary,
          ),
          icon: const AppIcon(AppIcons.playSolid, size: IconSizes.sm),
        ),
      ),
    );
    final sections = groupTemplates(
      templates,
      ref.watch(templateFoldersProvider).value ?? const [],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Lift Flow')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [
          _WeekStrip(
            history: history,
            firstDay: ref.watch(
              settingsProvider.select((s) => s.firstDayOfWeek),
            ),
          ),
          const _WeekCaption(),
          const Padding(
            padding: EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, 0),
            child: _StartButton(),
          ),
          if (history.isNotEmpty) ...[
            const SectionLabel('Last workout'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: WorkoutSummaryCard(
                workout: history.first,
                unit: ref.watch(settingsProvider.select((s) => s.weightUnit)),
                onTap: () => context.go('/workouts/${history.first.id}'),
              ),
            ),
          ],
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
                        'Create a template, like “Push” or “Legs”, to start '
                        'it here with one tap.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          for (final d in sections.unfiled) templateCard(d),
          for (final s in sections.folders)
            if (s.templates.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, 0),
                child: FolderHeader(
                  folder: s.folder,
                  count: s.templates.length,
                  onToggle: () => toggleFolder(ref, s.folder),
                ),
              ),
              if (!s.folder.isCollapsed)
                for (final d in s.templates) templateCard(d),
            ],
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
  const _WeekStrip({required this.history, required this.firstDay});
  final List<Workout> history;

  /// [DateTime.monday] … [DateTime.sunday].
  final int firstDay;

  @override
  Widget build(BuildContext context) {
    final today = dayOf(DateTime.now());
    final first = weekStart(today, firstDay);
    final days = [for (var i = 0; i < 7; i++) addDays(first, i)];
    final trained = <int>{};
    for (final w in history) {
      final day = dayOf(w.startedAt);
      if (day.isBefore(first)) break;
      trained.add(days.indexOf(day));
    }
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    // By weekday, Monday first.
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    final dayFmt = DateFormat('EEEE d MMMM');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Semantics(
                button: trained.contains(i),
                label:
                    '${dayFmt.format(days[i])}'
                    '${trained.contains(i) ? ', trained' : ''}',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: Radii.smAll,
                  onTap: trained.contains(i)
                      ? () => showWorkoutDaySheet(
                          context,
                          day: days[i],
                          history: history,
                          workoutPath: (id) => '/workouts/$id',
                        )
                      : null,
                  child: Column(
                    children: [
                      Text(
                        letters[days[i].weekday - 1],
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
                            color: days[i] == today
                                ? scheme.primary
                                : trained.contains(i)
                                ? lift.done
                                : scheme.outline,
                            width: days[i] == today ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          '${days[i].day}',
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
            ),
        ],
      ),
    );
  }
}

/// This week against the goal, and the streak, with the volume change against
/// the same point last week. Opens Progress.
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
    final compare = compareWeeks(
      ref.watch(historyProvider).value ?? const <Workout>[],
      now: DateTime.now(),
      firstDay: ref.watch(settingsProvider.select((s) => s.firstDayOfWeek)),
    );
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
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(parts.join(' · '), textAlign: TextAlign.center),
                    if (compare != null)
                      Text(
                        compare.label,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
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

  /// Exercise rows, with each superset in one marked block.
  List<Widget> _rows(TextTheme t, LiftColors lift, Color accent) {
    final items = detail.items;
    Widget row(TemplateItem it) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Row(
        children: [
          Expanded(child: Text(it.exercise.name, style: t.bodyLarge)),
          Text(
            '${it.targetSets} $kTimes '
            '${it.repsMin == null ? '–' : fmtRepsRange(it.repsMin, it.repsMax)}',
            style: t.bodyMedium?.copyWith(color: lift.muted),
          ),
        ],
      ),
    );
    final runEnd = {
      for (final (s, e) in supersetRuns([
        for (final i in items) i.supersetGroup,
      ]))
        s: e,
    };
    final out = <Widget>[];
    for (var i = 0; i < items.length;) {
      final end = runEnd[i];
      if (end == null) {
        out.add(row(items[i++]));
        continue;
      }
      out.add(
        Container(
          margin: const EdgeInsets.symmetric(vertical: Space.xs),
          padding: const EdgeInsets.only(left: Space.md),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Superset', style: t.labelSmall?.copyWith(color: accent)),
              for (var k = i; k < end; k++) row(items[k]),
            ],
          ),
        ),
      );
      i = end;
    }
    return out;
  }

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
                children: _rows(t, lift, Theme.of(context).colorScheme.primary),
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
