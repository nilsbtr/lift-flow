import 'package:intl/intl.dart';

import '../data/enums.dart';

const double kgPerLb = 0.45359237;

double kgToUnit(double kg, WeightUnit unit) =>
    unit == WeightUnit.kg ? kg : kg / kgPerLb;

double unitToKg(double value, WeightUnit unit) =>
    unit == WeightUnit.kg ? value : value * kgPerLb;

/// Formats a number with up to 2 decimals, trimming trailing zeros.
String fmtNum(double v) {
  final rounded = (v * 100).roundToDouble() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  var s = rounded.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Formats a kg value in the display unit without unit suffix.
String fmtWeight(double kg, WeightUnit unit) => fmtNum(kgToUnit(kg, unit));

/// Parses user input ("82.5" or "82,5") into a display-unit number.
double? parseNumber(String input) {
  final t = input.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

final NumberFormat _grouped = NumberFormat.decimalPattern('en_US');

String fmtVolume(double kg, WeightUnit unit) =>
    '${_grouped.format(kgToUnit(kg, unit).round())} ${unit.label}';

const String kMinus = '\u2212';
const String kTimes = '\u00d7';

final NumberFormat _compact = NumberFormat.compact(locale: 'en_US');

/// Short axis label, e.g. "950", "1.2K", "12K".
String fmtCompact(double v) =>
    v.abs() < 1000 ? fmtNum(v) : _compact.format(v).replaceFirst('-', kMinus);

/// Signed change, e.g. "+2.5", "−5", "±0". [fmt] formats the magnitude.
String fmtDelta(double d, [String Function(double) fmt = fmtNum]) {
  final s = fmt(d.abs());
  if (s == fmt(0)) return '±$s';
  return d > 0 ? '+$s' : '$kMinus$s';
}

/// Short "load" label for a set, e.g. "80", "BW", "+10", "−20".
String fmtLoad({
  required TrackingType type,
  required LoadMode mode,
  required double? loadKg,
  required WeightUnit unit,
}) {
  if (type == TrackingType.weights) {
    return loadKg == null ? '–' : fmtWeight(loadKg, unit);
  }
  if (loadKg == null || loadKg == 0 || mode == LoadMode.none) return 'BW';
  if (loadKg > 0) return '+${fmtWeight(loadKg, unit)}';
  return '$kMinus${fmtWeight(-loadKg, unit)}';
}

/// "80 × 8", "BW × 12", "+10 × 8", "−20 × 8". Time and distance sets read
/// "1:30", "20 × 1:30", "5 km in 27:30" or "40 × 30 m".
///
/// A set is shown by what it holds, so sets logged before an exercise changed
/// its type stay readable.
String fmtSet({
  required TrackingType type,
  required LoadMode mode,
  required double? loadKg,
  required int? reps,
  int? durationSeconds,
  double? distanceM,
  required WeightUnit unit,
}) {
  final timed = durationSeconds != null || distanceM != null;
  if (reps == null ? timed || !type.hasReps : timed && !type.hasReps) {
    final du = DistanceUnit.of(unit, mode);
    final value = [
      if (distanceM != null) '${fmtDistance(distanceM, du)} ${du.label}',
      if (durationSeconds != null) fmtHms(durationSeconds),
    ].join(' in ');
    final text = value.isEmpty ? '–' : value;
    return loadKg != null && loadKg > 0
        ? '${fmtWeight(loadKg, unit)} $kTimes $text'
        : text;
  }
  if (!type.hasReps) {
    return loadKg == null
        ? '$reps reps'
        : '${fmtWeight(loadKg, unit)} $kTimes $reps';
  }
  final load = fmtLoad(type: type, mode: mode, loadKg: loadKg, unit: unit);
  return '$load $kTimes ${reps ?? '–'}';
}

/// Effort as entered in [mode]: the RPE, or RIR (10 − RPE). Empty when unset.
String fmtEffort(double? rpe, EffortMode mode) =>
    rpe == null ? '' : fmtNum(mode == EffortMode.rir ? 10 - rpe : rpe);

/// "RPE 8.5" or "1.5 RIR".
String fmtEffortLabel(double rpe, EffortMode mode) => mode == EffortMode.rir
    ? '${fmtEffort(rpe, mode)} RIR'
    : 'RPE ${fmtEffort(rpe, mode)}';

/// Parses effort entered in [mode] into an RPE of 1–10 in 0.5 steps.
/// Returns null if empty or out of range.
double? parseEffort(String input, EffortMode mode) {
  final v = parseNumber(input);
  if (v == null) return null;
  final rpe = ((mode == EffortMode.rir ? 10 - v : v) * 2).round() / 2;
  return rpe < 1 || rpe > 10 ? null : rpe;
}

String fmtDuration(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final rm = m % 60;
  return rm == 0 ? '$h h' : '$h h $rm min';
}

String fmtClock(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

/// Longest time of a set in seconds, as backups accept it.
const int kMaxSetSeconds = 86400;

/// Longest distance of a set in metres, as backups accept it.
const double kMaxSetMetres = 1000000;

/// The time of a set: "0:45", "12:05", and "1:02:03" from an hour on.
String fmtHms(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  if (s < 3600) return fmtClock(s);
  return '${s ~/ 3600}:${fmtClock(s % 3600).padLeft(5, '0')}';
}

/// Parses "45" (seconds), "1:30" or "1:02:03" into seconds. Parts may run
/// over ("90" and "0:90" are 1:30). Returns null if empty, zero, malformed
/// or longer than [kMaxSetSeconds].
int? parseHms(String input) {
  final parts = input.trim().split(':');
  if (parts.length > 3) return null;
  var total = 0;
  for (final p in parts) {
    if (p.isEmpty || p.length > 5 || p.contains(RegExp(r'\D'))) return null;
    total = total * 60 + int.parse(p);
  }
  return total <= 0 || total > kMaxSetSeconds ? null : total;
}

/// Puts the colons into a time typed as digits only: "130" becomes "1:30"
/// and "10203" "1:02:03". One or two digits stay seconds.
String hmsInput(String text) {
  var d = text.replaceAll(RegExp(r'\D'), '');
  if (d.length > 6) d = d.substring(0, 6);
  if (d.length <= 2) return d;
  final tail = d.substring(d.length - 2);
  final head = d.substring(0, d.length - 2);
  if (head.length <= 2) return '$head:$tail';
  return '${head.substring(0, head.length - 2)}:'
      '${head.substring(head.length - 2)}:$tail';
}

/// Distances are stored in metres and shown in one of these.
enum DistanceUnit {
  m('m', 1, 100, '/100 m'),
  km('km', 1000, 1000, '/km'),
  yd('yd', 0.9144, 91.44, '/100 yd'),
  mi('mi', 1609.344, 1609.344, '/mi');

  const DistanceUnit(this.label, this.metres, this.paceMetres, this.paceLabel);
  final String label;

  /// Metres in one unit.
  final double metres;

  /// The distance a pace is given over, in metres.
  final double paceMetres;
  final String paceLabel;

  bool get isImperial => this == yd || this == mi;

  /// "km/h" or "mph".
  String get speedLabel => isImperial ? 'mph' : 'km/h';

  /// The unit an exercise is logged and shown in. There is no distance
  /// setting: kg means metric and lb imperial. Loaded exercises (carries, sled
  /// pushes) are short and use m or yd, the others (runs, rows) km or mi.
  static DistanceUnit of(WeightUnit unit, LoadMode mode) =>
      switch ((unit, mode == LoadMode.none)) {
        (WeightUnit.kg, true) => km,
        (WeightUnit.kg, false) => m,
        (WeightUnit.lb, true) => mi,
        (WeightUnit.lb, false) => yd,
      };
}

/// Formats metres in [unit] without the unit label.
String fmtDistance(double metres, DistanceUnit unit) =>
    fmtNum(metres / unit.metres);

/// Parses a distance entered in [unit] into metres. Returns null if empty,
/// not above zero or longer than [kMaxSetMetres].
double? parseDistance(String input, DistanceUnit unit) {
  final v = parseNumber(input);
  if (v == null || v <= 0) return null;
  final metres = v * unit.metres;
  return metres > kMaxSetMetres ? null : metres;
}

/// A speed in m/s as a pace: "5:30 /km", "8:51 /mi", "1:45 /100 m".
String fmtPace(double metresPerSecond, DistanceUnit unit) =>
    metresPerSecond <= 0
    ? '–'
    : '${fmtHms((unit.paceMetres / metresPerSecond).round())} '
          '${unit.paceLabel}';

/// A speed in m/s as km/h or mph, see [DistanceUnit.speedLabel].
double speedIn(double metresPerSecond, DistanceUnit unit) =>
    metresPerSecond *
    3600 /
    (unit.isImperial ? DistanceUnit.mi : DistanceUnit.km).metres;

/// Parses "8" or "8-12" into a reps range. Returns null if invalid.
/// An empty string parses to `(null, null)`.
({int? min, int? max})? parseRepsRange(String input) {
  final t = input.trim().replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return (min: null, max: null);
  final parts = t.split(RegExp(r'[-–]'));
  if (parts.length == 1) {
    final v = int.tryParse(parts[0]);
    if (v == null || v < 1 || v > 100) return null;
    return (min: v, max: null);
  }
  if (parts.length != 2) return null;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  if (a == null || b == null || a < 1 || b > 100 || a > b) return null;
  if (a == b) return (min: a, max: null);
  return (min: a, max: b);
}

/// Parses the separate min and max rep fields. Both empty means no target and
/// an empty max means exactly min. [error] explains why a pair can't be used.
({int? min, int? max, String? error}) parseRepsFields(String min, String max) {
  final a = min.trim();
  final b = max.trim();
  if (a.isEmpty && b.isEmpty) return (min: null, max: null, error: null);
  ({int? min, int? max, String? error}) bad(String error) =>
      (min: null, max: null, error: error);
  if (a.isEmpty) return bad('Enter the min reps first');
  final lo = int.tryParse(a);
  final hi = b.isEmpty ? lo : int.tryParse(b);
  if (lo == null || hi == null || lo < 1 || hi > 100) {
    return bad('Use 1–100 reps');
  }
  if (lo > hi) return bad('Max must be at least min');
  return (min: lo, max: lo == hi ? null : hi, error: null);
}

String fmtRepsRange(int? min, int? max) {
  if (min == null) return '';
  if (max == null || max == min) return '$min';
  return '$min-$max';
}
