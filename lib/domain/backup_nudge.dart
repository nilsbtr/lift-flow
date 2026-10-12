/// Finished workouts after which Home suggests a backup.
const kBackupNudgeEvery = 10;

/// Workouts finished after the later of the last backup and the last dismissal.
int workoutsSinceBackup(
  Iterable<DateTime> finishedAt, {
  DateTime? lastBackupAt,
  DateTime? snoozedAt,
}) {
  final since = [
    lastBackupAt,
    snoozedAt,
  ].nonNulls.fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
  return since == null
      ? finishedAt.length
      : finishedAt.where((d) => d.isAfter(since)).length;
}

bool backupNudgeDue(
  Iterable<DateTime> finishedAt, {
  DateTime? lastBackupAt,
  DateTime? snoozedAt,
}) =>
    workoutsSinceBackup(
      finishedAt,
      lastBackupAt: lastBackupAt,
      snoozedAt: snoozedAt,
    ) >=
    kBackupNudgeEvery;
