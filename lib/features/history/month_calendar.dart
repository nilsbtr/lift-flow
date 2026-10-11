import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/stats.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// One month at a time with trained days marked. Weeks start on [firstDay].
/// Taps on trained days call [onTapDay].
class MonthCalendar extends StatefulWidget {
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
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  late DateTime _month = DateTime(_now.year, _now.month);

  DateTime get _now => widget.now ?? DateTime.now();

  /// First month with a workout, so paging back stops there.
  DateTime get _earliest {
    var first = _month;
    for (final w in widget.workouts) {
      if (w.startedAt.isBefore(first)) first = w.startedAt;
    }
    return DateTime(first.year, first.month);
  }

  void _page(int by) => setState(() {
    final m = DateTime(_month.year, _month.month + by);
    if (!m.isBefore(_earliest) && !m.isAfter(DateTime(_now.year, _now.month))) {
      _month = m;
    }
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final today = dayOf(_now);

    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final lead = (_month.weekday - widget.firstDay) % 7;
    final rows = (lead + days + 6) ~/ 7;
    final count = <DateTime, int>{};
    var total = 0;
    for (final w in widget.workouts) {
      final d = dayOf(w.startedAt);
      if (d.year == _month.year && d.month == _month.month) {
        count[d] = (count[d] ?? 0) + 1;
        total++;
      }
    }
    final canBack = _month.isAfter(_earliest);
    final canForward = _month.isBefore(DateTime(_now.year, _now.month));
    final label = DateFormat('MMMM y').format(_month);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() > 200) _page(v > 0 ? -1 : 1);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.sm,
          Space.lg,
          Space.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: canBack ? () => _page(-1) : null,
                  icon: const AppIcon(AppIcons.arrowLeft),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(label, style: t.titleMedium),
                      Text(
                        total == 0
                            ? 'No workouts'
                            : '$total ${total == 1 ? 'workout' : 'workouts'}',
                        style: t.bodySmall?.copyWith(color: lift.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: canForward ? () => _page(1) : null,
                  icon: const AppIcon(AppIcons.chevronRight),
                ),
              ],
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
                        ][(widget.firstDay - 1 + i) % 7],
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
                      child: _cell(
                        r * 7 + c - lead + 1,
                        days,
                        count,
                        today,
                        t,
                        lift,
                        scheme,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    int dayNumber,
    int daysInMonth,
    Map<DateTime, int> count,
    DateTime today,
    TextTheme t,
    LiftColors lift,
    ColorScheme scheme,
  ) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: kMinTap);
    }
    final day = DateTime(_month.year, _month.month, dayNumber);
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
        onTap: trained ? () => widget.onTapDay(day) : null,
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
