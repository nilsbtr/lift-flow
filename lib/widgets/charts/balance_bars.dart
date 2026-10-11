import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../data/enums.dart';
import '../../domain/units.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'chart_style.dart';

/// Weekly sets per muscle group against a target band.
class BalanceBars extends StatelessWidget {
  const BalanceBars({super.key, required this.sets, this.low = 10, this.high = 20});

  /// Working sets per week.
  final Map<MuscleGroup, double> sets;
  final double low;
  final double high;

  /// Always listed. Other groups, including the legacy arms and legs, only
  /// show up when they have sets.
  static const _main = [
    MuscleGroup.chest,
    MuscleGroup.back,
    MuscleGroup.shoulders,
    MuscleGroup.biceps,
    MuscleGroup.triceps,
    MuscleGroup.core,
    MuscleGroup.quads,
    MuscleGroup.hamstrings,
    MuscleGroup.glutes,
    MuscleGroup.calves,
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final lift = LiftColors.of(context);
    final style = ChartStyle.of(context);
    final groups = [
      for (final g in MuscleGroup.values)
        if (_main.contains(g) || (sets[g] ?? 0) > 0) g,
    ];
    final top = math.max(high * 1.2, sets.values.fold(0.0, math.max));
    // Large text gets the label on its own line so names don't break.
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 15;
    return Column(
      children: [
        for (final g in groups)
          Builder(
            builder: (context) {
              final v = sets[g] ?? 0;
              final shown = fmtNum((v * 10).roundToDouble() / 10);
              final color = v < low
                  ? lift.rest
                  : v > high
                  ? scheme.primary
                  : lift.done;
              final label = Text(g.label, style: t.bodyMedium);
              final value = Text(
                shown,
                textAlign: TextAlign.end,
                style: t.labelMedium?.copyWith(color: lift.muted),
              );
              final bar = LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  return SizedBox(
                    height: Space.sm,
                    child: Stack(
                      children: [
                        Positioned.fill(child: _Pill(color: style.empty)),
                        Positioned(
                          left: w * low / top,
                          width: w * (high - low) / top,
                          top: 0,
                          bottom: 0,
                          child: ColoredBox(
                            color: lift.done.withValues(alpha: 0.2),
                          ),
                        ),
                        if (v > 0)
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: math.max(Space.sm, w * v / top),
                            child: _Pill(color: color),
                          ),
                      ],
                    ),
                  );
                },
              );
              return Semantics(
                container: true,
                label: '${g.label}: $shown sets a week',
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: Space.xs,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: label),
                                  value,
                                ],
                              ),
                              bar,
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(flex: 2, child: label),
                              Expanded(flex: 5, child: bar),
                              SizedBox(width: Space.xxl + Space.sm, child: value),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: Radii.pill,
    ),
  );
}
