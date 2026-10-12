import 'package:timezone/timezone.dart' as tz;

/// Reminder notifications use ids 101 (Monday) to 107 (Sunday).
const kReminderBaseId = 100;

/// A weekly repeating notification, in local wall-clock time.
typedef ReminderSlot = ({int id, int weekday, int hour, int minute});

/// Bit 0 is Monday, bit 6 is Sunday ([DateTime.monday] is 1).
bool reminderOn(int days, int weekday) => days & (1 << (weekday - 1)) != 0;

int toggleReminderDay(int days, int weekday) => days ^ (1 << (weekday - 1));

/// What to schedule and what to cancel for the chosen [days] and [minutes]
/// after midnight. Every day gets its own id, so a change only touches the
/// days that changed and no days at all cancels everything.
({List<ReminderSlot> schedule, List<int> cancel}) planReminders(
  int days,
  int minutes,
) {
  final schedule = <ReminderSlot>[];
  final cancel = <int>[];
  for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
    final id = kReminderBaseId + weekday;
    if (reminderOn(days, weekday)) {
      schedule.add((
        id: id,
        weekday: weekday,
        hour: minutes ~/ 60,
        minute: minutes % 60,
      ));
    } else {
      cancel.add(id);
    }
  }
  return (schedule: schedule, cancel: cancel);
}

/// The first time [slot] fires after [now], in [now]'s zone. The notification
/// then repeats weekly at the same wall-clock time, also across a change of
/// daylight saving time: the date is built from calendar fields, never by
/// adding 24 hours.
tz.TZDateTime nextReminder(tz.TZDateTime now, ReminderSlot slot) {
  final days = (slot.weekday - now.weekday) % 7;
  var at = tz.TZDateTime(
    now.location,
    now.year,
    now.month,
    now.day + days,
    slot.hour,
    slot.minute,
  );
  if (!at.isAfter(now)) {
    at = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day + days + 7,
      slot.hour,
      slot.minute,
    );
  }
  return at;
}
