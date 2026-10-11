import 'dart:math' as math;

import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../domain/stats.dart';
import 'chart_style.dart';

/// GitHub-style grid of recent days, one column per week with [firstDay] on
/// top.
class DotCalendar extends StatelessWidget {
  const DotCalendar({
    super.key,
    required this.activity,
    required this.now,
    required this.semanticLabel,
    this.firstDay = DateTime.monday,
    this.onTapDay,
  });

  final DayActivity activity;
  final DateTime now;
  final String semanticLabel;

  /// [DateTime.monday] … [DateTime.sunday].
  final int firstDay;

  /// Called for training days only.
  final ValueChanged<DateTime>? onTapDay;

  static const _gap = 3.0;
  static const _target = 16.0;

  @override
  Widget build(BuildContext context) {
    final style = ChartStyle.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final labelH = scaler.scale(style.label.fontSize!) * style.label.height!;
    return ChartSemantics(
      label: semanticLabel,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final weeks = ((w + _gap) / (_target + _gap)).floor().clamp(4, 26);
          final cell = (w + _gap) / weeks - _gap;
          final layout = _Layout(
            first: addDays(weekStart(now, firstDay), -7 * (weeks - 1)),
            weeks: weeks,
            cell: cell,
            top: labelH + _gap * 2,
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onTapDay == null
                ? null
                : (d) {
                    final day = layout.dayAt(d.localPosition);
                    if (day != null && activity.level(day) > 0) onTapDay!(day);
                  },
            child: CustomPaint(
              size: Size(w, layout.top + 7 * (cell + _gap) - _gap),
              painter: _CalendarPainter(
                layout: layout,
                activity: activity,
                today: dayOf(now),
                style: style,
                scaler: scaler,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Layout {
  const _Layout({
    required this.first,
    required this.weeks,
    required this.cell,
    required this.top,
  });

  final DateTime first;
  final int weeks;
  final double cell;
  final double top;

  double get pitch => cell + DotCalendar._gap;

  Rect rect(int week, int weekday) => Rect.fromLTWH(
    week * pitch,
    top + weekday * pitch,
    cell,
    cell,
  );

  DateTime? dayAt(Offset p) {
    final col = (p.dx / pitch).floor();
    final row = ((p.dy - top) / pitch).floor();
    if (col < 0 || col >= weeks || row < 0 || row > 6) return null;
    return addDays(first, col * 7 + row);
  }

  @override
  bool operator ==(Object other) =>
      other is _Layout &&
      other.first == first &&
      other.weeks == weeks &&
      other.cell == cell &&
      other.top == top;

  @override
  int get hashCode => Object.hash(first, weeks, cell, top);
}

class _CalendarPainter extends CustomPainter {
  _CalendarPainter({
    required this.layout,
    required this.activity,
    required this.today,
    required this.style,
    required this.scaler,
  });

  final _Layout layout;
  final DayActivity activity;
  final DateTime today;
  final ChartStyle style;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    final month = DateFormat('MMM');
    var labelRight = double.negativeInfinity;
    for (var w = 0; w < layout.weeks; w++) {
      final start = addDays(layout.first, w * 7);
      // Label the column where a month starts.
      if (w == 0 || start.day <= 7) {
        final tp = TextPainter(
          text: TextSpan(text: month.format(start), style: style.label),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final x = w * layout.pitch;
        if (x > labelRight + DotCalendar._gap * 2 &&
            x + tp.width <= size.width) {
          tp.paint(canvas, Offset(x, 0));
          labelRight = x + tp.width;
        }
        tp.dispose();
      }
      for (var d = 0; d < 7; d++) {
        final day = addDays(start, d);
        if (day.isAfter(today)) break;
        final r = RRect.fromRectAndRadius(
          layout.rect(w, d),
          Radius.circular(math.min(4, layout.cell / 3)),
        );
        canvas.drawRRect(r, Paint()..color = style.ramp[activity.level(day)]);
        if (day == today) {
          canvas.drawRRect(
            r.deflate(0.75),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = style.line,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CalendarPainter old) =>
      old.layout != layout ||
      old.today != today ||
      old.style != style ||
      old.scaler != scaler ||
      !identical(old.activity, activity);
}
