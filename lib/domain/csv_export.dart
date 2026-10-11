import 'dart:convert';
import 'dart:typed_data';

import '../data/database.dart';
import 'units.dart';

/// Everything [setsCsv] needs, plain data so it can cross to an isolate.
typedef CsvSource = ({
  List<Workout> workouts,
  List<Exercise> exercises,
  List<WorkoutExercise> workoutExercises,
  List<WorkoutSet> sets,
});

/// Weight comes twice: always in kg, and in the user's [unit] with its name.
/// RPE is RPE whatever the effort setting is. Duration and distance are empty
/// until timed and distance exercises exist.
const kCsvHeader = [
  'date',
  'start',
  'workout',
  'exercise',
  'muscle_group',
  'equipment',
  'set',
  'set_type',
  'weight_kg',
  'weight',
  'unit',
  'reps',
  'rpe',
  'duration_s',
  'distance_m',
  'set_note',
  'exercise_note',
  'workout_note',
];

/// Quotes a field when it holds a comma, quote or line break (RFC 4180).
String csvField(String? v) {
  if (v == null || v.isEmpty) return '';
  return v.contains(RegExp(r'[",\r\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
}

/// One row per completed set of finished workouts, oldest workout first, then
/// exercise and set order. Records end with CRLF.
String setsCsv(CsvSource src, WeightUnit unit) {
  final exercises = {for (final e in src.exercises) e.id: e};
  final byWorkout = <int, List<WorkoutExercise>>{};
  for (final we in src.workoutExercises) {
    (byWorkout[we.workoutId] ??= []).add(we);
  }
  final byExercise = <int, List<WorkoutSet>>{};
  for (final s in src.sets) {
    if (s.isCompleted) (byExercise[s.workoutExerciseId] ??= []).add(s);
  }
  final workouts = [
    for (final w in src.workouts)
      if (w.endedAt != null) w,
  ]..sort((a, b) => _then(a.startedAt.compareTo(b.startedAt), a.id - b.id));

  final out = StringBuffer()..write(_record(kCsvHeader));
  for (final w in workouts) {
    final wes = (byWorkout[w.id] ?? [])
      ..sort((a, b) => _then(a.position - b.position, a.id - b.id));
    for (final we in wes) {
      final e = exercises[we.exerciseId];
      final sets = (byExercise[we.id] ?? [])
        ..sort((a, b) => _then(a.position - b.position, a.id - b.id));
      if (e == null) continue;
      for (var i = 0; i < sets.length; i++) {
        final s = sets[i];
        out.write(
          _record([
            _day(w.startedAt),
            _time(w.startedAt),
            w.name,
            e.name,
            e.muscleGroup.label,
            e.equipment == Equipment.none ? '' : e.equipment.label,
            '${i + 1}',
            s.setType.label,
            s.loadKg == null ? '' : fmtNum(s.loadKg!),
            s.loadKg == null ? '' : fmtWeight(s.loadKg!, unit),
            unit.label,
            s.reps?.toString() ?? '',
            s.rpe == null ? '' : fmtNum(s.rpe!),
            s.durationSeconds?.toString() ?? '',
            s.distanceM == null ? '' : fmtNum(s.distanceM!),
            s.note ?? '',
            we.note ?? '',
            w.note ?? '',
          ]),
        );
      }
    }
  }
  return out.toString();
}

Uint8List encodeSetsCsv(CsvSource src, WeightUnit unit) =>
    Uint8List.fromList(utf8.encode(setsCsv(src, unit)));

int _then(int first, int second) => first != 0 ? first : second;

String _record(List<String> fields) => '${fields.map(csvField).join(',')}\r\n';

String _two(int n) => n.toString().padLeft(2, '0');

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${_two(d.month)}-${_two(d.day)}';

String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
