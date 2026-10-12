import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/loading.dart';
import '../../domain/records.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import '../../widgets/periodic_builder.dart';
import 'set_menu_sheet.dart';
import 'workout_controller.dart';

/// Column widths shared by the header and rows, at text scale 1.
abstract final class SetCols {
  static const double set = 32;
  static const double load = 76;
  static const double reps = 64;
  static const double distance = 64;
  static const double effort = 48;
  static const double check = 48;
  static const double gap = Space.sm;

  /// The start and stop button of a time set. It doesn't scale.
  static const double timer = kCompactTap;

  /// Below this the Previous column is left empty.
  static const double minPrevious = 40;

  /// A distance row has up to four inputs, so its text may get this small.
  static const double minDistanceScale = 0.75;

  /// Fits the columns into [width]. The inputs grow with [textScale] and take
  /// their room from Previous. Only once that is used up do the inputs, and
  /// their text with them, shrink.
  ///
  /// `reps` is the reps column, or the time column of a time or distance
  /// exercise. [distance] adds the distance column before it and [timer] the
  /// stopwatch button after it.
  static SetWidths fit(
    double width, {
    required double textScale,
    required bool load,
    bool effort = false,
    bool distance = false,
    bool timer = false,
  }) {
    final scale = textScale.clamp(1.0, 2.0);
    final set = SetCols.set * math.min(scale, 1.5);
    final gaps =
        gap *
        (1 +
            (load ? 1 : 0) +
            (effort ? 1 : 0) +
            (distance ? 1 : 0) +
            (timer ? 1 : 0));
    final room = math.max(
      0.0,
      width - set - check - gaps - (timer ? SetCols.timer : 0),
    );
    final wanted =
        ((load ? SetCols.load : 0.0) +
            (distance ? SetCols.distance : 0.0) +
            reps +
            (effort ? SetCols.effort : 0.0)) *
        scale;
    final f = wanted <= room ? 1.0 : room / wanted;
    return SetWidths(
      set: set,
      previous: room - wanted * f,
      load: SetCols.load * scale * f,
      distance: SetCols.distance * scale * f,
      reps: reps * scale * f,
      effort: SetCols.effort * scale * f,
      inputScale: math.max(distance ? minDistanceScale : 1.0, scale * f),
    );
  }

  /// [fit] for the columns of [exercise] at the text scale of [context].
  static SetWidths of(
    BuildContext context,
    double width, {
    required DraftExercise exercise,
    required bool effort,
  }) => fit(
    width,
    textScale: MediaQuery.textScalerOf(context).scale(100) / 100,
    load: exercise.hasLoad,
    effort: effort,
    distance: exercise.type == TrackingType.distance,
    timer: exercise.type == TrackingType.duration,
  );
}

class SetWidths {
  const SetWidths({
    required this.set,
    required this.previous,
    required this.load,
    required this.distance,
    required this.reps,
    required this.effort,
    required this.inputScale,
  });

  final double set;
  final double previous;
  final double load;
  final double distance;

  /// Reps, or the time of a time or distance exercise.
  final double reps;
  final double effort;

  /// Largest text scale that still fits the input columns.
  final double inputScale;
}

