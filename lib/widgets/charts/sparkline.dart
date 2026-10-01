import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'chart_style.dart';

/// Tiny trend line without axes; the last point is marked. Describe it in the
/// surrounding row's semantics.
class Sparkline extends StatelessWidget {
  const Sparkline(
    this.values, {
    super.key,
    this.color,
    this.width = 72,
    this.height = 28,
  });

  final List<double> values;

  /// Line color; defaults to the chart line color.
  final Color? color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = ChartStyle.of(context);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(width, height),
          painter: _SparkPainter(values, color ?? style.line, style.surface),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.surface);

  final List<double> values;
  final Color color;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const pad = 3.0;
    final lo = values.reduce(math.min);
    final span = values.reduce(math.max) - lo;
    final n = values.length;
    Offset at(int i) => Offset(
      n == 1 ? size.width - pad : pad + (size.width - pad * 2) * i / (n - 1),
      span == 0
          ? size.height / 2
          : size.height - pad - (size.height - pad * 2) * (values[i] - lo) / span,
    );
    final pts = [for (var i = 0; i < n; i++) at(i)];
    if (n > 1) {
      canvas.drawPath(
        Path()..addPolygon(pts, false),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }
    canvas
      ..drawCircle(pts.last, 3.5, Paint()..color = surface)
      ..drawCircle(pts.last, 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.color != color ||
      old.surface != surface ||
      !listEquals(old.values, values);
}
