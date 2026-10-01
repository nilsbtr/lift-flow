import 'dart:math' as math;

/// Axis range with round tick steps of 1, 2, 2.5 or 5 × 10ⁿ.
class NiceScale {
  const NiceScale._(this.min, this.max, this.step);

  /// Covers [lo]–[hi] with about [ticks] intervals. [zero] keeps 0 in range.
  factory NiceScale(double lo, double hi, {int ticks = 4, bool zero = false}) {
    if (lo > hi) (lo, hi) = (hi, lo);
    if (zero) {
      lo = math.min(lo, 0);
      hi = math.max(hi, 0);
    }
    if (hi - lo < 1e-9) {
      final pad = lo == 0 ? 1.0 : lo.abs() * 0.1;
      if (zero && lo >= 0) {
        hi += pad * 2;
      } else {
        lo -= pad;
        hi += pad;
      }
    }
    final raw = (hi - lo) / ticks;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / mag;
    final nice = f <= 1
        ? 1.0
        : f <= 2
        ? 2.0
        : f <= 2.5
        ? 2.5
        : f <= 5
        ? 5.0
        : 10.0;
    final step = nice * mag;
    return NiceScale._(
      (lo / step + 1e-9).floorToDouble() * step,
      (hi / step - 1e-9).ceilToDouble() * step,
      step,
    );
  }

  final double min;
  final double max;
  final double step;

  List<double> get ticks {
    final n = ((max - min) / step).round();
    // Rounding keeps labels like 0.30000000000000004 out.
    return [for (var i = 0; i <= n; i++) _round(min + i * step)];
  }

  /// 0 at [min], 1 at [max].
  double norm(double v) => (v - min) / (max - min);

  static double _round(double v) => (v * 1e6).roundToDouble() / 1e6;
}
