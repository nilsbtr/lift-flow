import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/stats.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/bodyweight_dialog.dart';
import '../../widgets/charts/balance_bars.dart';
import '../../widgets/charts/chart_card.dart';
import '../../widgets/charts/dot_calendar.dart';
import '../../widgets/charts/sparkline.dart';
import '../../widgets/charts/trend_chart.dart';
import '../../widgets/charts/week_bar_chart.dart';
import '../../widgets/common.dart';
import 'progress_providers.dart';

final _day = DateFormat('EEE, d MMM y');
final _short = DateFormat('d MMM');

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider).value ?? const <Workout>[];
    final weights = ref.watch(bodyweightEntriesProvider).value;

    if (history.isEmpty && (weights?.isEmpty ?? true)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Progress')),
        body: const EmptyState(
          icon: AppIcons.progress,
          title: 'No progress yet',
          message: 'Finish a workout to see your trends here.',
        ),
      );
    }

    const gap = SizedBox(height: Space.md);
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xxl),
        children: [
          if (history.isNotEmpty) ...[
            _ConsistencyCard(history),
            gap,
            _WeeklyCard(history),
            gap,
            const _BalanceCard(),
            const _TopLiftsCard(),
          ],
          _BodyweightCard(weights ?? const []),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ consistency

class _ConsistencyCard extends ConsumerWidget {
  const _ConsistencyCard(this.history);
  final List<Workout> history;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(weekSummaryProvider);
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    final now = DateTime.now();
    final goal = week.goal;
    final recent = weeklyStats(history, now: now).map((w) => w.workouts).sum;

    return ChartCard(
      title: 'Consistency',
      trailing: week.streak > 0
          ? Tag(
              '${week.streak}-week streak',
              color: lift.done,
              icon: AppIcons.checkSolid,
            )
          : null,
      caption: goal == null
          ? 'Set a weekly goal in Settings to track your streak.'
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            goal == null
                ? '${_count(week.workouts, 'workout')} this week'
                : '${week.workouts} of $goal this week',
            style: t.titleLarge?.copyWith(fontFeatures: Fonts.tabular),
          ),
          const SizedBox(height: Space.md),
          DotCalendar(
            activity: dayActivity(history),
            now: now,
            semanticLabel:
                '${_count(recent, 'workout')} in the last 12 weeks',
            onTapDay: (day) => showAppSheet<void>(
              context,
              (_) => _DaySheet(
                day: day,
                workouts: [
                  for (final w in history)
                    if (dayOf(w.startedAt) == day) w,
                ].reversed.toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

class _DaySheet extends StatelessWidget {
  const _DaySheet({required this.day, required this.workouts});
  final DateTime day;
  final List<Workout> workouts;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
          child: Text(_day.format(day), style: t.titleLarge),
        ),
        for (final w in workouts)
          ListTile(
            title: Text(w.name),
            subtitle: Text(
              '${fmtDuration(workoutTime(w))} · ${_count(w.totalSets, 'set')}',
            ),
            trailing: const AppIcon(AppIcons.chevronRight),
            onTap: () {
              final router = GoRouter.of(context);
              Navigator.pop(context);
              router.go('/progress/workout/${w.id}');
            },
          ),
        const SizedBox(height: Space.sm),
      ],
    );
  }
}

// ------------------------------------------------------------ weekly load

enum _Load {
  volume('Volume'),
  sets('Sets'),
  workouts('Workouts'),
  time('Time');

  const _Load(this.label);
  final String label;
}

class _WeeklyCard extends ConsumerStatefulWidget {
  const _WeeklyCard(this.history);
  final List<Workout> history;

  @override
  ConsumerState<_WeeklyCard> createState() => _WeeklyCardState();
}

class _WeeklyCardState extends ConsumerState<_WeeklyCard> {
  _Load _load = _Load.volume;

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final goal = ref.watch(settingsProvider.select((s) => s.weeklyGoal));
    final weeks = weeklyStats(widget.history, now: DateTime.now());

    double value(WeekStats w) => switch (_load) {
      _Load.volume => kgToUnit(w.volumeKg, unit),
      _Load.sets => w.sets.toDouble(),
      _Load.workouts => w.workouts.toDouble(),
      _Load.time => w.time.inMinutes / 60,
    };
    String fmt(WeekStats w) => switch (_load) {
      _Load.volume => fmtVolume(w.volumeKg, unit),
      _Load.sets => _count(w.sets, 'set'),
      _Load.workouts => _count(w.workouts, 'workout'),
      _Load.time => fmtDuration(w.time),
    };

    final current = weeks.last;
    return ChartCard(
      title: 'Weekly training',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChipChoice(
            values: _Load.values,
            selected: _load,
            label: (l) => l.label,
            onSelected: (l) => setState(() => _load = l),
          ),
          const SizedBox(height: Space.md),
          WeekBarChart(
            weeks: [for (final w in weeks) w.start],
            values: [for (final w in weeks) value(w)],
            goal: _load == _Load.workouts ? goal?.toDouble() : null,
            yLabel: _load == _Load.time ? (v) => '${fmtNum(v)} h' : fmtCompact,
            tooltip: (i) =>
                'Week of ${_short.format(weeks[i].start)}\n${fmt(weeks[i])}',
            semanticLabel:
                '${_load.label} per week, last ${weeks.length} weeks. '
                'This week ${fmt(current)}.',
            animateKey: _load,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ muscle balance

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sets = ref.watch(muscleBalanceProvider);
    if (sets == null || sets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: ChartCard(
        title: 'Muscle balance',
        caption:
            'Working sets per week over the last 4 weeks. '
            'The band marks 10–20 sets.',
        child: BalanceBars(sets: sets),
      ),
    );
  }
}

// ------------------------------------------------------------ top lifts

class _TopLiftsCard extends ConsumerWidget {
  const _TopLiftsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lifts = ref.watch(topLiftsProvider);
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    if (lifts == null || lifts.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: ChartCard(
        title: 'Top lifts',
        caption: 'Last 6 months',
        child: Column(
          children: [
            for (final l in lifts)
              InkWell(
                borderRadius: Radii.mdAll,
                onTap: () => context.go('/progress/exercise/${l.exercise.id}'),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinTap),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.exercise.name, style: t.bodyLarge),
                              Text(
                                l.metric.label,
                                style: t.bodySmall?.copyWith(
                                  color: lift.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (l.series.length > 1) ...[
                          const SizedBox(width: Space.md),
                          Sparkline([for (final p in l.series) p.value]),
                        ],
                        const SizedBox(width: Space.md),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              fmtMetric(l.metric, l.series.last.value, unit),
                              style: t.titleSmall?.copyWith(
                                fontFeatures: Fonts.tabular,
                              ),
                            ),
                            if (l.series.length > 1)
                              Text(
                                fmtMetricDelta(
                                  l.metric,
                                  l.series.last.value - l.series.first.value,
                                  unit,
                                ),
                                style: t.bodySmall?.copyWith(
                                  color: lift.muted,
                                  fontFeatures: Fonts.tabular,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ body weight

class _BodyweightCard extends ConsumerWidget {
  const _BodyweightCard(this.entries);

  /// Oldest first.
  final List<BodyweightEntry> entries;

  Future<void> _log(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    final kg = await askBodyweight(
      context,
      unit: settings.weightUnit,
      initialKg: settings.bodyweightKg,
    );
    if (kg != null) await ref.read(settingsProvider.notifier).logBodyweight(kg);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    String kg(double v) => '${fmtWeight(v, unit)} ${unit.label}';
    final last = entries.lastOrNull;

    return ChartCard(
      title: 'Body weight',
      trailing: TextButton(
        onPressed: () => _log(context, ref),
        child: const Text('Log'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (last == null)
            Text(
              'Log your weight to see how it changes.',
              style: t.bodyMedium?.copyWith(color: lift.muted),
            )
          else ...[
            Text(
              kg(last.kg),
              style: t.titleLarge?.copyWith(fontFeatures: Fonts.tabular),
            ),
            Text(
              entries.length < 2
                  ? _day.format(last.date)
                  : '${fmtDelta(kgToUnit(last.kg - entries.first.kg, unit))} '
                        '${unit.label} since ${_short.format(entries.first.date)}',
              style: t.bodySmall?.copyWith(color: lift.muted),
            ),
          ],
          if (entries.length >= 2) ...[
            const SizedBox(height: Space.md),
            TrendChart(
              points: [
                for (final e in entries)
                  TrendPoint(e.date, kgToUnit(e.kg, unit)),
              ],
              showRecords: false,
              tooltip: (i) =>
                  '${kg(entries[i].kg)}\n${_short.format(entries[i].date)}',
              semanticLabel:
                  'Body weight, ${entries.length} entries. Latest ${kg(last!.kg)}.',
            ),
          ],
          if (entries.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => showAppSheet<void>(
                  context,
                  (_) => const _EntriesSheet(),
                ),
                child: Text('All entries (${entries.length})'),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntriesSheet extends ConsumerWidget {
  const _EntriesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(bodyweightEntriesProvider).value ?? const [];
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
          child: Text('Body weight', style: t.titleLarge),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in entries.reversed)
                ListTile(
                  title: Text(
                    '${fmtWeight(e.kg, unit)} ${unit.label}',
                    style: const TextStyle(fontFeatures: Fonts.tabular),
                  ),
                  subtitle: Text(_day.format(e.date)),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const AppIcon(AppIcons.trash),
                    onPressed: () => ref
                        .read(settingsProvider.notifier)
                        .deleteBodyweightEntry(e.date),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
      ],
    );
  }
}
