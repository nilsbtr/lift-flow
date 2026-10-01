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

/// "80 × 8", "BW × 12", "+10 × 8", "−20 × 8".
String fmtSet({
  required TrackingType type,
  required LoadMode mode,
  required double? loadKg,
  required int? reps,
  required WeightUnit unit,
}) {
  final load = fmtLoad(type: type, mode: mode, loadKg: loadKg, unit: unit);
  return '$load $kTimes ${reps ?? '–'}';
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

String fmtRepsRange(int? min, int? max) {
  if (min == null) return '';
  if (max == null || max == min) return '$min';
  return '$min-$max';
}
