import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/records.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'set_menu_sheet.dart';
import 'workout_controller.dart';

/// Column widths shared by the header and rows, at text scale 1.
abstract final class SetCols {
  static const double set = 32;
  static const double load = 76;
  static const double reps = 64;
  static const double effort = 48;
  static const double check = 48;
  static const double gap = Space.sm;

  /// Below this the Previous column is left empty.
  static const double minPrevious = 40;

  /// Fits the columns into [width]. The inputs grow with [textScale] and take
  /// their room from Previous. Only once that is used up do the inputs, and
  /// their text with them, shrink.
  static SetWidths fit(
    double width, {
    required double textScale,
    required bool load,
    bool effort = false,
  }) {
    final scale = textScale.clamp(1.0, 2.0);
    final set = SetCols.set * math.min(scale, 1.5);
    final gaps = gap * (1 + (load ? 1 : 0) + (effort ? 1 : 0));
    final room = math.max(0.0, width - set - check - gaps);
    final wanted =
        ((load ? SetCols.load : 0.0) + reps + (effort ? SetCols.effort : 0.0)) *
        scale;
    final f = wanted <= room ? 1.0 : room / wanted;
    return SetWidths(
      set: set,
      previous: room - wanted * f,
      load: SetCols.load * scale * f,
      reps: reps * scale * f,
      effort: SetCols.effort * scale * f,
      inputScale: math.max(1.0, scale * f),
    );
  }

  static SetWidths of(
    BuildContext context,
    double width, {
    required bool load,
    required bool effort,
  }) => fit(
    width,
    textScale: MediaQuery.textScalerOf(context).scale(100) / 100,
    load: load,
    effort: effort,
  );
}

class SetWidths {
  const SetWidths({
    required this.set,
    required this.previous,
    required this.load,
    required this.reps,
    required this.effort,
    required this.inputScale,
  });

  final double set;
  final double previous;
  final double load;
  final double reps;
  final double effort;

  /// Largest text scale that still fits the input columns.
  final double inputScale;
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
  const SetHeader({
    super.key,
    required this.exercise,
    required this.unit,
    this.effort = EffortMode.off,
  });
  final DraftExercise exercise;
  final WeightUnit unit;
  final EffortMode effort;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: LiftColors.of(context).muted);
    final hasEffort = effort != EffortMode.off;
    // Labels scale down rather than wrap when large text narrows a column.
    Widget cell(double width, String text) => SizedBox(
      width: width,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, style: style, maxLines: 1),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.md),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = SetCols.of(
            context,
            box.maxWidth,
            load: exercise.hasLoad,
            effort: hasEffort,
          );
          return Row(
            children: [
              cell(w.set, 'SET'),
              const SizedBox(width: SetCols.gap),
              Expanded(
                child: w.previous < SetCols.minPrevious
                    ? const SizedBox.shrink()
                    : Text(
                        'PREVIOUS',
                        style: style,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              if (exercise.hasLoad) ...[
                cell(w.load, loadHeader(exercise, unit)),
                const SizedBox(width: SetCols.gap),
              ],
              cell(w.reps, 'REPS'),
              if (hasEffort) ...[
                const SizedBox(width: SetCols.gap),
                cell(w.effort, effort.label.toUpperCase()),
              ],
              const SizedBox(width: SetCols.check),
            ],
          );
        },
      ),
    );
  }
}

/// One-time pointer to the set menu, which has no visible button of its own.
class SetMenuHint extends ConsumerWidget {
  const SetMenuHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(settingsProvider.select((s) => s.setMenuHintSeen))) {
      return const SizedBox.shrink();
    }
    final lift = LiftColors.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, Space.sm),
      padding: const EdgeInsets.only(left: Space.md),
      decoration: BoxDecoration(color: lift.raised, borderRadius: Radii.smAll),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Tap a set number for warm-up, failure, a note or delete.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => markSetMenuHintSeen(ref),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

void markSetMenuHintSeen(WidgetRef ref) {
  if (ref.read(settingsProvider).setMenuHintSeen) return;
  unawaited(
    ref
        .read(settingsProvider.notifier)
        .update(const AppSettingsCompanion(setMenuHintSeen: Value(true))),
  );
}

class SetRow extends ConsumerStatefulWidget {
  const SetRow({
    super.key,
    required this.workoutId,
    required this.exercise,
    required this.index,
    required this.unit,
    this.effort = EffortMode.off,
    this.records = const {},
  });

  final int workoutId;
  final DraftExercise exercise;
  final int index;
  final WeightUnit unit;

  /// Adds the RPE or RIR column.
  final EffortMode effort;

  /// Records this set beats.
  final Set<PrKind> records;

  @override
  ConsumerState<SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<SetRow> {
  /// Mounted rows by set id, so a row can hand the focus to the next one.
  static final _mounted = <int, _SetRowState>{};

  late final TextEditingController _load;
  late final TextEditingController _reps;
  late final TextEditingController _effort;
  final _loadFocus = FocusNode();
  final _repsFocus = FocusNode();
  final _effortFocus = FocusNode();
  late final int _setId = _set.id;

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
    _effort = TextEditingController(text: fmtEffort(_set.rpe, widget.effort));
    _loadFocus.addListener(_onBlur);
    _repsFocus.addListener(_onBlur);
    _effortFocus.addListener(_onBlur);
    _mounted[_setId] = this;
  }

  bool get _typing =>
      _loadFocus.hasFocus || _repsFocus.hasFocus || _effortFocus.hasFocus;

