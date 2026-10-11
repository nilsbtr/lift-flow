import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/stats.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Asks for the weekly sets band of the muscle balance chart. Returns
/// (min, max), or null when cancelled.
Future<(int, int)?> askBalanceBand(
  BuildContext context, {
  required int min,
  required int max,
}) {
  final minCtrl = TextEditingController(text: '$min');
  final maxCtrl = TextEditingController(text: '$max');
  return showDialog<(int, int)>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          void submit() {
            final lo = int.tryParse(minCtrl.text.trim());
            final hi = int.tryParse(maxCtrl.text.trim());
            final e = balanceBandError(lo, hi);
            if (e != null) {
              setLocal(() => error = e);
              return;
            }
            Navigator.pop(ctx, (lo!, hi!));
          }

          Widget field(String label, TextEditingController c, bool last) =>
              Expanded(
                child: TextField(
                  controller: c,
                  keyboardType: TextInputType.number,
                  textInputAction: last
                      ? TextInputAction.done
                      : TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: label),
                  onSubmitted: last ? (_) => submit() : null,
                ),
              );

          final t = Theme.of(ctx).textTheme;
          return AlertDialog(
            title: const Text('Muscle balance band'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Weekly sets per muscle that count as on target.',
                  style: t.bodyMedium?.copyWith(
                    color: LiftColors.of(ctx).muted,
                  ),
                ),
                const SizedBox(height: Space.lg),
                Row(
                  spacing: Space.md,
                  children: [
                    field('Min', minCtrl, false),
                    field('Max', maxCtrl, true),
                  ],
                ),
                if (error case final e?) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    e,
                    style: t.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, kBalanceDefault),
                child: const Text('Reset'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(onPressed: submit, child: const Text('Save')),
            ],
          );
        },
      );
    },
  );
}
