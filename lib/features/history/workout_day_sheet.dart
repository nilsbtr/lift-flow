import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/stats.dart';
import '../../domain/units.dart';
import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';

/// Shows the workouts of [day] from [history] in a sheet.
/// [workoutPath] builds the detail route inside the current tab, e.g.
/// `(id) => '/history/$id'`.
Future<void> showWorkoutDaySheet(
  BuildContext context, {
  required DateTime day,
  required Iterable<Workout> history,
  required String Function(int workoutId) workoutPath,
}) => showAppSheet<void>(
  context,
  (_) => WorkoutDaySheet(
    day: day,
    // History is newest first; a day reads oldest first.
    workouts: [
      for (final w in history)
        if (dayOf(w.startedAt) == day) w,
    ].reversed.toList(),
    workoutPath: workoutPath,
  ),
);

/// The workouts of one day; a tap opens the workout at [workoutPath].
class WorkoutDaySheet extends StatelessWidget {
  const WorkoutDaySheet({
    super.key,
    required this.day,
    required this.workouts,
    required this.workoutPath,
  });

  final DateTime day;
  final List<Workout> workouts;
  final String Function(int workoutId) workoutPath;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
          child: Text(
            DateFormat('EEE, d MMM y').format(day),
            style: t.titleLarge,
          ),
        ),
        for (final w in workouts)
          ListTile(
            title: Text(w.name),
            subtitle: Text(
              '${fmtDuration(workoutTime(w))} · '
              '${w.totalSets} ${w.totalSets == 1 ? 'set' : 'sets'}',
            ),
            trailing: const AppIcon(AppIcons.chevronRight),
            onTap: () {
              final router = GoRouter.of(context);
              Navigator.pop(context);
              router.go(workoutPath(w.id));
            },
          ),
        const SizedBox(height: Space.sm),
      ],
    );
  }
}
