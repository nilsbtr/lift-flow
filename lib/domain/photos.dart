import 'package:collection/collection.dart';

import '../data/database.dart';
import 'stats.dart';

const kMaxPhotoNote = 500;

/// Photos of one calendar month, newest first.
typedef PhotoMonth = ({DateTime month, List<ProgressPhoto> photos});

/// Groups photos given newest first into months, newest month first.
List<PhotoMonth> groupByMonth(List<ProgressPhoto> photos) => [
  for (final MapEntry(:key, :value) in groupBy(
    photos,
    (p) => DateTime(p.takenAt.year, p.takenAt.month),
  ).entries)
    (month: key, photos: value),
];

/// The two photos to compare, from [photos] (newest first): the ones with ids
/// [a] and [b] when they exist, otherwise the earliest and the latest, and
/// never the same photo twice by default. Null with fewer than two photos.
(ProgressPhoto, ProgressPhoto)? comparePair(
  List<ProgressPhoto> photos, {
  int? a,
  int? b,
}) {
  if (photos.length < 2) return null;
  final (earliest, latest) = (photos.last, photos.first);
  var left = photos.firstWhereOrNull((p) => p.id == a);
  final right =
      photos.firstWhereOrNull((p) => p.id == b) ??
      (left?.id == latest.id ? earliest : latest);
  left ??= right.id == earliest.id ? latest : earliest;
  return (left, right);
}

/// Moves [takenAt] to the calendar day [day], keeping its time of day and
/// never going past [now].
DateTime redate(DateTime takenAt, DateTime day, DateTime now) {
  final moved = DateTime(
    day.year,
    day.month,
    day.day,
    takenAt.hour,
    takenAt.minute,
    takenAt.second,
  );
  return moved.isAfter(now) ? now : moved;
}

/// A note stored as null when blank.
String? cleanNote(String? note) {
  final t = note?.trim();
  return t == null || t.isEmpty ? null : t;
}

String _n(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// The time between two dates in the coarsest sensible unit, e.g. "9 days",
/// "6 weeks", "4 months" or "1 year 2 months". Order doesn't matter.
String fmtSpan(DateTime a, DateTime b) {
  final (from, to) = a.isAfter(b) ? (dayOf(b), dayOf(a)) : (dayOf(a), dayOf(b));
  final days = DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
  if (days == 0) return 'Same day';
  if (days < 14) return _n(days, 'day');
  final months =
      (to.year - from.year) * 12 +
      to.month -
      from.month -
      (to.day < from.day ? 1 : 0);
  if (months < 1) return _n(days ~/ 7, 'week');
  if (months < 12) return _n(months, 'month');
  final rest = months % 12;
  return [_n(months ~/ 12, 'year'), if (rest > 0) _n(rest, 'month')].join(' ');
}