  void _onBlur() {
    if (!_typing) _editor.flush();
    if (_effortFocus.hasFocus || widget.index >= widget.exercise.sets.length) {
      return;
    }
    // Shows what was stored, e.g. 7.5 for a typed 7.3.
    final text = fmtEffort(_set.rpe, widget.effort);
    if (_effort.text != text) _effort.text = text;
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
    if (parseEffort(_effort.text, widget.effort) != s.rpe ||
        old.effort != widget.effort) {
      _effort.text = fmtEffort(s.rpe, widget.effort);
    }
  }

  @override
  void dispose() {
    if (_mounted[_setId] == this) _mounted.remove(_setId);
    _load.dispose();
    _reps.dispose();
    _effort.dispose();
    _loadFocus.dispose();
    _repsFocus.dispose();
    _effortFocus.dispose();
    super.dispose();
  }

  void _toggle() {
    // Only carry on typing if the keyboard is already up.
    final typing = _typing;
    final result = _editor.toggleDone(widget.exercise.id, _set.id);
    switch (result) {
      case CompleteResult.ok:
        HapticFeedback.lightImpact();
        final ex = ref
            .read(workoutEditorProvider(widget.workoutId))
            .value
            ?.byId(widget.exercise.id);
        final next = typing && ex != null ? nextField(ex, widget.index) : null;
        final row = next == null ? null : _mounted[next.setId];
        if (row == null) {
          FocusScope.of(context).unfocus();
        } else if (next!.field == SetField.load) {
          row._loadFocus.requestFocus();
        } else {
          row._repsFocus.requestFocus();
        }
      case CompleteResult.needsReps:
        _repsFocus.requestFocus();
      case CompleteResult.needsWeight:
        _loadFocus.requestFocus();
    }
  }

  void _menu() {
    unawaited(HapticFeedback.selectionClick());
    markSetMenuHintSeen(ref);
    unawaited(
      showSetMenu(
        context,
        editor: _editor,
        exercise: widget.exercise,
        setId: _set.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.exercise;
    final s = _set;
    final done = s.isCompleted;
    final lift = LiftColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final hasEffort = widget.effort != EffortMode.off;
    final hint = ex.hintFor(widget.index);
    final label = setLabels(ex.sets.map((s) => s.setType))[widget.index];
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, box) {
                final w = SetCols.of(
                  context,
                  box.maxWidth,
                  load: ex.hasLoad,
                  effort: hasEffort,
                );
                Widget input(double width, Widget field) => SizedBox(
                  width: width,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: w.inputScale,
                    child: field,
                  ),
                );
                return Row(
                  children: [
                    SizedBox(
                      width: w.set,
                      height: kMinTap,
                      child: Semantics(
                        button: true,
                        label: setSemantics(s.setType, label),
                        hint: 'Set options',
                        excludeSemantics: true,
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: _menu,
                          onLongPress: _menu,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: t.titleSmall?.copyWith(
                                  color:
                                      setTypeColor(context, s.setType) ??
                                      (done ? lift.done : lift.muted),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: SetCols.gap),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress: _menu,
                        child: Container(
                          height: kMinTap,
                          alignment: Alignment.centerLeft,
                          child: w.previous < SetCols.minPrevious
                              ? null
                              : Text(
                                  prevText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.bodyMedium?.copyWith(
                                    color: lift.muted,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    if (ex.hasLoad) ...[
                      input(
                        w.load,
                        TextField(
                          controller: _load,
                          focusNode: _loadFocus,
                          textAlign: TextAlign.center,
                          style: numStyle,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                            LengthLimitingTextInputFormatter(6),
                          ],
                          textInputAction: TextInputAction.next,
                          decoration: deco(
                            hint.load == null ? null : _loadText(hint.load),
                          ),
                          onChanged: (v) =>
                              _editor.setLoad(ex.id, s.id, _parseLoad(v)),
                        ),
                      ),
                      const SizedBox(width: SetCols.gap),
                    ],
                    input(
                      w.reps,
                      TextField(
                        controller: _reps,
                        focusNode: _repsFocus,
                        textAlign: TextAlign.center,
                        style: numStyle,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        textInputAction: hasEffort
                            ? TextInputAction.next
                            : TextInputAction.done,
                        // Done completes the set; _toggle decides the focus.
                        onEditingComplete: hasEffort
                            ? _effortFocus.requestFocus
                            : _toggle,
                        decoration: deco(hint.reps?.toString()),
                        onChanged: (v) =>
                            _editor.setReps(ex.id, s.id, int.tryParse(v)),
                      ),
                    ),
                    if (hasEffort) ...[
                      const SizedBox(width: SetCols.gap),
                      input(
                        w.effort,
                        TextField(
                          controller: _effort,
                          focusNode: _effortFocus,
                          textAlign: TextAlign.center,
                          style: numStyle,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                            LengthLimitingTextInputFormatter(3),
                          ],
                          textInputAction: TextInputAction.done,
                          onEditingComplete: _toggle,
                          decoration: deco(null),
                          onChanged: (v) => _editor.setRpe(
                            ex.id,
                            s.id,
                            parseEffort(v, widget.effort),
                          ),
                        ),
                      ),
                    ],
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
                );
              },
            ),
            if (widget.records.isNotEmpty || s.note != null)
              Padding(
                padding: const EdgeInsets.only(
                  left: SetCols.set + SetCols.gap,
                  bottom: Space.xs,
                ),
                child: Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final k in PrKind.values)
                      if (widget.records.contains(k))
                        Tag(
                          k.label,
                          color: lift.record,
                          icon: AppIcons.trophySolid,
                        ),
                    if (s.note case final note?)
                      Text(
                        note,
                        style: t.bodySmall?.copyWith(
                          color: lift.muted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
