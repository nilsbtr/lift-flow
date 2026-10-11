import 'dart:math' as math;

import '../data/enums.dart';
import 'units.dart';

const double _eps = 1e-6;

const _kgPlates = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25];
const _lbPlates = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5];
const _kgChoices = [
  25.0,
  20.0,
  15.0,
  10.0,
  5.0,
  2.5,
  2.0,
  1.25,
  1.0,
  0.5,
  0.25,
];
const _lbChoices = [55.0, 45.0, 35.0, 25.0, 15.0, 10.0, 5.0, 2.5, 1.25, 1.0];

List<double> _toKg(List<double> values, WeightUnit unit) => [
  for (final v in values) unitToKg(v, unit),
];

/// Bar used when none is set: 20 kg or 45 lb.
double defaultBarKg(WeightUnit unit) =>
    unitToKg(unit == WeightUnit.kg ? 20 : 45, unit);

/// The bar weight in kg: the stored one, or the default for [unit].
double barWeightKg(double? stored, WeightUnit unit) =>
    stored ?? defaultBarKg(unit);

/// Plates used when none are set, in kg, heaviest first.
List<double> defaultPlatesKg(WeightUnit unit) =>
    _toKg(unit == WeightUnit.kg ? _kgPlates : _lbPlates, unit);

/// Plate sizes a picker offers in [unit], in kg, heaviest first.
List<double> plateChoicesKg(WeightUnit unit) =>
    _toKg(unit == WeightUnit.kg ? _kgChoices : _lbChoices, unit);

/// Reads `AppSettings.plates` (comma-separated kg), heaviest first. Null is
/// the default set for [unit].
List<double> parsePlates(String? stored, WeightUnit unit) {
  if (stored == null) return defaultPlatesKg(unit);
  final plates = <double>{
    for (final p in stored.split(','))
      if (double.tryParse(p.trim()) case final v? when v > 0) v,
  }.toList()..sort((a, b) => b.compareTo(a));
  return plates;
}

String encodePlates(Iterable<double> platesKg) =>
    (platesKg.toSet().toList()..sort((a, b) => b.compareTo(a))).join(',');

class PlateLoad {
  const PlateLoad(this.perSide, this.remainderKg);

  /// Plates for one side in kg, heaviest first.
  final List<double> perSide;

  /// What the plates can't make up, both sides together. Negative when the
  /// weight is below the bar.
  final double remainderKg;
}

/// Plates per side for [totalKg] on a [barKg] bar, taking the heaviest of
/// [plates] first. Each size can be used any number of times.
PlateLoad platesFor(
  double totalKg, {
  required double barKg,
  required List<double> plates,
}) {
  var side = (totalKg - barKg) / 2;
  if (side < -_eps) return PlateLoad(const [], totalKg - barKg);
  final used = <double>[];
  for (final p in [...plates]..sort((a, b) => b.compareTo(a))) {
    if (p <= 0) continue;
    while (side >= p - _eps) {
      used.add(p);
      side -= p;
    }
  }
  return PlateLoad(used, side < _eps ? 0 : side * 2);
}

/// A bar and the plate sizes to load it with, in kg.
class BarSetup {
  const BarSetup(this.barKg, this.plates);

  /// From `AppSettings.barWeightKg` and `plates`, with the defaults of [unit].
  BarSetup.of(double? barKg, String? plates, WeightUnit unit)
    : barKg = barWeightKg(barKg, unit),
      plates = parsePlates(plates, unit);

  final double barKg;
  final List<double> plates;

  PlateLoad load(double totalKg) =>
      platesFor(totalKg, barKg: barKg, plates: plates);
}

/// "2 × 20 · 5 · 2.5" in [unit], with a note on what can't be loaded.
String fmtPlates(PlateLoad load, WeightUnit unit) {
  if (load.remainderKg < 0) return 'Lighter than the bar';
  final parts = <String>[];
  for (var i = 0; i < load.perSide.length;) {
    var n = 1;
    while (i + n < load.perSide.length &&
        load.perSide[i + n] == load.perSide[i]) {
      n++;
    }
    final w = fmtWeight(load.perSide[i], unit);
    parts.add(n == 1 ? w : '$n $kTimes $w');
    i += n;
  }
  if (parts.isEmpty) parts.add('Empty bar');
  if (load.remainderKg > 0) {
    parts.add('${fmtWeight(load.remainderKg, unit)} ${unit.label} left over');
  }
  return parts.join(' · ');
}

/// Smallest step a load on [equipment] can go up by, in kg: a pair of the
/// lightest of [plates] on a barbell, otherwise a usual step for [unit].
double loadStep(Equipment equipment, WeightUnit unit, List<double> plates) {
  final kg = unit == WeightUnit.kg;
  return switch (equipment) {
    Equipment.barbell when plates.isNotEmpty => 2 * plates.reduce(math.min),
    Equipment.kettlebell => unitToKg(kg ? 4 : 5, unit),
    _ => unitToKg(kg ? 2.5 : 5, unit),
  };
}

/// [kg] rounded to the nearest load that [step]s reach from [base] (the bar),
/// never below it.
double roundLoad(double kg, double step, {double base = 0}) {
  if (step <= 0) return math.max(kg, base);
  return base + math.max(0, ((kg - base) / step).round()) * step;
}

const _ramp = [(0.5, 5), (0.7, 3), (0.85, 2)];

/// Warm-up ramp to [workKg]: the empty bar when [barKg] is given, then 50 %,
/// 70 % and 85 %, rounded to [step]. Steps that round to the load before them
/// or reach the working weight are left out.
List<({double loadKg, int reps})> warmupSets(
  double workKg, {
  required double step,
  double? barKg,
}) {
  final out = <({double loadKg, int reps})>[];
  if (barKg != null && barKg < workKg - _eps) {
    out.add((loadKg: barKg, reps: 10));
  }
  for (final (share, reps) in _ramp) {
    final kg = roundLoad(workKg * share, step, base: barKg ?? 0);
    final last = out.isEmpty ? 0.0 : out.last.loadKg;
    if (kg > last + _eps && kg < workKg - _eps) {
      out.add((loadKg: kg, reps: reps));
    }
  }
  return out;
}
