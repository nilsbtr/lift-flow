import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../data/enums.dart';
import '../domain/stats.dart';
import '../domain/units.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// A body weight on a local day.
typedef Weighin = ({double kg, DateTime date});

final _day = DateFormat('EEE, d MMM y');

/// Asks for a weigh-in, today by default and never in the future. Returns null
/// when cancelled. [taken] holds the days that already have an entry.
Future<Weighin?> askBodyweight(
  BuildContext context, {
  required WeightUnit unit,
  double? initialKg,
  DateTime? initialDate,
  bool editing = false,
  Set<DateTime> taken = const {},
}) {
  final ctrl = TextEditingController(
    text: initialKg == null ? '' : fmtWeight(initialKg, unit),
  );
  final today = dayOf(DateTime.now());
  var date = initialDate == null ? today : dayOf(initialDate);
  return showDialog<Weighin>(
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
            Navigator.pop(ctx, (kg: kg, date: date));
          }

          Future<void> pickDate() async {
            final picked = await showDatePicker(
              context: ctx,
              initialDate: date,
              firstDate: DateTime(2000),
              lastDate: today,
            );
            if (picked != null) setLocal(() => date = dayOf(picked));
          }

          final t = Theme.of(ctx).textTheme;
          final muted = LiftColors.of(ctx).muted;
          final replaces =
              taken.contains(date) && !(editing && date == initialDate);
          return AlertDialog(
            title: Text(editing ? 'Edit weigh-in' : 'Log body weight'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Used for volume and e1RM of bodyweight exercises.',
                  style: t.bodyMedium?.copyWith(color: muted),
                ),
                const SizedBox(height: Space.md),
                TextButton.icon(
                  onPressed: pickDate,
                  icon: const AppIcon(AppIcons.calendar, size: IconSizes.sm),
                  label: Text(date == today ? 'Today' : _day.format(date)),
                ),
                if (replaces)
                  Text(
                    'Replaces the entry for this day.',
                    style: t.bodySmall?.copyWith(color: muted),
                  ),
                const SizedBox(height: Space.md),
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
