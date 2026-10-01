import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../common.dart';

/// Card with a title row for a chart or summary.
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.caption,
    this.onTap,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return FlatCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kCompactTap),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: t.titleMedium),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          child,
          if (caption case final c?) ...[
            const SizedBox(height: Space.sm),
            Text(
              c,
              style: t.bodySmall?.copyWith(color: LiftColors.of(context).muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// A row of single-select chips.
class ChipChoice<T> extends StatelessWidget {
  const ChipChoice({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.sm,
    runSpacing: Space.sm,
    children: [
      for (final v in values)
        ChoiceChip(
          label: Text(label(v)),
          selected: v == selected,
          onSelected: (_) => onSelected(v),
        ),
    ],
  );
}
