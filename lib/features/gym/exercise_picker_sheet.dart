import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/exercise_search.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'exercise_editor_sheet.dart';

/// Multi-select exercise picker. Returns the chosen exercises in tap order.
Future<List<Exercise>?> showExercisePicker(
  BuildContext context, {
  Set<int> exclude = const {},
}) => showAppSheet<List<Exercise>>(
  context,
  (_) => ExercisePickerSheet(exclude: exclude),
);

/// Picks one exercise: a tap chooses it and closes the sheet.
Future<Exercise?> pickExercise(
  BuildContext context, {
  Set<int> exclude = const {},
}) async => (await showAppSheet<List<Exercise>>(
  context,
  (_) => ExercisePickerSheet(exclude: exclude, single: true),
))?.firstOrNull;

class ExercisePickerSheet extends ConsumerStatefulWidget {
  const ExercisePickerSheet({
    super.key,
    this.exclude = const {},
    this.single = false,
  });
  final Set<int> exclude;

  /// A tap picks the exercise instead of ticking it.
  final bool single;

  @override
  ConsumerState<ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<ExercisePickerSheet> {
  final _query = TextEditingController();
  final List<Exercise> _selected = [];
  String _text = '';
  MuscleGroup? _group;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _toggle(Exercise e) {
    if (widget.single) return Navigator.pop(context, [e]);
    setState(() {
      final i = _selected.indexWhere((x) => x.id == e.id);
      if (i >= 0) {
        _selected.removeAt(i);
      } else {
        _selected.add(e);
      }
    });
  }

  Future<void> _create() async {
    final created = await showExerciseEditor(
      context,
      initialName: _text.trim(),
    );
    if (created == null || !mounted) return;
    if (widget.single) return Navigator.pop(context, [created]);
    setState(() {
      _selected.add(created);
      _query.clear();
      _text = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(exercisesProvider).value ?? const <Exercise>[];
    final lift = LiftColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final q = _text.trim().toLowerCase();
    final available = [
      for (final e in all)
        if (!widget.exclude.contains(e.id)) e,
    ];
    final groups = {for (final e in available) e.muscleGroup};
    // A filter whose exercises are all gone no longer applies.
    final group = groups.contains(_group) ? _group : null;
    final ranked = rankExercises(
      available,
      query: q,
      group: group,
      usage: ref.watch(exerciseUsageProvider).value ?? const {},
    );
    final list = ranked.exercises;
    final exact = all.any((e) => e.name.toLowerCase() == q);
    final showCreate = q.isNotEmpty && !exact;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: TextField(
              controller: _query,
              autofocus: all.isNotEmpty,
              onChanged: (v) => setState(() => _text = v),
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'Search or create exercise',
                prefixIcon: AppIcon(AppIcons.search),
              ),
            ),
          ),
          if (groups.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.sm,
              ),
              child: Row(
                spacing: Space.sm,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: group == null,
                    onSelected: (_) => setState(() => _group = null),
                  ),
                  for (final g in MuscleGroup.values)
                    if (groups.contains(g))
                      ChoiceChip(
                        label: Text(g.label),
                        selected: group == g,
                        onSelected: (_) => setState(() => _group = g),
                      ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length + (showCreate || all.isEmpty ? 1 : 0),
              itemBuilder: (context, i) {
                if (showCreate || all.isEmpty) {
                  if (i == 0) {
                    return ListTile(
                      leading: AppIcon(AppIcons.plus, color: scheme.primary),
                      title: Text(
                        q.isEmpty
                            ? 'Create exercise'
                            : "Create “${_text.trim()}”",
                        style: TextStyle(color: scheme.primary),
                      ),
                      onTap: _create,
                    );
                  }
                  i--;
                }
                final e = list[i];
                final header = ranked.recent == 0
                    ? null
                    : i == 0
                    ? 'Recent'
                    : i == ranked.recent
                    ? 'All exercises'
                    : null;
                final selected = _selected.any((x) => x.id == e.id);
                final tile = ListTile(
                  key: ValueKey(e.id),
                  title: Text(e.name),
                  subtitle: Text(
                    '${e.muscleGroup.label} · ${exerciseSubtitle(e)}',
                  ),
                  trailing: widget.single
                      ? null
                      : AnimatedSwitcher(
                          duration: Motion.of(context, Motion.fast),
                          child: selected
                              ? AppIcon(
                                  AppIcons.checkSolid,
                                  key: const ValueKey(true),
                                  color: scheme.primary,
                                )
                              : AppIcon(
                                  AppIcons.box,
                                  key: const ValueKey(false),
                                  color: lift.muted,
                                ),
                        ),
                  onTap: () => _toggle(e),
                );
                if (header == null) return tile;
                return Column(
                  key: ValueKey(e.id),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [SectionLabel(header), tile],
                );
              },
            ),
          ),
          if (!widget.single)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, List.of(_selected)),
                    child: Text(
                      _selected.isEmpty
                          ? 'Select exercises'
                          : 'Add ${_selected.length}',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Equipment and type for a list subtitle, e.g. "Barbell" or "Bodyweight".
String exerciseSubtitle(Exercise e) => [
  if (e.equipment != Equipment.none) e.equipment.label,
  if (e.equipment == Equipment.none ||
      e.trackingType == TrackingType.bodyweight)
    exerciseTypeLabel(e),
].join(' · ');

String exerciseTypeLabel(Exercise e) => e.trackingType == TrackingType.weights
    ? 'Weights'
    : switch (e.loadMode) {
        LoadMode.none => 'Bodyweight',
        LoadMode.added => 'Bodyweight + weight',
        LoadMode.assisted => 'Assisted bodyweight',
      };
