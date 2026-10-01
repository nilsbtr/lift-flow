import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/units.dart';
import '../../theme/tokens.dart';
import 'chart_style.dart';
import 'scale.dart';

/// Maps data to pixels inside the plot area.
@immutable
class ChartGeometry {
  const ChartGeometry({
    required this.plot,
    required this.y,
    required this.xMin,
    required this.xMax,
  });

  final Rect plot;
  final NiceScale y;
  final double xMin;
  final double xMax;

  double dx(double x) => xMax - xMin < 1e-9
      ? plot.center.dx
      : plot.left + (x - xMin) / (xMax - xMin) * plot.width;

  double dy(double v) => plot.bottom - y.norm(v) * plot.height;

  Offset at(double x, double v) => Offset(dx(x), dy(v));

  @override
  bool operator ==(Object other) =>
      other is ChartGeometry &&
      other.plot == plot &&
      other.y.min == y.min &&
      other.y.max == y.max &&
      other.xMin == xMin &&
      other.xMax == xMax;

  @override
  int get hashCode => Object.hash(plot, y.min, y.max, xMin, xMax);
}

/// The marks one chart draws inside an [AxisChart].
abstract class ChartLayer {
  const ChartLayer();

  /// [t] is the draw-in progress from 0 to 1. [selected] is the highlighted
  /// point, if any.
  void paint(
    Canvas canvas,
    ChartGeometry g,
    ChartStyle style,
    double t,
    int? selected,
  );

  bool shouldRepaint(covariant ChartLayer old);
}

enum ScrubMode {
  /// Picks the point closest in x; for lines and bars.
  nearestX,

  /// Picks the point under the finger; for scatter plots.
  nearest,
}

/// Shared chart scaffold: axes, gridlines, labels, draw-in, touch and
/// semantics. The [layer] draws the data.
class AxisChart extends StatefulWidget {
  const AxisChart({
    super.key,
    required this.xs,
    required this.ys,
    required this.y,
    required this.layer,
    required this.semanticLabel,
    this.xMin,
    this.xMax,
    this.xLabels = const [],
    this.yLabel = fmtCompact,
    this.height = 176,
    this.tooltip,
    this.onSelect,
    this.scrub = ScrubMode.nearestX,
    this.animateKey,
  });

  /// Point positions, used for touch and the tooltip anchor.
  final List<double> xs;
  final List<double> ys;
  final NiceScale y;
  final ChartLayer layer;
  final String semanticLabel;

  /// Defaults to the range of [xs].
  final double? xMin;
  final double? xMax;
  final List<(double, String)> xLabels;
  final String Function(double) yLabel;
  final double height;

  /// Tooltip text for a point.
  final String Function(int)? tooltip;
  final ValueChanged<int?>? onSelect;
  final ScrubMode scrub;

  /// Changing it replays the draw-in.
  final Object? animateKey;

  bool get interactive => xs.isNotEmpty && (tooltip != null || onSelect != null);

  @override
  State<AxisChart> createState() => _AxisChartState();
}

