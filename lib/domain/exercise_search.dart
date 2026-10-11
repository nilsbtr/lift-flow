import 'dart:math' as math;

import '../data/database.dart';

/// How often and how recently an exercise was logged in finished workouts.
class ExerciseUsage {
  const ExerciseUsage(this.count, this.lastUsed);
  final int count;
  final DateTime lastUsed;

  /// Sessions weighted by age; halves every 30 days.
  double score(DateTime now) =>
      count *
      math.pow(0.5, now.difference(lastUsed).inHours / 24 / 30).toDouble();
}

/// Exercises shown ahead of the A–Z list when there is no search.
const kRecentExercises = 8;

typedef RankedExercises = ({List<Exercise> exercises, int recent});

// Query words that stand for other words. Every group must match.
const _abbreviations = <String, List<List<String>>>{
  'db': [
    ['dumbbell'],
  ],
  'dbs': [
    ['dumbbell'],
  ],
  'bb': [
    ['barbell'],
  ],
  'kb': [
    ['kettlebell'],
  ],
  'bw': [
    ['bodyweight', 'bw'],
  ],
  'ohp': [
    ['overhead', 'military', 'shoulder'],
    ['press'],
  ],
  'rdl': [
    ['romanian', 'rdl'],
    ['deadlift', 'rdl'],
  ],
  'sldl': [
    ['stiff', 'sldl'],
    ['deadlift', 'sldl'],
  ],
  'dl': [
    ['deadlift', 'dl'],
  ],
  'bp': [
    ['bench'],
    ['press'],
  ],
  'cgbp': [
    ['close'],
    ['bench'],
    ['press'],
  ],
};

List<String> _tokens(String s) => [
  for (final t in s.toLowerCase().split(RegExp('[^a-z0-9]+')))
    if (t.isNotEmpty) _singular(t),
];

String _singular(String t) =>
    t.length > 3 && t.endsWith('s') && !t.endsWith('ss')
    ? t.substring(0, t.length - 1)
    : t;

/// Match quality of [query] against [e], or null when it doesn't match. The
/// query is split into words that may come in any order and match the start of
/// a word in the name, equipment or muscle group. Common abbreviations such as
/// "db" or "ohp" are expanded. Name matches score higher than the rest.
double? matchScore(Exercise e, String query) {
  final words = _tokens(query);
  if (words.isEmpty) return 0;
  final name = _tokens(e.name);
  final other = [
    ..._tokens(e.equipment.label),
    if (e.trackingType == TrackingType.bodyweight) 'bodyweight',
    ..._tokens(e.muscleGroup.label),
    for (final g in e.secondaryMuscles) ..._tokens(g.label),
  ];
  var score = 0.0;
  for (final w in words) {
    for (final group
        in _abbreviations[w] ??
            [
              [w],
            ]) {
      var best = 0.0;
      for (final alt in group) {
        for (final n in name) {
          if (n == alt) {
            best = math.max(best, 3);
          } else if (n.startsWith(alt)) {
            best = math.max(best, 2);
          }
        }
        for (final o in other) {
          if (o.startsWith(alt)) best = math.max(best, 1);
        }
      }
      if (best == 0) return null;
      score += best;
    }
  }
  if (_tokens(e.name).join(' ').startsWith(words.join(' '))) score += 1;
  return score;
}

/// Orders [all] for the picker. [group] limits the list to one primary muscle
/// group. With a [query], matches come best first, then by [usage]. Without
/// one, the most used and most recent exercises lead, followed by A–Z.
/// `recent` counts the leading exercises of that first block.
RankedExercises rankExercises(
  List<Exercise> all, {
  String query = '',
  MuscleGroup? group,
  Map<int, ExerciseUsage> usage = const {},
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  double used(Exercise e) => usage[e.id]?.score(t) ?? 0;
  int byName(Exercise a, Exercise b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  final pool = [
    for (final e in all)
      if (group == null || e.muscleGroup == group) e,
  ];

  if (_tokens(query).isNotEmpty) {
    final scored = <(Exercise, double)>[
      for (final e in pool)
        if (matchScore(e, query) case final s?) (e, s),
    ];
    scored.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      if (c != 0) return c;
      final u = used(b.$1).compareTo(used(a.$1));
      return u != 0 ? u : byName(a.$1, b.$1);
    });
    return (exercises: [for (final s in scored) s.$1], recent: 0);
  }

  final top =
      [
        for (final e in pool)
          if (usage.containsKey(e.id)) e,
      ]..sort((a, b) {
        final u = used(b).compareTo(used(a));
        return u != 0 ? u : byName(a, b);
      });
  final lead = top.take(kRecentExercises).toList();
  final rest = [
    for (final e in pool)
      if (!lead.contains(e)) e,
  ]..sort(byName);
  return (exercises: [...lead, ...rest], recent: lead.length);
}
