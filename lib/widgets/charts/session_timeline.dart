import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/stats.dart';
import 'chart_style.dart';

/// When each set was completed, one row per exercise.
class SessionTimeline extends StatelessWidget {
  const SessionTimeline({
    super.key,
    required this.marks,
    required this.start,
    required this.end,
    required this.lanes,
    required this.semanticLabel,
  });

  final List<TimelineMark> marks;
  final DateTime start;
  final DateTime end;
  final int lanes;
  final String semanticLabel;

  static const _row = 12.0;

  @override
  Widget build(BuildContext context) {
    final style = ChartStyle.of(context);
    return ChartSemantics(
      label: semanticLabel,
      child: CustomPaint(
        size: Size(double.infinity, math.max(1, lanes) * _row),
        painter: _TimelinePainter(this, style),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.chart, this.style);

  final SessionTimeline chart;
  final ChartStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 4.0;
    final total = chart.end.difference(chart.start).inSeconds;
    final track = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    for (var lane = 0; lane < chart.lanes; lane++) {
      final y = (lane + 0.5) * SessionTimeline._row;
      canvas.drawLine(Offset(r, y), Offset(size.width - r, y), track);
    }
    if (total <= 0) return;
    for (final m in chart.marks) {
      final f = m.at.difference(chart.start).inSeconds / total;
      canvas.drawCircle(
        Offset(r + (size.width - r * 2) * f, (m.lane + 0.5) * SessionTimeline._row),
        r,
        Paint()..color = m.warmup ? style.muted : style.line,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.style != style ||
      old.chart.start != chart.start ||
      old.chart.end != chart.end ||
      old.chart.lanes != chart.lanes ||
      !const ListEquality<TimelineMark>().equals(old.chart.marks, chart.marks);
}
