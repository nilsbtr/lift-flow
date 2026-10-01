import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/units.dart';
import 'axis_chart.dart';
import 'chart_style.dart';
import 'scale.dart';

/// One pill bar per week with a dashed average and an optional goal line.
class WeekBarChart extends StatelessWidget {
  const WeekBarChart({
    super.key,
    required this.weeks,
    required this.values,
    required this.semanticLabel,
    this.goal,
    this.yLabel = fmtCompact,
    this.tooltip,
    this.height = 176,
    this.animateKey,
  });

  /// Week starts, oldest first; the last is the current week.
  final List<DateTime> weeks;
  final List<double> values;
  final String semanticLabel;
  final double? goal;
  final String Function(double) yLabel;
  final String Function(int)? tooltip;
  final double height;
  final Object? animateKey;

  @override
  Widget build(BuildContext context) {
    final n = values.length;
    // The unfinished current week would drag the average down.
    final done = n > 1 ? values.sublist(0, n - 1) : values;
    final active = done.where((v) => v > 0);
    final average = active.isEmpty ? null : active.average;
    final top = [...values, ?goal].fold(0.0, math.max);
    final fmt = DateFormat('d MMM');
    return AxisChart(
      xs: [for (var i = 0; i < n; i++) i.toDouble()],
      ys: values,
      y: NiceScale(0, top, zero: true, ticks: 3),
      xMin: -0.5,
      xMax: n - 0.5,
      layer: _BarLayer(values, average: average, goal: goal),
      semanticLabel: semanticLabel,
      xLabels: [
        for (var i = n - 1; i >= 0; i -= 4) (i.toDouble(), fmt.format(weeks[i])),
      ],
      yLabel: yLabel,
      tooltip: tooltip,
      height: height,
      animateKey: animateKey,
    );
  }
}

class _BarLayer extends ChartLayer {
  const _BarLayer(this.values, {this.average, this.goal});

  final List<double> values;
  final double? average;
  final double? goal;

  @override
  void paint(
    Canvas canvas,
    ChartGeometry g,
    ChartStyle style,
    double t,
    int? selected,
  ) {
    final n = values.length;
    if (n == 0) return;
    final p = g.plot;
    final width = math.min(p.width / n * 0.56, 20.0);
    for (var i = 0; i < n; i++) {
      final x = g.dx(i.toDouble());
      final h = (p.bottom - g.dy(values[i])) * t;
      final color = values[i] <= 0
          ? style.empty
          : selected == null || selected == i
          ? style.line
          : style.line.withValues(alpha: 0.4);
      // Empty weeks keep a stub so the rhythm stays visible.
      final rect = Rect.fromLTRB(
        x - width / 2,
        p.bottom - math.max(h, width / 2),
        x + width / 2,
        p.bottom,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(width / 2)),
        Paint()..color = color,
      );
    }
    if (average case final avg?) {
      _dashed(canvas, p, g.dy(avg), style.muted);
    }
    if (goal case final goal?) {
      final y = g.dy(goal);
      canvas.drawLine(
        Offset(p.left, y),
        Offset(p.right, y),
        Paint()
          ..color = style.goal
          ..strokeWidth = 1.5,
      );
    }
  }

  static void _dashed(Canvas canvas, Rect p, double y, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    for (var x = p.left; x < p.right; x += 8) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, p.right), y), paint);
    }
  }

  @override
  bool shouldRepaint(_BarLayer old) =>
      old.average != average ||
      old.goal != goal ||
      !listEquals(old.values, values);
}
