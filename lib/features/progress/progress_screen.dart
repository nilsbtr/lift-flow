import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/records.dart';
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
import '../history/workout_day_sheet.dart';
import 'progress_providers.dart';

final _day = DateFormat('EEE, d MMM y');
final _short = DateFormat('d MMM');
final _shortYear = DateFormat('d MMM y');

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
            const _RecordsCard(),
            _LifetimeCard(history),
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
    final firstDay = ref.watch(
      settingsProvider.select((s) => s.firstDayOfWeek),
    );

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
            firstDay: firstDay,
            semanticLabel: 'Training calendar',
            labelBuilder: (weeks) {
              final recent = weeklyStats(
                history,
                now: now,
                weeks: weeks,
                firstDay: firstDay,
              ).map((w) => w.workouts).sum;
              return '${_count(recent, 'workout')} in the last '
                  '${_count(weeks, 'week')}';
            },
            onTapDay: (day) => showWorkoutDaySheet(
              context,
              day: day,
              history: history,
              workoutPath: (id) => '/progress/workout/$id',
            ),
          ),
        ],
      ),
    );
  }
}

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

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
  TrendRange _range = TrendRange.m3;

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final goal = ref.watch(settingsProvider.select((s) => s.weeklyGoal));
    final firstDay = ref.watch(
      settingsProvider.select((s) => s.firstDayOfWeek),
    );
    final now = DateTime.now();
    final weeks = weeklyStats(
      widget.history,
      now: now,
      firstDay: firstDay,
      weeks: weeksInRange(
        _range,
        now: now,
        earliest: widget.history.map((w) => w.startedAt).minOrNull,
        firstDay: firstDay,
      ),
    );

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
            animateKey: (_load, _range),
          ),
          const SizedBox(height: Space.md),
          ChipChoice(
            values: TrendRange.values,
            selected: _range,
            label: (r) => r.label,
            onSelected: (r) => setState(() => _range = r),
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
    final balance = ref.watch(muscleBalanceProvider);
    if (balance == null || balance.sets.isEmpty) return const SizedBox.shrink();
    final (min, max) = ref.watch(
      settingsProvider.select((s) => (s.balanceMin, s.balanceMax)),
    );
    final weeks = balance.weeks;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: ChartCard(
        title: 'Muscle balance',
        trailing: _InfoTip(
          'Aim for $min–$max working sets per muscle each week. Below is '
          'light, above is heavy. Secondary muscles count half a set. '
          'Change the band in Settings.',
        ),
        caption:
            'Working sets per week over '
            '${weeks == 1 ? 'the last week' : 'the last $weeks weeks'}. '
            'The band marks $min–$max sets.',
        child: BalanceBars(
          sets: balance.sets,
          low: min.toDouble(),
          high: max.toDouble(),
        ),
      ),
    );
  }
}

/// An info icon that explains itself in a tooltip on tap.
class _InfoTip extends StatelessWidget {
  const _InfoTip(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    triggerMode: TooltipTriggerMode.tap,
    showDuration: const Duration(seconds: 6),
    child: SizedBox.square(
      dimension: kCompactTap,
      child: Center(
        child: AppIcon(
          AppIcons.info,
          size: IconSizes.sm,
          color: LiftColors.of(context).muted,
        ),
      ),
    ),
  );
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
                              fmtMetric(
                                l.metric,
                                l.series.last.value,
                                unit,
                                mode: l.exercise.loadMode,
                              ),
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
                                  mode: l.exercise.loadMode,
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

// ------------------------------------------------------------ records

class _RecordsCard extends ConsumerWidget {
  const _RecordsCard();

  static const _count = 5;

  static TrendMetric _metricOf(PrKind k) => switch (k) {
    PrKind.heaviest => TrendMetric.heaviest,
    PrKind.e1rm => TrendMetric.e1rm,
    PrKind.bestLoad => TrendMetric.bestLoad,
    PrKind.mostReps => TrendMetric.reps,
    PrKind.longestTime => TrendMetric.time,
    PrKind.longestDistance => TrendMetric.distance,
    PrKind.bestPace => TrendMetric.pace,
  };

