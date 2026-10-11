const kMaxRestSeconds = 3600;

/// Quick rest times on the rest bar.
const kRestPresets = [60, 90, 120, 180];

/// Parses "90" (seconds) or "1:30" into 1 to [kMaxRestSeconds] seconds, or
/// null for anything else.
int? parseRestTime(String text) {
  final m = RegExp(r'^(?:(\d{1,2}):([0-5]?\d)|(\d{1,4}))$')
      .firstMatch(text.trim());
  if (m == null) return null;
  final seconds = m[3] != null
      ? int.parse(m[3]!)
      : int.parse(m[1]!) * 60 + int.parse(m[2]!);
  return seconds >= 1 && seconds <= kMaxRestSeconds ? seconds : null;
}

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
