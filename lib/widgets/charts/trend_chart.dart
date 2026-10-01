import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/units.dart';
import 'axis_chart.dart';
import 'chart_style.dart';
import 'scale.dart';

@immutable
class TrendPoint {
  const TrendPoint(this.date, this.value, {double? best, this.isRecord = false})
    : best = best ?? value;

  final DateTime date;

  /// In the display unit.
  final double value;

  /// Running best up to this point.
  final double best;
  final bool isRecord;

  @override
  bool operator ==(Object other) =>
      other is TrendPoint &&
      other.date == date &&
      other.value == value &&
      other.best == best &&
      other.isRecord == isRecord;

  @override
  int get hashCode => Object.hash(date, value, best, isRecord);
}

/// Days since epoch, the x unit of date charts.
double chartDay(DateTime d) => d.millisecondsSinceEpoch / Duration.millisecondsPerDay;

/// Up to three date labels spread over [first]–[last].
List<(double, String)> dateLabels(DateTime first, DateTime last) {
  final a = chartDay(first);
  final b = chartDay(last);
  final fmt = b - a > 400 ? DateFormat('MMM yy') : DateFormat('d MMM');
  if (b - a < 1) return [(a, fmt.format(first))];
  return [
    for (final f in const [0.0, 0.5, 1.0])
      (
        a + (b - a) * f,
        fmt.format(
          DateTime.fromMillisecondsSinceEpoch(
            ((a + (b - a) * f) * Duration.millisecondsPerDay).round(),
          ),
        ),
      ),
  ];
}

/// Line over time with a gradient area and, optionally, a staircase of the
/// running best with record dots.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.semanticLabel,
    this.showRecords = true,
    this.yLabel = fmtCompact,
    this.tooltip,
    this.onSelect,
    this.height = 176,
    this.animateKey,
  });

  final List<TrendPoint> points;
  final String semanticLabel;
  final bool showRecords;
  final String Function(double) yLabel;
  final String Function(int)? tooltip;
  final ValueChanged<int?>? onSelect;
  final double height;
  final Object? animateKey;

  /// Beyond this many points only records get a dot.
  static const maxDots = 40;

  @override
  Widget build(BuildContext context) {
    final xs = [for (final p in points) chartDay(p.date)];
    final ys = [for (final p in points) p.value];
    final lo = ys.isEmpty ? 0.0 : ys.reduce(math.min);
    final hi = ys.isEmpty ? 1.0 : ys.reduce(math.max);
    return AxisChart(
      xs: xs,
      ys: ys,
      y: NiceScale(lo, hi),
      layer: _TrendLayer(points, xs, showRecords: showRecords),
      semanticLabel: semanticLabel,
      xLabels: points.isEmpty
          ? const []
          : dateLabels(points.first.date, points.last.date),
      yLabel: yLabel,
      tooltip: tooltip,
      onSelect: onSelect,
      height: height,
      animateKey: animateKey,
    );
  }
}

class _TrendLayer extends ChartLayer {
  const _TrendLayer(this.points, this.xs, {required this.showRecords});

  final List<TrendPoint> points;
  final List<double> xs;
  final bool showRecords;

  @override
  void paint(
    Canvas canvas,
    ChartGeometry g,
    ChartStyle style,
    double t,
    int? selected,
  ) {
    if (points.isEmpty) return;
    final pts = [
      for (var i = 0; i < points.length; i++) g.at(xs[i], points[i].value),
    ];
    final p = g.plot;
    // Everything left of this edge is drawn in.
    final edge = p.left + (p.width + 1) * t;

    if (pts.length > 1) {
      final line = Path()..addPolygon(pts, false);
      final area = Path.from(line)
        ..lineTo(pts.last.dx, p.bottom)
        ..lineTo(pts.first.dx, p.bottom)
        ..close();
      canvas
        ..save()
        ..clipRect(Rect.fromLTRB(0, 0, edge, p.bottom))
        ..drawPath(
          area,
          Paint()
            ..shader = ui.Gradient.linear(p.topCenter, p.bottomCenter, [
              style.line.withValues(alpha: 0.22),
              style.line.withValues(alpha: 0),
            ]),
        )
        ..restore();

      if (showRecords) {
        final stairs = Path()..moveTo(pts.first.dx, g.dy(points.first.best));
        for (var i = 1; i < pts.length; i++) {
          stairs
            ..lineTo(pts[i].dx, g.dy(points[i - 1].best))
            ..lineTo(pts[i].dx, g.dy(points[i].best));
        }
        canvas
          ..save()
          ..clipRect(Rect.fromLTRB(0, 0, edge, p.bottom + 1))
          ..drawPath(
            stairs,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = style.record.withValues(alpha: 0.5),
          )
          ..restore();
      }

      final metric = line.computeMetrics().firstOrNull;
      if (metric != null) {
        canvas.drawPath(
          metric.extractPath(0, metric.length * t),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = style.line,
        );
      }
    }

    final all = points.length <= TrendChart.maxDots;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < pts.length; i++) {
      final record = showRecords && points[i].isRecord;
      if (pts[i].dx > edge || !(all || record || pts.length == 1)) continue;
      final color = record ? style.record : style.line;
      canvas
        ..drawCircle(pts[i], record ? 4.5 : 3.5, Paint()..color = style.surface)
        ..drawCircle(pts[i], record ? 3.5 : 2.5, Paint()..color = color);
    }
    if (selected != null && selected < pts.length) {
      final color = showRecords && points[selected].isRecord
          ? style.record
          : style.line;
      canvas
        ..drawCircle(pts[selected], 7, Paint()..color = style.surface)
        ..drawCircle(pts[selected], 6, ring..color = color)
        ..drawCircle(pts[selected], 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_TrendLayer old) =>
      old.showRecords != showRecords || !listEquals(old.points, points);
}
