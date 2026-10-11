import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/loading.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';

/// Settings rows for the bar weight and the plates of the plate calculator.
class BarbellSettings extends ConsumerWidget {
  const BarbellSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final unit = s.weightUnit;
    final bar = BarSetup.of(s.barWeightKg, s.plates, unit);
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        ListTile(
          title: const Text('Bar weight'),
          subtitle: s.barWeightKg == null ? const Text('Default') : null,
          trailing: Text(
            '${fmtWeight(bar.barKg, unit)} ${unit.label}',
            style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          onTap: () async {
            final result = await _askBar(
              context,
              unit: unit,
              barKg: bar.barKg,
              custom: s.barWeightKg != null,
            );
            if (result == null) return;
            await ref
                .read(settingsProvider.notifier)
                .update(AppSettingsCompanion(barWeightKg: Value(result.kg)));
          },
        ),
        ListTile(
          title: const Text('Plates'),
          subtitle: Text(
            bar.plates.isEmpty
                ? 'None'
                : '${bar.plates.map((p) => fmtWeight(p, unit)).join(', ')} '
                      '${unit.label}',
          ),
          onTap: () => showAppSheet<void>(context, (_) => const _PlatesSheet()),
        ),
      ],
    );
  }
}

/// Asks for the bar weight. Returns null on cancel and a null `kg` to go back
/// to the default.
Future<({double? kg})?> _askBar(
  BuildContext context, {
  required WeightUnit unit,
  required double barKg,
  required bool custom,
}) {
  final ctrl = TextEditingController(text: fmtWeight(barKg, unit));
  return showDialog<({double? kg})>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          void submit() {
            final v = parseNumber(ctrl.text);
            final kg = v == null ? null : unitToKg(v, unit);
            if (kg == null || kg < 0 || kg > 100) {
              setLocal(() => error = 'Enter a bar weight');
              return;
            }
            Navigator.pop(ctx, (kg: kg));
          }

          return AlertDialog(
            title: const Text('Bar weight'),
            content: TextField(
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
            actions: [
              if (custom)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, (kg: null)),
                  child: const Text('Use default'),
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

class _PlatesSheet extends ConsumerStatefulWidget {
  const _PlatesSheet();

  @override
  ConsumerState<_PlatesSheet> createState() => _PlatesSheetState();
}

class _PlatesSheetState extends ConsumerState<_PlatesSheet> {
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  static bool _has(Iterable<double> plates, double kg) =>
      plates.any((p) => (p - kg).abs() < 1e-6);

  Future<void> _write(Iterable<double>? plates) => ref
      .read(settingsProvider.notifier)
      .update(
        AppSettingsCompanion(
          plates: Value(plates == null ? null : encodePlates(plates)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final unit = s.weightUnit;
    final plates = parsePlates(s.plates, unit);
    final choices = [
      ...plateChoicesKg(unit),
      for (final p in plates)
        if (!_has(plateChoicesKg(unit), p)) p,
    ]..sort((a, b) => b.compareTo(a));
    final t = Theme.of(context).textTheme;

    void addOther() {
      final v = parseNumber(_other.text);
      final kg = v == null ? null : unitToKg(v, unit);
      if (kg == null || kg <= 0 || kg > 100) return;
      _other.clear();
      if (!_has(plates, kg)) unawaited(_write([...plates, kg]));
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Plates', style: t.titleLarge),
            const SizedBox(height: Space.xs),
            Text(
              'Sizes you can load on each side, in ${unit.label}.',
              style: t.bodyMedium?.copyWith(
                color: LiftColors.of(context).muted,
              ),
            ),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              children: [
                for (final p in choices)
                  FilterChip(
                    label: Text(fmtWeight(p, unit)),
                    selected: _has(plates, p),
                    onSelected: (on) => _write([
                      for (final x in plates)
                        if ((x - p).abs() >= 1e-6) x,
                      if (on) p,
                    ]),
                  ),
              ],
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _other,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Other size',
                      suffixText: unit.label,
                    ),
                    onSubmitted: (_) => addOther(),
                  ),
                ),
                const SizedBox(width: Space.sm),
                TextButton(onPressed: addOther, child: const Text('Add')),
              ],
            ),
            const SizedBox(height: Space.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Space.sm,
              children: [
                if (s.plates != null)
                  TextButton(
                    onPressed: () => _write(null),
                    child: const Text('Use default'),
                  ),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
