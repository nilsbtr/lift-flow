import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/units.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'workout_controller.dart';

/// Column widths shared by the header and rows.
abstract final class SetCols {
  static const double set = 32;
  static const double load = 76;
  static const double reps = 64;
  static const double check = 48;
  static const double gap = Space.sm;
}

String loadHeader(DraftExercise ex, WeightUnit unit) {
  final u = unit.label.toUpperCase();
  if (ex.type == TrackingType.weights) return u;
  return switch (ex.mode) {
    LoadMode.none => '',
    LoadMode.added => '+$u',
    LoadMode.assisted => '$kMinus$u',
  };
}

class SetHeader extends StatelessWidget {
  const SetHeader({super.key, required this.exercise, required this.unit});
  final DraftExercise exercise;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: LiftColors.of(context).muted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      child: Row(
        children: [
          SizedBox(
            width: SetCols.set,
            child: Text('SET', style: style, textAlign: TextAlign.center),
          ),
          const SizedBox(width: SetCols.gap),
          Expanded(child: Text('PREVIOUS', style: style)),
          if (exercise.hasLoad) ...[
            SizedBox(
              width: SetCols.load,
              child: Text(
                loadHeader(exercise, unit),
                style: style,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: SetCols.gap),
          ],
          SizedBox(
            width: SetCols.reps,
            child: Text('REPS', style: style, textAlign: TextAlign.center),
          ),
          const SizedBox(width: SetCols.check),
        ],
      ),
    );
  }
}

class SetRow extends ConsumerStatefulWidget {
  const SetRow({
    super.key,
    required this.workoutId,
    required this.exercise,
    required this.index,
    required this.unit,
  });

  final int workoutId;
  final DraftExercise exercise;
  final int index;
  final WeightUnit unit;

  @override
  ConsumerState<SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<SetRow> {
  late final TextEditingController _load;
  late final TextEditingController _reps;
  final _loadFocus = FocusNode();
  final _repsFocus = FocusNode();

  WorkoutSet get _set => widget.exercise.sets[widget.index];
  bool get _assisted =>
      widget.exercise.type == TrackingType.bodyweight &&
      widget.exercise.mode == LoadMode.assisted;

  WorkoutEditor get _editor =>
      ref.read(workoutEditorProvider(widget.workoutId).notifier);

  @override
  void initState() {
    super.initState();
    _load = TextEditingController(text: _loadText(_set.loadKg));
    _reps = TextEditingController(text: _set.reps?.toString() ?? '');
    _loadFocus.addListener(_onBlur);
    _repsFocus.addListener(_onBlur);
  }

  void _onBlur() {
    if (!_loadFocus.hasFocus && !_repsFocus.hasFocus) _editor.flush();
  }

  String _loadText(double? kg) {
    if (kg == null) return '';
    final display = _assisted ? -kg : kg;
    if (_assisted && display == 0) return '0';
    return fmtWeight(display, widget.unit);
  }

  double? _parseLoad(String text) {
    final v = parseNumber(text);
    if (v == null) return null;
    final kg = unitToKg(v.abs(), widget.unit);
    return _assisted ? -kg : kg;
  }

  @override
  void didUpdateWidget(SetRow old) {
    super.didUpdateWidget(old);
    final s = _set;
    final parsed = _parseLoad(_load.text);
    final same =
        (parsed == null && s.loadKg == null) ||
        (parsed != null &&
            s.loadKg != null &&
            (parsed - s.loadKg!).abs() < 0.005);
    if (!same || old.unit != widget.unit) _load.text = _loadText(s.loadKg);
    final reps = int.tryParse(_reps.text);
    if (reps != s.reps) _reps.text = s.reps?.toString() ?? '';
  }

  @override
  void dispose() {
    _load.dispose();
    _reps.dispose();
    _loadFocus.dispose();
    _repsFocus.dispose();
    super.dispose();
  }

  void _toggle() {
    final result = _editor.toggleDone(widget.exercise.id, _set.id);
    switch (result) {
      case CompleteResult.ok:
        HapticFeedback.lightImpact();
        FocusScope.of(context).unfocus();
      case CompleteResult.needsReps:
        _repsFocus.requestFocus();
      case CompleteResult.needsWeight:
        _loadFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.exercise;
    final s = _set;
    final done = s.isCompleted;
    final lift = LiftColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final hint = ex.hintFor(widget.index);
    final label = setLabels(ex.sets.map((s) => s.isWarmup))[widget.index];
    final prev = widget.index < ex.previous.length
        ? ex.previous[widget.index]
        : null;

    final prevText = prev == null
        ? '–'
        : fmtSet(
            type: ex.type,
            mode: ex.mode,
            loadKg: prev.loadKg,
            reps: prev.reps,
            unit: widget.unit,
          );

    final fieldFill = done ? Colors.transparent : lift.raised;
    final numStyle = t.titleMedium?.copyWith(fontFeatures: Fonts.tabular);

    InputDecoration deco(String? hintText) => InputDecoration(
      hintText: hintText,
      fillColor: fieldFill,
      contentPadding: const EdgeInsets.symmetric(vertical: Space.md),
    );

    return AnimatedContainer(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.curve,
      color: done ? lift.done.withValues(alpha: 0.12) : Colors.transparent,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Row(
          children: [
            SizedBox(
              width: SetCols.set,
              height: kMinTap,
              child: Semantics(
                button: true,
                label: s.isWarmup ? 'Warm-up set' : 'Set $label',
                hint: s.isWarmup ? 'Make working set' : 'Make warm-up',
                excludeSemantics: true,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () {
                    unawaited(HapticFeedback.selectionClick());
                    _editor.toggleWarmup(ex.id, s.id);
                  },
                  child: Center(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: t.titleSmall?.copyWith(
                        color: s.isWarmup
                            ? lift.rest
                            : done
                            ? lift.done
                            : lift.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: SetCols.gap),
            Expanded(
              child: Text(
                prevText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium?.copyWith(color: lift.muted),
              ),
            ),
            if (ex.hasLoad) ...[
              SizedBox(
                width: SetCols.load,
                child: TextField(
                  controller: _load,
                  focusNode: _loadFocus,
                  textAlign: TextAlign.center,
                  style: numStyle,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  textInputAction: TextInputAction.next,
                  decoration: deco(
                    hint.load == null ? null : _loadText(hint.load),
                  ),
                  onChanged: (v) => _editor.setLoad(ex.id, s.id, _parseLoad(v)),
                ),
              ),
              const SizedBox(width: SetCols.gap),
            ],
            SizedBox(
              width: SetCols.reps,
              child: TextField(
                controller: _reps,
                focusNode: _repsFocus,
                textAlign: TextAlign.center,
                style: numStyle,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _toggle(),
                decoration: deco(hint.reps?.toString()),
                onChanged: (v) => _editor.setReps(ex.id, s.id, int.tryParse(v)),
              ),
            ),
            SizedBox(
              width: SetCols.check,
              height: kMinTap,
              child: IconButton(
                tooltip: done ? 'Mark not done' : 'Complete set',
                onPressed: _toggle,
                icon: AnimatedSwitcher(
                  duration: Motion.of(context, Motion.fast),
                  transitionBuilder: (child, a) =>
                      ScaleTransition(scale: a, child: child),
                  child: done
                      ? AppIcon(
                          AppIcons.checkSolid,
                          key: const ValueKey(true),
                          color: lift.done,
                        )
                      : AppIcon(
                          AppIcons.check,
                          key: const ValueKey(false),
                          color: scheme.onSurfaceVariant,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