  /// The record kind to headline for an exercise, by its usual metrics.
  static PrKind _headline(Exercise e, Map<PrKind, double> v) {
    for (final m in metricsFor(e.trackingType, e.loadMode)) {
      for (final k in v.keys) {
        if (_metricOf(k) == m) return k;
      }
    }
    return v.keys.first;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(prHistoryProvider).value;
    final exercises = ref.watch(exercisesProvider).value;
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    if (events == null || exercises == null) return const SizedBox.shrink();
    final byId = {for (final e in exercises) e.id: e};
    // Newest first, one row per exercise.
    final seen = <int>{};
    final latest = [
      for (final ev in events)
        if (byId.containsKey(ev.exerciseId) && seen.add(ev.exerciseId)) ev,
    ].take(_count).toList();
    if (latest.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    final year = DateTime.now().year;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: ChartCard(
        title: 'Records',
        caption: 'Latest personal record per exercise',
        child: Column(
          children: [
            for (final ev in latest)
              InkWell(
                borderRadius: Radii.mdAll,
                onTap: () => context.go('/progress/exercise/${ev.exerciseId}'),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinTap),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Builder(
                      builder: (context) {
                        final e = byId[ev.exerciseId]!;
                        final kind = _headline(e, ev.values);
                        final more = ev.values.length - 1;
                        return Row(
                          children: [
                            AppIcon(
                              AppIcons.trophySolid,
                              size: IconSizes.sm,
                              color: lift.record,
                            ),
                            const SizedBox(width: Space.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.name, style: t.bodyLarge),
                                  Text(
                                    '${kind.label} '
                                    '${fmtMetric(_metricOf(kind), ev.values[kind]!, unit, mode: e.loadMode)}'
                                    '${more > 0 ? ' · +$more more' : ''}',
                                    style: t.bodySmall?.copyWith(
                                      color: lift.muted,
                                      fontFeatures: Fonts.tabular,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: Space.md),
                            Text(
                              (ev.date.year == year ? _short : _shortYear)
                                  .format(ev.date),
                              style: t.bodySmall?.copyWith(color: lift.muted),
                            ),
                          ],
                        );
                      },
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

// ------------------------------------------------------------ lifetime

String _hours(Duration d) => d.inHours >= 1 ? '${d.inHours} h' : fmtDuration(d);

class _LifetimeCard extends ConsumerWidget {
  const _LifetimeCard(this.history);
  final List<Workout> history;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final stats = periodStats(history);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: ChartCard(
        title: 'Lifetime',
        trailing: TextButton(
          onPressed: () =>
              showAppSheet<void>(context, (_) => _YearSheet(history)),
          child: const Text('Year in review'),
        ),
        child: _StatGrid(_periodRows(stats, unit)),
      ),
    );
  }
}

List<(String, String)> _periodRows(PeriodStats s, WeightUnit unit) => [
  (fmtCompact(s.workouts.toDouble()), 'Workouts'),
  (fmtCompact(s.sets.toDouble()), 'Sets'),
  ('${fmtCompact(kgToUnit(s.volumeKg, unit))} ${unit.label}', 'Volume'),
  (_hours(s.time), 'Time'),
];

/// Value and label pairs in two columns.
class _StatGrid extends StatelessWidget {
  const _StatGrid(this.stats);
  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    Widget cell((String, String)? s) => Expanded(
      child: s == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.$1,
                  style: t.titleLarge?.copyWith(fontFeatures: Fonts.tabular),
                ),
                Text(s.$2, style: t.bodySmall?.copyWith(color: muted)),
              ],
            ),
    );
    return Column(
      spacing: Space.md,
      children: [
        for (var i = 0; i < stats.length; i += 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cell(stats[i]),
              cell(i + 1 < stats.length ? stats[i + 1] : null),
            ],
          ),
      ],
    );
  }
}

class _YearSheet extends ConsumerStatefulWidget {
  const _YearSheet(this.history);
  final List<Workout> history;

  @override
  ConsumerState<_YearSheet> createState() => _YearSheetState();
}

class _YearSheetState extends ConsumerState<_YearSheet> {
  int? _year;

