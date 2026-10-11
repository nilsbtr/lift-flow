/// A last set older than this makes finishing offer to end the workout there.
const kStaleSetAfter = Duration(minutes: 30);

/// A live workout older than this was probably forgotten. Stats stop counting
/// its time here too (`kMaxWorkoutTime`).
const kForgottenAfter = Duration(hours: 4);

/// The time to offer as the end of a workout whose last set was logged at
/// [lastSetAt], or null when ending now is fine.
DateTime? staleEnd(
  DateTime? lastSetAt, {
  required DateTime startedAt,
  required DateTime now,
}) {
  if (lastSetAt == null || !lastSetAt.isAfter(startedAt)) return null;
  return now.difference(lastSetAt) > kStaleSetAfter ? lastSetAt : null;
}

/// Whether a live workout has run long enough to ask if it was forgotten.
bool looksForgotten(DateTime startedAt, DateTime now) =>
    now.difference(startedAt) > kForgottenAfter;

/// [end] kept between [start] and [now].
DateTime endWithin(
  DateTime end, {
  required DateTime start,
  required DateTime now,
}) => end.isAfter(now)
    ? now
    : end.isBefore(start)
    ? start
    : end;
