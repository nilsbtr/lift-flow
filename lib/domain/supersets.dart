import 'dart:math' as math;

/// Supersets are runs of neighbouring exercises that share a group value.
/// A value on a single exercise, or shared by exercises that are apart, does
/// not link anything.

/// Every superset as `[start, end)`, in list order.
List<(int, int)> supersetRuns(List<int?> groups) {
  final runs = <(int, int)>[];
  for (var i = 0; i < groups.length;) {
    final run = supersetRun(groups, i);
    if (run == null) {
      i++;
    } else {
      runs.add((run.start, run.end));
      i = run.end;
    }
  }
  return runs;
}

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

/// Drops lone groups, splits groups that are apart and numbers the rest
/// 1, 2, … in list order.
List<int?> normalizeGroups(List<int?> groups) {
  final out = List<int?>.filled(groups.length, null);
  var next = 1;
  for (final (s, e) in supersetRuns(groups)) {
    for (var i = s; i < e; i++) {
      out[i] = next;
    }
    next++;
  }
  return out;
}

/// Whether the exercise at [index] and the one after it are in one superset.
bool isLinkedWithNext(List<int?> groups, int index) =>
    index >= 0 &&
    index + 1 < groups.length &&
    groups[index] != null &&
    groups[index] == groups[index + 1];

/// Links the exercise at [index] with the next one, or splits them apart if
/// already linked, and normalizes the result.
List<int?> toggleLinkWithNext(List<int?> groups, int index) {
  if (index < 0 || index + 1 >= groups.length) return normalizeGroups(groups);
  if (!isLinkedWithNext(groups, index)) {
    return normalizeGroups(linkGroups(groups, index));
  }
  final g = [...groups];
  final fresh = g.whereType<int>().fold(0, math.max) + 1;
  for (var j = index + 1; j < g.length && g[j] == groups[index]; j++) {
    g[j] = fresh;
  }
  return normalizeGroups(g);
}

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
/// in the middle of another superset. A superset dropped there snaps to its
/// edge in the direction of the move, or to the nearer edge with [nearest].
List<T> moveGrouped<T>(
  List<T> list,
  int from,
  int target,
  int? Function(T) groupOf, {
  bool nearest = false,
}) {
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
      t = (nearest ? t - split.start <= split.end - t : to < from)
          ? split.start
          : split.end;
    }
  }
  return others..insertAll(t, moving);
}