  @override
  Widget build(BuildContext context) {
    final years = workoutYears(widget.history);
    final year = _year ?? years.firstOrNull ?? DateTime.now().year;
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final records = ref.watch(prHistoryProvider).value;
    final stats = periodStats(widget.history, year: year);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Year in review', style: Theme.of(context).textTheme.titleLarge),
          if (years.length > 1) ...[
            const SizedBox(height: Space.md),
            ChipChoice(
              values: years,
              selected: year,
              label: (y) => '$y',
              onSelected: (y) => setState(() => _year = y),
            ),
          ],
          const SizedBox(height: Space.lg),
          _StatGrid([
            ..._periodRows(stats, unit),
            ('${stats.days}', 'Training days'),
            (
              records == null
                  ? '–'
                  : '${records.where((r) => r.date.year == year).length}',
              'Records',
            ),
          ]),
        ],
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
    final w = await askBodyweight(
      context,
      unit: settings.weightUnit,
      initialKg: settings.bodyweightKg,
      taken: {for (final e in entries) e.date},
    );
    if (w != null) {
      await ref
          .read(settingsProvider.notifier)
          .logBodyweight(w.kg, date: w.date);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    String kg(double v) => '${fmtWeight(v, unit)} ${unit.label}';
    final last = entries.lastOrNull;
    final avgs = bodyweightAverages(entries);

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
                  : '${fmtDelta(kgToUnit(avgs.last - avgs.first, unit))} '
                        '${unit.label} since ${_short.format(entries.first.date)}'
                        ' · 7-day avg',
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
              average: [for (final a in avgs) kgToUnit(a, unit)],
              tooltip: (i) =>
                  '${kg(entries[i].kg)}\n7-day avg ${kg(avgs[i])}\n'
                  '${_short.format(entries[i].date)}',
              semanticLabel:
                  'Body weight, ${entries.length} entries. Latest ${kg(last!.kg)}, '
                  '7-day average ${kg(avgs.last)}.',
            ),
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'Dots are weigh-ins. The line is the 7-day average.',
                style: t.bodySmall?.copyWith(color: lift.muted),
              ),
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

class _EntriesSheet extends ConsumerStatefulWidget {
  const _EntriesSheet();

  @override
  ConsumerState<_EntriesSheet> createState() => _EntriesSheetState();
}

class _EntriesSheetState extends ConsumerState<_EntriesSheet> {
  /// The last deleted entry, offered for undo.
  BodyweightEntry? _deleted;

  SettingsController get _ctrl => ref.read(settingsProvider.notifier);

  Future<void> _edit(BodyweightEntry e, List<BodyweightEntry> all) async {
    final w = await askBodyweight(
      context,
      unit: ref.read(settingsProvider).weightUnit,
      initialKg: e.kg,
      initialDate: e.date,
      editing: true,
      taken: {for (final o in all) o.date},
    );
    if (w != null) {
      await _ctrl.logBodyweight(w.kg, date: w.date, replacing: e.date);
    }
  }

  Future<void> _delete(BodyweightEntry e) async {
    setState(() => _deleted = e);
    await _ctrl.deleteBodyweightEntry(e.date);
  }

  Future<void> _undo(BodyweightEntry e) async {
    setState(() => _deleted = null);
    await _ctrl.logBodyweight(e.kg, date: e.date);
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(bodyweightEntriesProvider).value ?? const [];
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final t = Theme.of(context).textTheme;
    final deleted = _deleted;
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
                  onTap: () => _edit(e, entries),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const AppIcon(AppIcons.edit),
                        onPressed: () => _edit(e, entries),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const AppIcon(AppIcons.trash),
                        onPressed: () => _delete(e),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (deleted != null)
          ListTile(
            title: Text(
              'Deleted ${_short.format(deleted.date)}',
              style: t.bodyMedium?.copyWith(
                color: LiftColors.of(context).muted,
              ),
            ),
            trailing: TextButton(
              onPressed: () => _undo(deleted),
              child: const Text('Undo'),
            ),
          ),
        const SizedBox(height: Space.sm),
      ],
    );
  }
}
