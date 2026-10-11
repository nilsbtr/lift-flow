const kMaxRestSeconds = 3600;

/// The rest countdown after moving its end by [deltaSeconds], or null when
/// nothing would be left. The end is capped at [kMaxRestSeconds] from [now].
({DateTime endsAt, int totalSeconds})? adjustRest(
  DateTime endsAt,
  int totalSeconds,
  int deltaSeconds,
  DateTime now,
) {
  final next = endsAt.add(Duration(seconds: deltaSeconds));
  if (!next.isAfter(now)) return null;
  final latest = now.add(const Duration(seconds: kMaxRestSeconds));
  final ms = endsAt.difference(now).inMilliseconds;
  final left = ms <= 0 ? 0 : (ms / 1000).ceil();
  return (
    endsAt: next.isAfter(latest) ? latest : next,
    totalSeconds: (totalSeconds + deltaSeconds).clamp(
      left.clamp(0, kMaxRestSeconds),
      kMaxRestSeconds,
    ),
  );
}
