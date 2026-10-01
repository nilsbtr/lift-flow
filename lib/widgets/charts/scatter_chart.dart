import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/units.dart';
import 'axis_chart.dart';
import 'chart_style.dart';
import 'scale.dart';
import 'trend_chart.dart';

@immutable
class ScatterPoint {
  const ScatterPoint(this.date, this.value, this.reps);
  final DateTime date;

  /// In the display unit.
  final double value;
  final int reps;

  @override
  bool operator ==(Object other) =>
      other is ScatterPoint &&
      other.date == date &&
      other.value == value &&
      other.reps == reps;

  @override
  int get hashCode => Object.hash(date, value, reps);
}

/// Every set over time; bigger dots mean more reps.
class ScatterChart extends StatelessWidget {
  const ScatterChart({
    super.key,
    required this.points,
    required this.semanticLabel,
    this.yLabel = fmtCompact,
    this.tooltip,
    this.height = 176,
  });

  final List<ScatterPoint> points;
  final String semanticLabel;
  final String Function(double) yLabel;
  final String Function(int)? tooltip;
  final double height;

  @override
  Widget build(BuildContext context) {
    final xs = [for (final p in points) chartDay(p.date)];
    final ys = [for (final p in points) p.value];
    return AxisChart(
      xs: xs,
      ys: ys,
      y: NiceScale(
        ys.isEmpty ? 0 : ys.reduce(math.min),
        ys.isEmpty ? 1 : ys.reduce(math.max),
      ),
      layer: _ScatterLayer(points, xs),
      semanticLabel: semanticLabel,
      xLabels: points.isEmpty
          ? const []
          : dateLabels(
              points.map((p) => p.date).reduce((a, b) => a.isBefore(b) ? a : b),
              points.map((p) => p.date).reduce((a, b) => a.isAfter(b) ? a : b),
            ),
      yLabel: yLabel,
      tooltip: tooltip,
      scrub: ScrubMode.nearest,
      height: height,
    );
  }
}

class _ScatterLayer extends ChartLayer {
  const _ScatterLayer(this.points, this.xs);

  final List<ScatterPoint> points;
  final List<double> xs;

  static const _minR = 2.5;
  static const _maxR = 6.0;

  @override
  void paint(
    Canvas canvas,
    ChartGeometry g,
    ChartStyle style,
    double t,
    int? selected,
  ) {
    if (points.isEmpty) return;
    final reps = points.map((p) => p.reps);
    final lo = reps.reduce(math.min);
    final span = reps.reduce(math.max) - lo;
    double radius(int r) =>
        span == 0 ? (_minR + _maxR) / 2 : _minR + (_maxR - _minR) * (r - lo) / span;
    final fill = Paint()..color = style.line.withValues(alpha: 0.45 * t);
    for (var i = 0; i < points.length; i++) {
      if (i == selected) continue;
      canvas.drawCircle(
        g.at(xs[i], points[i].value),
        radius(points[i].reps) * t,
        fill,
      );
    }
    if (selected != null && selected < points.length) {
      final c = g.at(xs[selected], points[selected].value);
      final r = radius(points[selected].reps);
      canvas
        ..drawCircle(c, r + 2, Paint()..color = style.surface)
        ..drawCircle(c, r, Paint()..color = style.line);
    }
  }

  @override
  bool shouldRepaint(_ScatterLayer old) => !listEquals(old.points, points);
}
