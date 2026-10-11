import 'dart:math' as math;

/// Supersets are runs of neighbouring exercises that share a group value.
/// A value on a single exercise, or shared by exercises that are apart, does
/// not link anything.

/// The superset around [index] as `[start, end)`. Null when it stands alone.
({int start, int end})? supersetRun(List<int?> groups, int index) {
  final g = groups[index];
  if (g == null) return null;
  var start = index;
  var end = index + 1;
  while (start > 0 && groups[start - 1] == g) {
    start--;
  }
  while (end < groups.length && groups[end] == g) {
    end++;
  }
  return end - start < 2 ? null : (start: start, end: end);
}

/// For each exercise its place in its superset, or null when it has none.
List<({int index, int count})?> supersetSpans(List<int?> groups) => [
  for (var i = 0; i < groups.length; i++)
    if (supersetRun(groups, i) case final run?)
      (index: i - run.start, count: run.end - run.start)
    else
      null,
];

/// "Superset" for two exercises, "Circuit" for more.
String supersetLabel(int count) => count > 2 ? 'Circuit' : 'Superset';

/// Clears group values that link nothing.
List<int?> dropLoneGroups(List<int?> groups) => [
  for (var i = 0; i < groups.length; i++)
    supersetRun(groups, i) == null ? null : groups[i],
];

/// Links the exercise at [index] with the one after it, merging the supersets
/// either of them is in.
List<int?> linkGroups(List<int?> groups, int index) {
  if (index < 0 || index >= groups.length - 1) return groups;
  final a = supersetRun(groups, index) ?? (start: index, end: index + 1);
  final b =
      supersetRun(groups, index + 1) ?? (start: index + 1, end: index + 2);
  if (a.end > index + 1) return groups;
  final id = groups.whereType<int>().fold(0, math.max) + 1;
  return [
    for (var i = 0; i < groups.length; i++)
      i >= a.start && i < b.end ? id : groups[i],
  ];
}

/// Moves the item at [from] to [target] (its index once it is taken out) and
/// keeps supersets together: inside its own superset the item just changes
/// place, anywhere else its whole superset moves with it, and nothing lands
/// in the middle of another superset.
List<T> moveGrouped<T>(
  List<T> list,
  int from,
  int target,
  int? Function(T) groupOf,
) {
  final run = supersetRun([for (final x in list) groupOf(x)], from);
  final item = list[from];
  final rest = [...list]..removeAt(from);
  final to = target.clamp(0, rest.length);
  if (run != null && to >= run.start && to <= run.end - 1) {
    return rest..insert(to, item);
  }
  final moving = run == null ? [item] : list.sublist(run.start, run.end);
  final others = run == null
      ? rest
      : [...list.sublist(0, run.start), ...list.sublist(run.end)];
  var t = run == null || to < run.start ? to : to - (moving.length - 1);
  if (t > 0 && t < others.length) {
    final split = supersetRun([for (final x in others) groupOf(x)], t);
    if (split != null && split.start < t) {
      t = to >= from ? split.end : split.start;
    }
  }
  return others..insertAll(t, moving);
}
