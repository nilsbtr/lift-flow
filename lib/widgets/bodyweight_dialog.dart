import 'package:material_ui/material_ui.dart';

import '../data/enums.dart';
import '../domain/units.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Asks for today’s body weight. Returns kg, or null when cancelled.
Future<double?> askBodyweight(
  BuildContext context, {
  required WeightUnit unit,
  double? initialKg,
}) {
  final ctrl = TextEditingController(
    text: initialKg == null ? '' : fmtWeight(initialKg, unit),
  );
  return showDialog<double>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void submit() {
              final v = parseNumber(ctrl.text);
              final kg = v == null ? null : unitToKg(v, unit);
              if (kg == null || kg < 20 || kg > 400) {
                setLocal(() => error = 'Enter a realistic body weight');
                return;
              }
              Navigator.pop(ctx, kg);
            }

            return AlertDialog(
              title: const Text('Log body weight'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saved for today. Used for volume and e1RM of bodyweight '
                    'exercises.',
                    style: Theme.of(ctx).textTheme.bodyMedium
                        ?.copyWith(color: LiftColors.of(ctx).muted),
                  ),
                  const SizedBox(height: Space.lg),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      suffixText: unit.label,
                      errorText: error,
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                ],
              ),
              actions: [
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