String loadHeader(DraftExercise ex, WeightUnit unit) {
  final u = unit.label.toUpperCase();
  if (ex.type != TrackingType.bodyweight) return u;
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
            exercise: exercise,
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
              if (exercise.type == TrackingType.distance) ...[
                cell(
                  w.distance,
                  DistanceUnit.of(unit, exercise.mode).label.toUpperCase(),
                ),
                const SizedBox(width: SetCols.gap),
              ],
              cell(w.reps, exercise.type.hasReps ? 'REPS' : 'TIME'),
              if (exercise.type == TrackingType.duration)
                const SizedBox(width: SetCols.gap + SetCols.timer),
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

/// Puts the colons into a time as its digits are typed, see [hmsInput].
class _HmsFormatter extends TextInputFormatter {
  const _HmsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = hmsInput(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
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
    this.effort = EffortMode.off,
    this.records = const {},
    this.bar,
  });

  final int workoutId;
  final DraftExercise exercise;
  final int index;
  final WeightUnit unit;

  /// Adds the RPE or RIR column.
  final EffortMode effort;

  /// Records this set beats.
  final Set<PrKind> records;

  /// The bar of a barbell exercise, to show the plates per side for a weight.
  final BarSetup? bar;

  @override
  ConsumerState<SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<SetRow> {
  /// Mounted rows by set id, so a row can hand the focus to the next one.
  static final _mounted = <int, _SetRowState>{};

  late final TextEditingController _load;
  late final TextEditingController _reps;
  late final TextEditingController _time;
  late final TextEditingController _distance;
  late final TextEditingController _effort;
  final _loadFocus = FocusNode();
  final _repsFocus = FocusNode();
  final _timeFocus = FocusNode();
  final _distanceFocus = FocusNode();
  final _effortFocus = FocusNode();
  late final int _setId = _set.id;

  WorkoutSet get _set => widget.exercise.sets[widget.index];
  bool get _assisted =>
      widget.exercise.type == TrackingType.bodyweight &&
      widget.exercise.mode == LoadMode.assisted;
  DistanceUnit get _du =>
      DistanceUnit.of(widget.unit, widget.exercise.mode);

  WorkoutEditor get _editor =>
      ref.read(workoutEditorProvider(widget.workoutId).notifier);

  @override
  void initState() {
    super.initState();
    _load = TextEditingController(text: _loadText(_set.loadKg));
    _reps = TextEditingController(text: _set.reps?.toString() ?? '');
    _time = TextEditingController(text: _timeText(_set.durationSeconds));
    _distance = TextEditingController(text: _distanceText(_set.distanceM));
    _effort = TextEditingController(text: fmtEffort(_set.rpe, widget.effort));
    for (final f in _focusNodes) {
      f.addListener(_onBlur);
    }
    _mounted[_setId] = this;
  }

  List<FocusNode> get _focusNodes => [
    _loadFocus,
    _repsFocus,
    _timeFocus,
    _distanceFocus,
    _effortFocus,
  ];

  bool get _typing => _focusNodes.any((f) => f.hasFocus);

  FocusNode _focusOf(SetField field) => switch (field) {
    SetField.load => _loadFocus,
    SetField.reps => _repsFocus,
    SetField.time => _timeFocus,
    SetField.distance => _distanceFocus,
  };

  /// Plates per side for the entered or hinted weight of a barbell set.
  String? _plates() {
    final bar = widget.bar;
    if (bar == null || widget.index >= widget.exercise.sets.length) return null;
    final kg = _set.loadKg ?? widget.exercise.hintFor(widget.index).load;
    return kg == null ? null : fmtPlates(bar.load(kg), widget.unit);
  }

  void _onBlur() {
    if (!_typing) _editor.flush();
    // The plates line comes and goes with the focus.
    if (widget.bar != null && mounted) setState(() {});
    if (widget.index >= widget.exercise.sets.length) return;
    // Shows what was stored, e.g. 7.5 for a typed 7.3 and 1:30 for 90.
    void show(FocusNode focus, TextEditingController c, String text) {
      if (!focus.hasFocus && c.text != text) c.text = text;
    }

    show(_effortFocus, _effort, fmtEffort(_set.rpe, widget.effort));
    show(_timeFocus, _time, _timeText(_set.durationSeconds));
  }

  String _timeText(int? seconds) => seconds == null ? '' : fmtHms(seconds);

  String _distanceText(double? metres) =>
      metres == null ? '' : fmtDistance(metres, _du);

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
    if (parseHms(_time.text) != s.durationSeconds) {
      _time.text = _timeText(s.durationSeconds);
    }
    final metres = parseDistance(_distance.text, _du);
    final sameDistance = metres == null || s.distanceM == null
        ? metres == s.distanceM
        : (metres - s.distanceM!).abs() < 0.005;
    if (!sameDistance ||
        _du != DistanceUnit.of(old.unit, old.exercise.mode)) {
      _distance.text = _distanceText(s.distanceM);
    }
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
    _time.dispose();
    _distance.dispose();
    _effort.dispose();
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _toggle() {
    // Only carry on typing if the keyboard is already up.
    final typing = _typing;
    // A set being timed is stopped and takes that time.
    final timed = ref.read(setStopwatchProvider.notifier).stop(_set.id);
    if (timed != null) {
      _editor.setDuration(widget.exercise.id, _set.id, timed);
    }
    final result = _editor.toggleDone(widget.exercise.id, _set.id);
    switch (result) {
      case CompleteResult.ok:
        HapticFeedback.lightImpact();
        final draft = ref.read(workoutEditorProvider(widget.workoutId)).value;
        final next = typing && draft != null
            ? nextFocus(draft, widget.exercise.id, widget.index)
            : null;
        final row = next == null ? null : _mounted[next.setId];
        if (row == null) {
          FocusScope.of(context).unfocus();
        } else {
          row._focusOf(next!.field).requestFocus();
        }
      case CompleteResult.needsReps:
        _repsFocus.requestFocus();
      case CompleteResult.needsWeight:
        _loadFocus.requestFocus();
      case CompleteResult.needsTime:
        _timeFocus.requestFocus();
      case CompleteResult.needsDistance:
        _distanceFocus.requestFocus();
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
        plates: _plates(),
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
    final timedHint = ex.timedHintFor(widget.index);
    // When the stopwatch of this set was started, while it runs.
    final timing = ex.type != TrackingType.duration
        ? null
        : ref.watch(
            setStopwatchProvider.select(
              (t) => t?.setId == _setId ? t?.startedAt : null,
            ),
          );
    final label = setLabels(ex.sets.map((s) => s.setType))[widget.index];
    final prev = ex.previousFor(widget.index);
    // While typing in a barbell set, its plates show under the row.
    final plates = _typing && !done ? _plates() : null;

    final prevText = prev == null
        ? '–'
        : fmtSet(
            type: ex.type,
            mode: ex.mode,
            loadKg: prev.loadKg,
            reps: prev.reps,
            durationSeconds: prev.durationSeconds,
            distanceM: prev.distanceM,
            unit: widget.unit,
          );

    final fieldFill = done ? Colors.transparent : lift.raised;
    final numStyle = t.titleMedium?.copyWith(fontFeatures: Fonts.tabular);

    // A suggested increase is tinted, so it doesn't pass for last time's load.
    InputDecoration deco(String? hintText, {bool increase = false}) =>
        InputDecoration(
          hintText: hintText,
          hintStyle: increase ? TextStyle(color: scheme.primary) : null,
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
                  exercise: ex,
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
                            increase: hint.increase,
                          ),
                          onChanged: (v) =>
                              _editor.setLoad(ex.id, s.id, _parseLoad(v)),
                        ),
                      ),
                      const SizedBox(width: SetCols.gap),
                    ],
                    if (ex.type == TrackingType.distance) ...[
                      input(
                        w.distance,
                        TextField(
                          controller: _distance,
                          focusNode: _distanceFocus,
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
                          decoration: deco(_distanceText(timedHint.metres)),
                          onChanged: (v) => _editor.setDistance(
                            ex.id,
                            s.id,
                            parseDistance(v, _du),
                          ),
                        ),
                      ),
                      const SizedBox(width: SetCols.gap),
                    ],
                    if (ex.type.hasReps)
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
                          decoration: deco(
                            hint.reps?.toString(),
                            increase: hint.increase,
                          ),
                          onChanged: (v) =>
                              _editor.setReps(ex.id, s.id, int.tryParse(v)),
                        ),
                      )
                    else
                      input(
                        w.reps,
                        timing != null
                            ? PeriodicBuilder(
                                period: const Duration(seconds: 1),
                                anchor: timing,
                                builder: (_) => InputDecorator(
                                  decoration: deco(null),
                                  child: Text(
                                    fmtHms(
                                      DateTime.now()
                                          .difference(timing)
                                          .inSeconds,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    style: numStyle?.copyWith(
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                              )
                            : TextField(
                                controller: _time,
                                focusNode: _timeFocus,
                                textAlign: TextAlign.center,
                                style: numStyle,
                                keyboardType: TextInputType.number,
                                inputFormatters: const [_HmsFormatter()],
                                textInputAction: hasEffort
                                    ? TextInputAction.next
                                    : TextInputAction.done,
                                onEditingComplete: hasEffort
                                    ? _effortFocus.requestFocus
                                    : _toggle,
                                decoration: deco(
                                  timedHint.seconds == null
                                      ? null
                                      : fmtHms(timedHint.seconds!),
                                ),
                                onChanged: (v) => _editor.setDuration(
                                  ex.id,
                                  s.id,
                                  parseHms(v),
                                ),
                              ),
                      ),
                    if (ex.type == TrackingType.duration) ...[
                      const SizedBox(width: SetCols.gap),
                      SizedBox(
                        width: SetCols.timer,
                        height: kMinTap,
                        child: done
                            ? null
                            : IconButton(
                                tooltip: timing == null
                                    ? 'Start timer'
                                    : 'Stop timer',
                                padding: EdgeInsets.zero,
                                // Stopping completes the set with its time.
                                onPressed: timing == null
                                    ? () => ref
                                          .read(setStopwatchProvider.notifier)
                                          .start(s.id)
                                    : _toggle,
                                icon: timing == null
                                    ? AppIcon(
                                        AppIcons.playSolid,
                                        size: IconSizes.sm,
                                        color: scheme.onSurfaceVariant,
                                      )
                                    : AppIcon(
                                        AppIcons.stopSolid,
                                        size: IconSizes.sm,
                                        color: scheme.primary,
                                      ),
                              ),
                      ),
                    ],
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
            if (plates != null)
              Padding(
                padding: const EdgeInsets.only(
                  left: SetCols.set + SetCols.gap,
                  bottom: Space.xs,
                ),
                child: Text(
                  'Per side: $plates',
                  style: t.bodySmall?.copyWith(color: lift.muted),
                ),
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
