import 'package:material_ui/material_ui.dart';

import '../../data/enums.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'chart_style.dart';

/// Share of working sets per muscle group, with a legend.
class SplitBar extends StatelessWidget {
  const SplitBar({super.key, required this.split});

  final Map<MuscleGroup, int> split;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final style = ChartStyle.of(context);
    final muted = LiftColors.of(context).muted;
    final groups = [
      for (final g in MuscleGroup.values)
        if ((split[g] ?? 0) > 0) g,
    ];
    if (groups.isEmpty) return const SizedBox.shrink();
    Color color(MuscleGroup g) => style.category(groups.indexOf(g));
    return Semantics(
      container: true,
      label: [for (final g in groups) '${g.label} ${split[g]} sets'].join(', '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: Radii.pill,
              child: SizedBox(
                height: Space.sm + Space.xs,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 2,
                  children: [
                    for (final g in groups)
                      Expanded(
                        flex: split[g]!,
                        child: ColoredBox(color: color(g)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.md,
              runSpacing: Space.xs,
              children: [
                for (final g in groups)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: Space.sm,
                        height: Space.sm,
                        decoration: BoxDecoration(
                          color: color(g),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: Space.xs),
                      Text(g.label, style: t.bodySmall),
                      const SizedBox(width: Space.xs),
                      Text(
                        '${split[g]}',
                        style: t.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
