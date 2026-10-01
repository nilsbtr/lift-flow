import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../data/workout_repository.dart';
import '../../domain/records.dart';
import '../../domain/stats.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/charts/sparkline.dart';
import '../../widgets/common.dart';

/// Shown after finishing a workout.
class FinishSummarySheet extends ConsumerStatefulWidget {
  const FinishSummarySheet({super.key, required this.workoutId});
  final int workoutId;

  @override
  ConsumerState<FinishSummarySheet> createState() => _FinishSummarySheetState();
}

class _FinishSummarySheetState extends ConsumerState<FinishSummarySheet> {
  bool _savedTemplate = false;

  Future<void> _saveAsTemplate(LoadedWorkout w) async {
    final name = await promptText(
      context,
      title: 'Save as template',
      initial: w.workout.name == 'Workout' ? '' : w.workout.name,
      hint: 'Name, e.g. Push',
      action: 'Save',
    );
    if (name == null || name.trim().isEmpty) return;
    final repo = ref.read(templateRepoProvider);
    final items = await repo.itemsFromWorkout(widget.workoutId);
    await repo.save(name: name, items: items);
    if (mounted) setState(() => _savedTemplate = true);
  }

  Future<void> _updateTemplate(int templateId) async {
    final repo = ref.read(templateRepoProvider);
    final tpl = await repo.get(templateId);
    if (tpl == null) return;
    final items = await repo.itemsFromWorkout(widget.workoutId);
    await repo.save(id: templateId, name: tpl.template.name, items: items);
    if (mounted) setState(() => _savedTemplate = true);
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(workoutDetailProvider(widget.workoutId)).value;
    final insights = ref
        .watch(workoutInsightsProvider(widget.workoutId))
        .value;
    final templates = ref.watch(templatesProvider).value ?? const [];
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);

    if (loaded == null) return const SizedBox(height: 200);
    final w = loaded.workout;
    final tid = w.templateId;
    final hasTemplate =
        tid != null && templates.any((d) => d.template.id == tid);
    final duration = (w.endedAt ?? DateTime.now()).difference(w.startedAt);
    final prev = insights?.previous;
    final lifts = [
      for (final ex in loaded.exercises)
        if (insights?.lifts[ex.exercise.id] case final l?) (ex.exercise, l),
    ];

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppIcons.checkSolid, color: lift.done, size: IconSizes.lg),
            const SizedBox(height: Space.sm),
            Text(
              'Workout complete',
              style: t.headlineSmall,
              textAlign: TextAlign.center,
            ),
            Text(
              w.name,
              style: t.bodyMedium?.copyWith(color: lift.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.lg),
            Row(
              children: [
                _Metric(
                  'Time',
                  fmtDuration(duration),
                  delta: prev == null
                      ? null
                      : '${fmtDelta((workoutTime(w) - workoutTime(prev)).inMinutes.toDouble())} min',
                ),
                _Metric(
                  'Sets',
                  '${w.totalSets}',
                  delta: prev == null
                      ? null
                      : fmtDelta((w.totalSets - prev.totalSets).toDouble()),
                ),
                if (w.totalVolumeKg > 0)
                  _Metric(
                    'Volume',
                    fmtVolume(w.totalVolumeKg, unit),
                    delta: prev == null || prev.totalVolumeKg <= 0
                        ? null
                        : fmtMetricDelta(
                            TrendMetric.volume,
                            w.totalVolumeKg - prev.totalVolumeKg,
                            unit,
                          ),
                  ),
              ],
            ),
            if (prev != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'Compared with ${DateFormat('d MMM').format(prev.startedAt)}',
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: lift.muted),
                ),
              ),
            if (lifts.isNotEmpty) ...[
              const SizedBox(height: Space.lg),
              for (final (e, l) in lifts) _LiftRow(e, l, unit),
            ],
            const SizedBox(height: Space.xl),
            if (!_savedTemplate) ...[
              if (hasTemplate)
                OutlinedButton(
                  onPressed: () => _updateTemplate(tid),
                  child: const Text('Update template with this workout'),
                )
              else
                OutlinedButton(
                  onPressed: () => _saveAsTemplate(loaded),
                  child: const Text('Save as template'),
                ),
              const SizedBox(height: Space.sm),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Text(
                  'Template saved',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: lift.done),
                ),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.delta});
  final String label;
  final String value;
  final String? delta;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: t.headlineSmall?.copyWith(fontFeatures: Fonts.tabular),
          ),
          Text(label.toUpperCase(), style: t.labelSmall?.copyWith(color: muted)),
          if (delta case final d?)
            Text(
              d,
              style: t.labelSmall?.copyWith(
                color: muted,
                fontFeatures: Fonts.tabular,
              ),
            ),
        ],
      ),
    );
  }
}

/// One exercise: its main metric over recent sessions, change and PRs.
class _LiftRow extends StatelessWidget {
  const _LiftRow(this.exercise, this.insight, this.unit);
  final Exercise exercise;
  final LiftInsight insight;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    final m = insight.metric;
    final pr = insight.prs.isNotEmpty;
    final delta = insight.delta;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.name, style: t.bodyLarge),
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(m.label, style: t.bodySmall?.copyWith(color: lift.muted)),
                    for (final k in PrKind.values)
                      if (insight.prs.contains(k))
                        Tag(
                          k.label,
                          color: lift.record,
                          icon: AppIcons.trophySolid,
                        ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          if (insight.series.length > 1) ...[
            Sparkline(
              [for (final p in insight.series) p.value],
              color: pr ? lift.record : null,
            ),
            const SizedBox(width: Space.md),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmtMetric(m, insight.value, unit),
                style: t.titleSmall?.copyWith(fontFeatures: Fonts.tabular),
              ),
              if (delta != null)
                Text(
                  fmtMetricDelta(m, delta, unit),
                  style: t.bodySmall?.copyWith(
                    color: delta > 1e-6 ? lift.done : lift.muted,
                    fontFeatures: Fonts.tabular,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  required String action,
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: hint, counterText: ''),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: Text(action),
        ),
      ],
    ),
  );
}
