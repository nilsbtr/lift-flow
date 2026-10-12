import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../data/workout_repository.dart';
import '../../domain/records.dart';
import '../../domain/stats.dart';
import '../../domain/units.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/charts/chart_card.dart';
import '../../widgets/charts/scatter_chart.dart';
import '../../widgets/charts/trend_chart.dart';

final _day = DateFormat('d MMM y');
final _short = DateFormat('d MMM');

/// Trend and all-sets charts for one exercise, sharing a time range.
class ExerciseCharts extends StatefulWidget {
  const ExerciseCharts({
    super.key,
    required this.exercise,
    required this.sessions,
    required this.unit,
  });

  final Exercise exercise;

  /// Newest first.
  final List<ExerciseSession> sessions;
  final WeightUnit unit;

  @override
  State<ExerciseCharts> createState() => _ExerciseChartsState();
}

class _ExerciseChartsState extends State<ExerciseCharts> {
  TrendMetric? _metric;
  TrendRange? _range;
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final e = widget.exercise;
    final unit = widget.unit;
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    final now = DateTime.now();

    final facts = sessionFacts(e, widget.sessions);
    final all = {
      for (final m in metricsFor(e.trackingType, e.loadMode))
        m: sessionSeries(facts, m),
    }..removeWhere((_, s) => s.isEmpty);
    if (all.isEmpty) return const SizedBox.shrink();

    final metric = all.containsKey(_metric) ? _metric! : all.keys.first;
    final series = all[metric]!;
    final range =
        _range ?? defaultRange(series.map((p) => p.date), now);
    final since = range.since(now);
    final shown = [
      for (final p in series)
        if (since == null || !p.date.isBefore(since)) p,
    ];
    final selected = _selected != null && _selected! < shown.length
        ? shown[_selected!]
        : null;
    final latest = shown.isEmpty ? series.last : shown.last;
    final best = series.map((p) => p.value).reduce((a, b) => a > b ? a : b);

    final mode = e.loadMode;
    String fmt(double v) => fmtMetric(metric, v, unit, mode: mode);

    final (headline, sub) = switch (selected) {
      final p? => (
        fmt(p.value),
        '${_day.format(p.date)}${p.isRecord ? ' · PR' : ''}',
      ),
      null when shown.length >= 2 => (
        fmt(latest.value),
        '${fmtMetricDelta(metric, shown.last.value - shown.first.value, unit, mode: mode)} '
            'since ${_short.format(shown.first.date)}',
      ),
      null => (fmt(latest.value), _day.format(latest.date)),
    };

    final scatter = hasRepMaxes(e.trackingType, e.loadMode)
        ? [
            for (final f in facts)
              if ((f.reps ?? 0) > 0 &&
                  f.loadKg != null &&
                  (since == null || !f.startedAt.isBefore(since)))
                (f, ScatterPoint(f.startedAt, kgToUnit(f.loadKg!, unit), f.reps!)),
          ]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChartCard(
          title: 'Trend',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (all.length > 1) ...[
                ChipChoice(
                  values: all.keys.toList(),
                  selected: metric,
                  label: (m) => m.label,
                  onSelected: (m) => setState(() {
                    _metric = m;
                    _selected = null;
                  }),
                ),
                const SizedBox(height: Space.md),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: t.headlineSmall?.copyWith(
                      fontFeatures: Fonts.tabular,
                    ),
                  ),
                  Text(sub, style: t.bodySmall?.copyWith(color: lift.muted)),
                ],
              ),
              const SizedBox(height: Space.md),
              if (series.length < 2)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.lg),
                  child: Text(
                    'Log one more session to see a trend.',
                    textAlign: TextAlign.center,
                    style: t.bodyMedium?.copyWith(color: lift.muted),
                  ),
                )
              else ...[
                TrendChart(
                  points: [
                    for (final p in shown)
                      TrendPoint(
                        p.date,
                        metricDisplay(metric, p.value, unit, mode: mode),
                        best: metricDisplay(metric, p.best, unit, mode: mode),
                        isRecord: p.isRecord,
                      ),
                  ],
                  yLabel: (v) => fmtMetricAxis(metric, v, unit, mode: mode),
                  semanticLabel:
                      '${metric.label}, ${shown.length} sessions. '
                      'Latest ${fmt(latest.value)}, best ${fmt(best)}.',
                  onSelect: (i) => setState(() => _selected = i),
                  animateKey: (metric, range),
                ),
                const SizedBox(height: Space.md),
                ChipChoice(
                  values: TrendRange.values,
                  selected: range,
                  label: (r) => r.label,
                  onSelected: (r) => setState(() {
                    _range = r;
                    _selected = null;
                  }),
                ),
              ],
            ],
          ),
        ),
        if (scatter != null && series.length >= 2) ...[
          const SizedBox(height: Space.sm),
          ChartCard(
            title: 'All sets',
            caption: 'Working sets. Bigger dots mean more reps.',
            child: ScatterChart(
              points: [for (final (_, p) in scatter) p],
              semanticLabel:
                  '${scatter.length} working sets, '
                  '${range == TrendRange.all ? 'all time' : 'last ${range.label}'}.',
              yLabel: fmtCompact,
              tooltip: (i) {
                final (f, _) = scatter[i];
                final set = fmtSet(
                  type: e.trackingType,
                  mode: e.loadMode,
                  loadKg: f.loadKg,
                  reps: f.reps,
                  unit: unit,
                );
                return '$set · ${_short.format(f.startedAt)}';
              },
            ),
          ),
        ],
      ],
    );
  }
}
