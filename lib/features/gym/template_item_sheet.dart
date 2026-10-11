import 'package:material_ui/material_ui.dart';

import '../../data/enums.dart';
import '../../data/template_repository.dart';
import '../../domain/units.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';

/// What the item sheet changed: the item, and whether it is linked with the
/// next exercise.
class ItemEdit {
  const ItemEdit(this.item, {required this.link});
  final TemplateItem item;
  final bool link;
}

/// Result of [showTemplateItemSheet] when the exercise should be removed.
const removeItem = 'remove';

const _restStep = 15;
const _restMin = 15;
const _restMax = 600;

/// Rest, target weight and superset of one template exercise. Pops an
/// [ItemEdit] on Done, [removeItem] on Remove, and null if dismissed.
Future<Object?> showTemplateItemSheet(
  BuildContext context, {
  required TemplateItem item,
  required bool canLink,
  required bool linked,
  required WeightUnit unit,
  required int defaultRest,
}) => showAppSheet<Object>(
  context,
  (_) => _ItemSheet(
    item: item,
    canLink: canLink,
    linked: linked,
    unit: unit,
    defaultRest: defaultRest,
  ),
);

/// Whether a target weight makes sense for the exercise.
bool takesLoad(TemplateItem item) =>
    item.exercise.trackingType == TrackingType.weights ||
    item.exercise.loadMode != LoadMode.none;

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({
    required this.item,
    required this.canLink,
    required this.linked,
    required this.unit,
    required this.defaultRest,
  });

  final TemplateItem item;
  final bool canLink;
  final bool linked;
  final WeightUnit unit;
  final int defaultRest;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  late final _weight = TextEditingController(
    text: widget.item.targetWeightKg == null
        ? ''
        : fmtWeight(widget.item.targetWeightKg!.abs(), widget.unit),
  );
  late int? _rest = widget.item.restSeconds;
  late bool _link = widget.linked;
  late double? _weightKg = widget.item.targetWeightKg;
  String? _error;

  /// Assisted loads are entered as a positive number but stored negative.
  bool get _assisted =>
      widget.item.exercise.trackingType == TrackingType.bodyweight &&
      widget.item.exercise.loadMode == LoadMode.assisted;

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  void _stepRest(int delta) => setState(
    () => _rest = ((_rest ?? widget.defaultRest) + delta).clamp(
      _restMin,
      _restMax,
    ),
  );

  void _onWeight(String v) {
    final n = parseNumber(v);
    setState(() {
      if (v.trim().isEmpty || n == 0) {
        _error = null;
        _weightKg = null;
      } else if (n == null || n < 0) {
        _error = 'Enter a number';
      } else {
        _error = null;
        _weightKg = unitToKg(n, widget.unit) * (_assisted ? -1 : 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    final scheme = Theme.of(context).colorScheme;
    final rest = _rest ?? widget.defaultRest;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.item.exercise.name, style: t.headlineSmall),
            const SizedBox(height: Space.lg),
            Text('Rest after each set', style: t.labelLarge),
            Row(
              children: [
                IconButton(
                  tooltip: 'Less rest',
                  onPressed: rest > _restMin
                      ? () => _stepRest(-_restStep)
                      : null,
                  icon: const AppIcon(AppIcons.minus),
                ),
                Expanded(
                  child: Text(
                    fmtClock(rest),
                    textAlign: TextAlign.center,
                    style: t.titleMedium?.copyWith(
                      fontFeatures: Fonts.tabular,
                      color: _rest == null ? muted : null,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'More rest',
                  onPressed: rest < _restMax
                      ? () => _stepRest(_restStep)
                      : null,
                  icon: const AppIcon(AppIcons.plus),
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _rest == null
                      ? 'Default from settings'
                      : 'Default is ${fmtClock(widget.defaultRest)}',
                  style: t.bodySmall?.copyWith(color: muted),
                ),
                if (_rest != null)
                  TextButton(
                    onPressed: () => setState(() => _rest = null),
                    child: const Text('Use default'),
                  ),
              ],
            ),
            if (takesLoad(widget.item)) ...[
              const SizedBox(height: Space.lg),
              Text(
                _assisted ? 'Target assistance' : 'Target weight',
                style: t.labelLarge,
              ),
              const SizedBox(height: Space.sm),
              TextField(
                controller: _weight,
                onChanged: _onWeight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: 'Optional',
                  suffixText: widget.unit.label,
                  errorText: _error,
                  helperText: 'Shown until you have a previous session',
                  helperMaxLines: 2,
                ),
              ),
            ],
            const SizedBox(height: Space.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Superset with next'),
              subtitle: Text(
                widget.canLink
                    ? 'Alternate sets with the exercise below'
                    : 'Add an exercise below to link',
              ),
              value: _link && widget.canLink,
              onChanged: widget.canLink
                  ? (v) => setState(() => _link = v)
                  : null,
            ),
            const SizedBox(height: Space.sm),
            FilledButton(
              onPressed: _error != null
                  ? null
                  : () => Navigator.pop(
                      context,
                      ItemEdit(
                        widget.item.copyWith(
                          restSeconds: () => _rest,
                          targetWeightKg: () => _weightKg,
                        ),
                        link: _link && widget.canLink,
                      ),
                    ),
              child: const Text('Done'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(context, removeItem),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              icon: const AppIcon(AppIcons.trash, size: IconSizes.sm),
              label: const Text('Remove exercise'),
            ),
          ],
        ),
      ),
    );
  }
}
