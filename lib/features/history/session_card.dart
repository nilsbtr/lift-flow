import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../data/workout_repository.dart';
import '../../domain/stats.dart';
import '../../domain/units.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/charts/chart_card.dart';
import '../../widgets/charts/session_timeline.dart';
import '../../widgets/charts/split_bar.dart';

/// Muscle split, set timeline and rest times of a finished workout.
class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.workout});
  final LoadedWorkout workout;

  @override
  Widget build(BuildContext context) {
    final w = workout.workout;
    final end = w.endedAt;
    final split = muscleSplit(workout);
    final marks = sessionTimeline(workout);
    final rest = restAnalysis(marks);
    if (end == null || (split.isEmpty && marks.length < 2)) {
      return const SizedBox.shrink();
    }
    final t = Theme.of(context).textTheme;
    final muted = t.bodySmall?.copyWith(color: LiftColors.of(context).muted);
    final clock = DateFormat('HH:mm');

    return ChartCard(
      title: 'Session',
      caption: rest == null
          ? null
          : 'Average rest ${fmtClock(rest.average.inSeconds)} · '
                'longest ${fmtClock(rest.longest.inSeconds)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (split.isNotEmpty) SplitBar(split: split),
          if (marks.length >= 2) ...[
            if (split.isNotEmpty) const SizedBox(height: Space.lg),
            SessionTimeline(
              marks: marks,
              start: w.startedAt,
              end: end,
              lanes: workout.exercises.length,
              semanticLabel:
                  '${marks.length} sets from ${clock.format(w.startedAt)} '
                  'to ${clock.format(end)}, one row per exercise.',
            ),
            const SizedBox(height: Space.xs),
            ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(clock.format(w.startedAt), style: muted),
                  Text(clock.format(end), style: muted),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