class _AxisChartState extends State<AxisChart>
    with SingleTickerProviderStateMixin {
  late final _draw = AnimationController(vsync: this);
  late final _t = CurvedAnimation(parent: _draw, curve: Motion.curve);
  final _selected = ValueNotifier<int?>(null);
  var _pinned = false;
  var _played = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_played) {
      _played = true;
      _play();
    }
  }

  @override
  void didUpdateWidget(AxisChart old) {
    super.didUpdateWidget(old);
    if (old.animateKey != widget.animateKey) _play();
    final i = _selected.value;
    if (i != null && i >= widget.xs.length) _select(null);
  }

  @override
  void dispose() {
    _t.dispose();
    _draw.dispose();
    _selected.dispose();
    super.dispose();
  }

  void _play() {
    final d = Motion.of(context, Motion.chart);
    if (d == Duration.zero) {
      _draw.value = 1;
    } else {
      _draw.duration = d;
      unawaited(_draw.forward(from: 0));
    }
  }

  void _select(int? i, {bool haptic = false}) {
    if (_selected.value == i) return;
    _selected.value = i;
    if (haptic && i != null) unawaited(HapticFeedback.selectionClick());
    widget.onSelect?.call(i);
  }

  int? _hit(Offset p, ChartGeometry g) {
    final xs = widget.xs;
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < xs.length; i++) {
      final d = switch (widget.scrub) {
        ScrubMode.nearestX => (g.dx(xs[i]) - p.dx).abs(),
        ScrubMode.nearest => (g.at(xs[i], widget.ys[i]) - p).distance,
      };
      if (d < bestD) (best, bestD) = (i, d);
    }
    if (widget.scrub == ScrubMode.nearest && bestD > kMinTap / 2) return null;
    return best;
  }

  ChartGeometry _geometry(Size size, ChartStyle style, TextScaler scaler) {
    var labelW = 0.0;
    var labelH = 0.0;
    for (final v in widget.y.ticks) {
      final tp = _label(widget.yLabel(v), style.label, scaler);
      labelW = math.max(labelW, tp.width);
      labelH = tp.height;
      tp.dispose();
    }
    final xs = widget.xs;
    return ChartGeometry(
      plot: Rect.fromLTRB(
        labelW + Space.sm,
        labelH / 2 + Space.xs,
        size.width - Space.sm,
        size.height -
            (widget.xLabels.isEmpty ? labelH / 2 : labelH + Space.xs),
      ),
      y: widget.y,
      xMin: widget.xMin ?? (xs.isEmpty ? 0 : xs.reduce(math.min)),
      xMax: widget.xMax ?? (xs.isEmpty ? 1 : xs.reduce(math.max)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = ChartStyle.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return ChartSemantics(
      label: widget.semanticLabel,
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, c) {
            final g = _geometry(c.biggest, style, scaler);
            final chart = CustomPaint(
              size: c.biggest,
              painter: _AxisPainter(
                geometry: g,
                style: style,
                layer: widget.layer,
                yTicks: widget.y.ticks,
                yLabel: widget.yLabel,
                xLabels: widget.xLabels,
                xs: widget.xs,
                scaler: scaler,
                t: _t,
                selected: _selected,
              ),
            );
            if (!widget.interactive) return chart;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) {
                _pinned = false;
                _select(_hit(d.localPosition, g), haptic: true);
              },
              onHorizontalDragUpdate: (d) =>
                  _select(_hit(d.localPosition, g), haptic: true),
              onHorizontalDragEnd: (_) => _select(null),
              // A tap also cancels the drag; keep a pinned selection then.
              onHorizontalDragCancel: () {
                if (!_pinned) _select(null);
              },
              onTapUp: (d) {
                final i = _hit(d.localPosition, g);
                final again = _pinned && i == _selected.value;
                _pinned = i != null && !again;
                _select(_pinned ? i : null);
              },
              child: Stack(
                children: [
                  chart,
                  if (widget.tooltip case final tooltip?)
                    Positioned.fill(
                      child: ValueListenableBuilder(
                        valueListenable: _selected,
                        builder: (context, i, _) {
                          if (i == null || i >= widget.xs.length) {
                            return const SizedBox.shrink();
                          }
                          return CustomSingleChildLayout(
                            delegate: _TooltipLayout(
                              g.at(widget.xs[i], widget.ys[i]),
                            ),
                            child: ChartTooltip(tooltip(i)),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

TextPainter _label(String text, TextStyle style, TextScaler scaler) =>
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();

class _AxisPainter extends CustomPainter {
  _AxisPainter({
    required this.geometry,
    required this.style,
    required this.layer,
    required this.yTicks,
    required this.yLabel,
    required this.xLabels,
    required this.xs,
    required this.scaler,
    required this.t,
    required this.selected,
  }) : super(repaint: Listenable.merge([t, selected]));

  final ChartGeometry geometry;
  final ChartStyle style;
  final ChartLayer layer;
  final List<double> yTicks;
  final String Function(double) yLabel;
  final List<(double, String)> xLabels;
  final List<double> xs;
  final TextScaler scaler;
  final Animation<double> t;
  final ValueListenable<int?> selected;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final p = g.plot;
    final grid = Paint()
      ..color = style.grid
      ..strokeWidth = 1;
    for (final v in yTicks) {
      final y = g.dy(v);
      canvas.drawLine(Offset(p.left, y), Offset(p.right, y), grid);
      final tp = _label(yLabel(v), style.label, scaler);
      tp.paint(canvas, Offset(p.left - Space.sm - tp.width, y - tp.height / 2));
      tp.dispose();
    }
    // Right to left so the newest label wins; skip labels that would collide.
    var limit = double.infinity;
    for (final (x, text) in xLabels.sortedBy<num>((l) => l.$1).reversed) {
      final tp = _label(text, style.label, scaler);
      // Keep clear of the y labels on the left.
      final left = math.max(
        p.left,
        math.min(g.dx(x) - tp.width / 2, size.width - tp.width),
      );
      if (left + tp.width <= limit) {
        tp.paint(canvas, Offset(left, p.bottom + Space.xs));
        limit = left - Space.sm;
      }
      tp.dispose();
    }
    final i = selected.value;
    if (i != null && i < xs.length) {
      final x = g.dx(xs[i]);
      canvas.drawLine(
        Offset(x, p.top),
        Offset(x, p.bottom),
        Paint()
          ..color = style.guide
          ..strokeWidth = 1,
      );
    }
    layer.paint(canvas, g, style, t.value, i);
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.geometry != geometry ||
      old.style != style ||
      old.scaler != scaler ||
      !listEquals(old.yTicks, yTicks) ||
      !listEquals(old.xLabels, xLabels) ||
      layer.shouldRepaint(old.layer);
}

/// Places the tooltip above its anchor, or below when there's no room.
class _TooltipLayout extends SingleChildLayoutDelegate {
  _TooltipLayout(this.anchor);
  final Offset anchor;

  static const _gap = Space.md;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => c.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = math.max(
      0.0,
      math.min(anchor.dx - child.width / 2, size.width - child.width),
    );
    final above = anchor.dy - _gap - child.height;
    return Offset(x, above >= 0 ? above : anchor.dy + _gap);
  }

  @override
  bool shouldRelayout(_TooltipLayout old) => old.anchor != anchor;
}

class ChartTooltip extends StatelessWidget {
  const ChartTooltip(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = ChartStyle.of(context);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: style.tooltipColor,
          borderRadius: const BorderRadius.all(Radius.circular(Space.sm)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: Space.xs,
          ),
          child: Text(text, style: style.tooltip),
        ),
      ),
    );
  }
}
