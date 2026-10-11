// Superset groups of an ordered exercise list. Neighbors sharing a non-null
// value form a superset; the value itself only tells groups apart.

/// Runs of neighbors sharing a non-null group, as `[start, end)` pairs.
List<(int, int)> supersetRuns(List<int?> groups) {
  final runs = <(int, int)>[];
  var i = 0;
  while (i < groups.length) {
    final g = groups[i];
    var j = i + 1;
    if (g != null) {
      while (j < groups.length && groups[j] == g) {
        j++;
      }
      if (j - i > 1) runs.add((i, j));
    }
    i = j;
  }
  return runs;
}

/// Drops groups left with one member, splits groups that are not adjacent and
/// numbers the rest 1, 2, … in list order.
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

/// Whether item [i] and the one after it are in the same superset.
bool isLinkedWithNext(List<int?> groups, int i) =>
    i >= 0 &&
    i + 1 < groups.length &&
    groups[i] != null &&
    groups[i] == groups[i + 1];

/// Links item [i] with the next one, or splits them apart if already linked.
/// Linking merges the groups on both sides.
List<int?> toggleLinkWithNext(List<int?> groups, int i) {
  if (i < 0 || i + 1 >= groups.length) return normalizeGroups(groups);
  final g = [...groups];
  final fresh = g.fold<int>(0, (m, v) => v != null && v > m ? v : m) + 1;
  if (isLinkedWithNext(g, i)) {
    final old = g[i];
    for (var j = i + 1; j < g.length && g[j] == old; j++) {
      g[j] = fresh;
    }
  } else {
    final a = g[i];
    final b = g[i + 1];
    final id = a ?? b ?? fresh;
    for (var j = 0; j < g.length; j++) {
      if ((a != null && g[j] == a) || (b != null && g[j] == b)) g[j] = id;
    }
    g[i] = id;
    g[i + 1] = id;
  }
  return normalizeGroups(g);
}

/// The new order after dragging item [from] to index [to] (its index once
/// removed, as in `onReorderItem`), as `result[newIndex] = oldIndex`.
///
/// Supersets stay adjacent: a member dragged within its superset reorders it;
/// dragged anywhere else, the whole superset moves as a block. Nothing lands
/// inside another superset, but snaps to its nearer edge.
List<int> reorderGroupIndices(List<int?> groups, int from, int to) {
  final g = normalizeGroups(groups);
  final n = g.length;
  var s = from;
  var e = from + 1;
  for (final (rs, re) in supersetRuns(g)) {
    if (from >= rs && from < re) {
      s = rs;
      e = re;
    }
  }
  final all = [for (var i = 0; i < n; i++) i];
  if (e - s > 1 && to >= s && to < e) {
    return all..insert(to, all.removeAt(from));
  }
  final rest = [
    for (final i in all)
      if (i < s || i >= e) i,
  ];
  final others = [...all]..removeAt(from);
  var p = others.take(to).where((i) => i < s || i >= e).length;
  if (p > 0 && p < rest.length) {
    final before = g[rest[p - 1]];
    if (before != null && before == g[rest[p]]) {
      var rs = p - 1;
      while (rs > 0 && g[rest[rs - 1]] == before) {
        rs--;
      }
      var re = p;
      while (re < rest.length && g[rest[re]] == before) {
        re++;
      }
      p = p - rs <= re - p ? rs : re;
    }
  }
  return [...rest.take(p), for (var i = s; i < e; i++) i, ...rest.skip(p)];
}
