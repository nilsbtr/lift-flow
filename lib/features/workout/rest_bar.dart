import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/rest.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/periodic_builder.dart';

/// Bottom rest countdown with ±15s and Skip. Tapping the countdown shows quick
/// presets (kept open between rests); holding it, or a preset, sets a custom
/// time. Animates in/out.
class RestBar extends ConsumerStatefulWidget {
  const RestBar({super.key});

  @override
  ConsumerState<RestBar> createState() => _RestBarState();
}

class _RestBarState extends ConsumerState<RestBar> {
  bool _presets = false;

  @override
  Widget build(BuildContext context) {
    final rest = ref.watch(restTimerProvider);
    return AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.curve,
      alignment: Alignment.bottomCenter,
      child: rest == null
          ? const SizedBox(width: double.infinity)
          : _RestPanel(
              rest: rest,
              presets: _presets,
              onTogglePresets: () => setState(() => _presets = !_presets),
            ),
    );
  }
}

class _RestPanel extends ConsumerWidget {
  const _RestPanel({
    required this.rest,
    required this.presets,
    required this.onTogglePresets,
  });
  final RestTimerState rest;
  final bool presets;
  final VoidCallback onTogglePresets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lift = LiftColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ctrl = ref.read(restTimerProvider.notifier);
    final compact = TextButton.styleFrom(
      minimumSize: const Size(kMinTap, kMinTap),
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
    );

    Future<void> custom() async {
      final seconds = await showDialog<int>(
        context: context,
        builder: (_) => _RestTimeDialog(initial: rest.totalSeconds),
      );
      if (seconds != null) ctrl.start(seconds);
    }

    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PeriodicBuilder(
              period: const Duration(seconds: 1),
              anchor: rest.endsAt,
              builder: (_) => LinearProgressIndicator(
                value: rest.progress(),
                minHeight: 4,
                color: lift.rest,
                backgroundColor: lift.raised,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.sm,
                Space.sm,
              ),
              // Wraps, countdown first, instead of overflowing at large text.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Countdown(
                    rest: rest,
                    open: presets,
                    onTap: onTogglePresets,
                    onLongPress: custom,
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        style: compact,
                        onPressed: () => ctrl.adjust(-15),
                        child: const Text('${kMinus}15'),
                      ),
                      TextButton(
                        style: compact,
                        onPressed: () => ctrl.adjust(15),
                        child: const Text('+15'),
                      ),
                      TextButton(
                        style: compact,
                        onPressed: ctrl.skip,
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (presets)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  0,
                  Space.lg,
                  Space.md,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      for (final p in kRestPresets)
                        _Chip(
                          label: fmtClock(p),
                          selected: rest.totalSeconds == p,
                          semanticLabel: 'Rest ${_spoken(p)}',
                          onTap: () => ctrl.start(p),
                          onLongPress: custom,
                        ),
                      _Chip(
                        label: 'Custom',
                        semanticLabel: 'Custom rest time',
                        onTap: custom,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _spoken(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return [if (m > 0) '$m min', if (s > 0) '$s s'].join(' ');
}

/// The timer icon and time left. Tap for presets, hold for a custom time.
class _Countdown extends StatelessWidget {
  const _Countdown({
    required this.rest,
    required this.open,
    required this.onTap,
    required this.onLongPress,
  });
  final RestTimerState rest;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final lift = LiftColors.of(context);
    final t = Theme.of(context).textTheme;
    return PeriodicBuilder(
      period: const Duration(seconds: 1),
      anchor: rest.endsAt,
      builder: (_) => Semantics(
        button: true,
        expanded: open,
        label: 'Rest, ${rest.remainingSeconds()} seconds left',
        onTap: onTap,
        onTapHint: open ? 'Hide rest presets' : 'Show rest presets',
        onLongPress: onLongPress,
        onLongPressHint: 'Set a custom rest time',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: Radii.smAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTap),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(AppIcons.timer, color: lift.rest),
                  const SizedBox(width: Space.sm),
                  Text(
                    fmtClock(rest.remainingSeconds()),
                    style: t.headlineMedium?.copyWith(color: lift.rest),
                  ),
                  const SizedBox(width: Space.xs),
                  AnimatedRotation(
                    turns: open ? 0.25 : -0.25,
                    duration: Motion.of(context, Motion.fast),
                    child: AppIcon(
                      AppIcons.chevronRight,
                      size: IconSizes.xs,
                      color: lift.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill button for the presets row.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final lift = LiftColors.of(context);
    final t = Theme.of(context).textTheme;
    final color = selected
        ? lift.rest
        : Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressHint: onLongPress == null ? null : 'Set a custom rest time',
      excludeSemantics: true,
      child: Material(
        color: selected ? lift.rest.withValues(alpha: 0.18) : lift.raised,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: kMinTap,
              minHeight: kCompactTap,
            ),
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                child: Text(
                  label,
                  style: t.labelLarge?.copyWith(
                    color: color,
                    fontFeatures: Fonts.tabular,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a rest time as seconds or m:ss.
class _RestTimeDialog extends StatefulWidget {
  const _RestTimeDialog({required this.initial});
  final int initial;

  @override
  State<_RestTimeDialog> createState() => _RestTimeDialogState();
}

class _RestTimeDialogState extends State<_RestTimeDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final text = fmtClock(widget.initial);
    _ctrl = TextEditingController(text: text)
      ..selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int? get _seconds => parseRestTime(_ctrl.text);

  void _submit() {
    if (_seconds case final s?) Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) {
    final invalid = _ctrl.text.isNotEmpty && _seconds == null;
    return AlertDialog(
      title: const Text('Custom rest'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.datetime,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[0-9:]')),
          LengthLimitingTextInputFormatter(5),
        ],
        decoration: InputDecoration(
          hintText: '1:30',
          helperText: 'Seconds or m:ss',
          errorText: invalid ? 'Between 0:01 and 60:00' : null,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _seconds == null ? null : _submit,
          child: const Text('Start'),
        ),
      ],
    );
  }
}
