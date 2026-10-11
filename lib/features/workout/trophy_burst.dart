import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// A trophy that pops in once with a ring and a few sparks, in the record
/// color. Shows the finished trophy without motion when animations are off.
class TrophyBurst extends StatefulWidget {
  const TrophyBurst({super.key, this.size = 80});
  final double size;

  @override
  State<TrophyBurst> createState() => _TrophyBurstState();
}

class _TrophyBurstState extends State<TrophyBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _started = false;

  static final _pop = CurveTween(
    curve: const Interval(0, 0.55, curve: Curves.elasticOut),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final duration = Motion.of(context, Motion.celebrate);
    if (duration == Duration.zero) {
      _c.value = 1;
    } else {
      _c.duration = duration;
      unawaited(_c.forward());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = LiftColors.of(context).record;
    return Semantics(
      label: 'New record',
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _BurstPainter(_c.value, color),
            child: Center(
              child: Transform.scale(
                scale: 0.2 + 0.8 * _pop.transform(_c.value),
                child: AppIcon(
                  AppIcons.trophySolid,
                  size: IconSizes.lg,
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.t, this.color);

  final double t;
  final Color color;

  static const _sparks = 8;
  static final _ring = CurveTween(
    curve: const Interval(0.1, 0.8, curve: Curves.easeOut),
  );
  static final _fly = CurveTween(
    curve: const Interval(0.15, 0.95, curve: Curves.easeOutCubic),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final reach = size.shortestSide / 2;

    final ring = _ring.transform(t);
    if (ring > 0 && ring < 1) {
      canvas.drawCircle(
        c,
        reach * (0.45 + 0.55 * ring),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - ring) + 0.5
          ..color = color.withValues(alpha: 0.6 * (1 - ring)),
      );
    }

    final fly = _fly.transform(t);
    if (fly <= 0 || fly >= 1) return;
    final dot = Paint()..color = color.withValues(alpha: 1 - fly);
    for (var i = 0; i < _sparks; i++) {
      final angle = (i + 0.5) * 2 * math.pi / _sparks;
      final distance = reach * (0.5 + 0.45 * fly);
      canvas.drawCircle(
        c + Offset(math.cos(angle), math.sin(angle)) * distance,
        3 * (1 - fly) + 0.5,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.color != color;
}
