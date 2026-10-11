import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
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

class ExercisePickerSheet extends ConsumerStatefulWidget {
  const ExercisePickerSheet({super.key, this.exclude = const {}});
  final Set<int> exclude;

  @override
  ConsumerState<ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<ExercisePickerSheet> {
  final _query = TextEditingController();
  final List<Exercise> _selected = [];
  String _text = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _toggle(Exercise e) => setState(() {
    final i = _selected.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      _selected.removeAt(i);
    } else {
      _selected.add(e);
    }
  });

  Future<void> _create() async {
    final created = await showExerciseEditor(
      context,
      initialName: _text.trim(),
    );
    if (created == null || !mounted) return;
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
    final list = [
      for (final e in all)
        if (!widget.exclude.contains(e.id) &&
            (q.isEmpty ||
                e.name.toLowerCase().contains(q) ||
                e.muscleGroup.label.toLowerCase().startsWith(q)))
          e,
    ];
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
                final selected = _selected.any((x) => x.id == e.id);
                return ListTile(
                  key: ValueKey(e.id),
                  title: Text(e.name),
                  subtitle: Text(
                    '${e.muscleGroup.label} · ${exerciseTypeLabel(e)}',
                  ),
                  trailing: AnimatedSwitcher(
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
              },
            ),
          ),
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

String exerciseTypeLabel(Exercise e) => e.trackingType == TrackingType.weights
    ? 'Weights'
    : switch (e.loadMode) {
        LoadMode.none => 'Bodyweight',
        LoadMode.added => 'Bodyweight + weight',
        LoadMode.assisted => 'Assisted bodyweight',
      };
