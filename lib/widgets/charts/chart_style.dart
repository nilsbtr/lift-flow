import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Colors and text shared by every chart.
@immutable
class ChartStyle {
  const ChartStyle({
    required this.line,
    required this.grid,
    required this.guide,
    required this.surface,
    required this.record,
    required this.goal,
    required this.muted,
    required this.empty,
    required this.label,
    required this.tooltip,
    required this.tooltipColor,
    required this.ramp,
    required this.categories,
  });

  factory ChartStyle.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lift = LiftColors.of(context);
    final t = theme.textTheme;
    Color tone(double a) =>
        Color.alphaBlend(scheme.primary.withValues(alpha: a), scheme.surface);
    return ChartStyle(
      line: scheme.primary,
      grid: scheme.outline.withValues(alpha: 0.6),
      guide: lift.muted.withValues(alpha: 0.6),
      surface: scheme.surface,
      record: lift.record,
      goal: lift.done,
      muted: lift.muted,
      empty: lift.raised,
      label: t.labelSmall!.copyWith(
        color: lift.muted,
        letterSpacing: 0,
        fontFeatures: Fonts.tabular,
      ),
      tooltip: t.labelMedium!.copyWith(
        color: scheme.onInverseSurface,
        letterSpacing: 0,
      ),
      tooltipColor: scheme.inverseSurface,
      ramp: [lift.raised, tone(0.3), tone(0.5), tone(0.75), scheme.primary],
      categories: [
        scheme.primary,
        lift.done,
        lift.rest,
        lift.record,
        tone(0.45),
        lift.muted,
      ],
    );
  }

  final Color line;
  final Color grid;

  /// Scrub guide line.
  final Color guide;

  /// Card background, used to punch out dots.
  final Color surface;
  final Color record;
  final Color goal;
  final Color muted;

  /// Placeholder fill for empty bars and rest days.
  final Color empty;
  final TextStyle label;
  final TextStyle tooltip;
  final Color tooltipColor;

  /// Tonal steps from empty (0) to full (4).
  final List<Color> ramp;

  /// Distinct colors for categories such as muscle groups.
  final List<Color> categories;

  Color category(int i) => categories[i % categories.length];

  @override
  bool operator ==(Object other) =>
      other is ChartStyle &&
      other.line == line &&
      other.grid == grid &&
      other.surface == surface &&
      other.record == record &&
      other.label == label;

  @override
  int get hashCode => Object.hash(line, grid, surface, record, label);
}

/// One semantics node that describes the whole chart in words.
class ChartSemantics extends StatelessWidget {
  const ChartSemantics({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: ExcludeSemantics(child: RepaintBoundary(child: child)),
  );
}
