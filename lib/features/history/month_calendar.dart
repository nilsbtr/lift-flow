import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/stats.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Every month from the current one back to the first with a workout, newest
/// first, in one scroll view. Trained days are marked and weeks start on
/// [firstDay]. Taps on trained days call [onTapDay].
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.workouts,
    required this.onTapDay,
    this.firstDay = DateTime.monday,
    this.now,
  });

  final List<Workout> workouts;
  final ValueChanged<DateTime> onTapDay;

  /// [DateTime.monday] … [DateTime.sunday].
  final int firstDay;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final now = this.now ?? DateTime.now();
    final count = <DateTime, int>{};
    var first = DateTime(now.year, now.month);
    for (final w in workouts) {
      final d = dayOf(w.startedAt);
      count[d] = (count[d] ?? 0) + 1;
      if (d.isBefore(first)) first = DateTime(d.year, d.month);
    }
    final months = (now.year - first.year) * 12 + now.month - first.month + 1;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Space.xxl),
      itemCount: months,
      itemBuilder: (_, i) => _Month(
        month: DateTime(now.year, now.month - i),
        count: count,
        firstDay: firstDay,
        today: dayOf(now),
        onTapDay: onTapDay,
      ),
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({
    required this.month,
    required this.count,
    required this.firstDay,
    required this.today,
    required this.onTapDay,
  });

  final DateTime month;

  /// Workouts per day, across all months.
  final Map<DateTime, int> count;
  final int firstDay;
  final DateTime today;
  final ValueChanged<DateTime> onTapDay;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    final scheme = Theme.of(context).colorScheme;

    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final lead = (month.weekday - firstDay) % 7;
    final rows = (lead + days + 6) ~/ 7;
    var total = 0;
    for (var d = 1; d <= days; d++) {
      total += count[DateTime(month.year, month.month, d)] ?? 0;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              children: [
                Text(DateFormat('MMMM y').format(month), style: t.titleMedium),
                Text(
                  total == 0
                      ? 'No workouts'
                      : '$total ${total == 1 ? 'workout' : 'workouts'}',
                  style: t.bodySmall?.copyWith(color: lift.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      // By weekday, Monday first.
                      const [
                        'M',
                        'T',
                        'W',
                        'T',
                        'F',
                        'S',
                        'S',
                      ][(firstDay - 1 + i) % 7],
                      style: t.labelSmall?.copyWith(color: lift.muted),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Space.xs),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: _cell(r * 7 + c - lead + 1, days, t, lift, scheme),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(
    int dayNumber,
    int daysInMonth,
    TextTheme t,
    LiftColors lift,
    ColorScheme scheme,
  ) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: kMinTap);
    }
    final day = DateTime(month.year, month.month, dayNumber);
    final n = count[day] ?? 0;
    final trained = n > 0;
    final isToday = day == today;
    return Semantics(
      button: trained,
      excludeSemantics: true,
      label:
          '${DateFormat('EEEE d MMMM').format(day)}'
          '${trained ? ', $n ${n == 1 ? 'workout' : 'workouts'}' : ''}',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: trained ? () => onTapDay(day) : null,
        child: SizedBox(
          height: kMinTap,
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: trained ? lift.done : Colors.transparent,
                border: isToday
                    ? Border.all(color: scheme.primary, width: 2)
                    : null,
              ),
              child: Text(
                '$dayNumber',
                style: t.labelLarge?.copyWith(
                  color: trained ? scheme.surface : scheme.onSurface,
                  fontFeatures: Fonts.tabular,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
