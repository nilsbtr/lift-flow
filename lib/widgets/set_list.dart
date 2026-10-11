import 'package:material_ui/material_ui.dart';

import '../data/database.dart';
import '../domain/units.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Logged sets of one exercise with their type, effort and notes: one set per
/// line, or all on one wrapping line when [compact]. Effort is shown in
/// [effort] mode and hidden when that is off.
class SetList extends StatelessWidget {
  const SetList({
    super.key,
    required this.exercise,
    required this.sets,
    required this.unit,
    required this.effort,
    this.compact = false,
  });

  final Exercise exercise;
  final List<WorkoutSet> sets;
  final WeightUnit unit;
  final EffortMode effort;
  final bool compact;

  String _set(WorkoutSet s) => fmtSet(
    type: exercise.trackingType,
    mode: exercise.loadMode,
    loadKg: s.loadKg,
    reps: s.reps,
    unit: unit,
  );

  String? _effort(WorkoutSet s) => effort == EffortMode.off || s.rpe == null
      ? null
      : fmtEffortLabel(s.rpe!, effort);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    final labels = setLabels(sets.map((s) => s.setType));
    final noteStyle = t.bodySmall?.copyWith(
      color: muted,
      fontStyle: FontStyle.italic,
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                for (final (i, s) in sets.indexed) ...[
                  if (i > 0) const TextSpan(text: '   '),
                  if (s.setType.letter.isNotEmpty)
                    TextSpan(
                      text: '${s.setType.letter} ',
                      semanticsLabel: '${s.setType.label}, ',
                      style: TextStyle(
                        color: setTypeColor(context, s.setType),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  TextSpan(text: _set(s)),
                  if (_effort(s) case final e?) TextSpan(text: ' · $e'),
                ],
              ],
            ),
            style: t.bodyMedium?.copyWith(color: muted),
          ),
          for (final (i, s) in sets.indexed)
            if (s.note case final note?)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${setSemantics(s.setType, labels[i])}: $note',
                  style: noteStyle,
                ),
              ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, s) in sets.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    labels[i],
                    semanticsLabel: setSemantics(s.setType, labels[i]),
                    style: t.bodyLarge?.copyWith(
                      color: setTypeColor(context, s.setType) ?? muted,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: _set(s),
                          children: [
                            if (_effort(s) case final e?)
                              TextSpan(
                                text: '   $e',
                                style: t.bodyMedium?.copyWith(color: muted),
                              ),
                          ],
                        ),
                        style: t.bodyLarge,
                      ),
                      if (s.note case final note?) Text(note, style: noteStyle),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
