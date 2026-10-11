import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../data/exercise_repository.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';

/// Opens the create/edit exercise sheet. Returns the saved exercise.
Future<Exercise?> showExerciseEditor(
  BuildContext context, {
  Exercise? existing,
  String? initialName,
}) => showAppSheet<Exercise>(
  context,
  (_) => ExerciseEditorSheet(existing: existing, initialName: initialName),
);

class ExerciseEditorSheet extends ConsumerStatefulWidget {
  const ExerciseEditorSheet({super.key, this.existing, this.initialName});
  final Exercise? existing;
  final String? initialName;

  @override
  ConsumerState<ExerciseEditorSheet> createState() =>
      _ExerciseEditorSheetState();
}

class _ExerciseEditorSheetState extends ConsumerState<ExerciseEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late MuscleGroup _group;
  late TrackingType _type;
  late LoadMode _mode;
  bool _typeLocked = false;
  bool _showNotes = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? widget.initialName ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _group = e?.muscleGroup ?? MuscleGroup.chest;
    _type = e?.trackingType ?? TrackingType.weights;
    _mode = e?.loadMode ?? LoadMode.none;
    _showNotes = (e?.notes ?? '').isNotEmpty;
    if (e != null) {
      ref.read(exerciseRepoProvider).hasLoggedSets(e.id).then((used) {
        if (mounted && used) setState(() => _typeLocked = true);
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = ExerciseRepository.normalizeName(_name.text);
    if (name.isEmpty) {
      setState(() => _error = 'Give it a name');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(exerciseRepoProvider);
    try {
      final Exercise saved;
      final e = widget.existing;
      if (e == null) {
        saved = await repo.create(
          name: name,
          muscleGroup: _group,
          trackingType: _type,
          loadMode: _mode,
          notes: _notes.text,
        );
      } else {
        await repo.update(
          e.id,
          name: name,
          muscleGroup: _group,
          trackingType: _type,
          loadMode: _mode,
          notes: _notes.text,
        );
        saved = (await repo.getById(e.id))!;
      }
      if (mounted) Navigator.pop(context, saved);
    } on DuplicateNameException {
      setState(() {
        _saving = false;
        _error = 'You already have an exercise with this name';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final lift = LiftColors.of(context);
    final missingBodyweight =
        _type == TrackingType.bodyweight &&
        ref.watch(settingsProvider.select((s) => s.bodyweightKg)) == null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.existing == null ? 'New exercise' : 'Edit exercise',
            style: t.headlineSmall,
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _name,
            autofocus: widget.existing == null && widget.initialName == null,
            textCapitalization: TextCapitalization.words,
            maxLength: 60,
            decoration: InputDecoration(
              hintText: 'Name, e.g. Bench press',
              errorText: _error,
              counterText: '',
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: Space.lg),
          _Label('Muscle group'),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final g in MuscleGroup.selectableWith([
                ?widget.existing?.muscleGroup,
              ]))
                ChoiceChip(
                  label: Text(g.label),
                  selected: _group == g,
                  onSelected: (_) => setState(() => _group = g),
                ),
            ],
          ),
          const SizedBox(height: Space.lg),
          _Label('Type'),
          SegmentedButton<TrackingType>(
            showSelectedIcon: false,
            segments: [
              for (final v in TrackingType.values)
                ButtonSegment(
                  value: v,
                  label: Text(v.label),
                  enabled: !_typeLocked || v == _type,
                ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          if (_typeLocked)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'Type is locked because this exercise has logged sets.',
                style: t.bodySmall?.copyWith(color: lift.muted),
              ),
            ),
          AnimatedSize(
            duration: Motion.of(context, Motion.medium),
            curve: Motion.curve,
            alignment: Alignment.topCenter,
            child: _type == TrackingType.bodyweight
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: Space.lg),
                      _Label('Load'),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final m in LoadMode.values)
                            ChoiceChip(
                              label: Text(m.label),
                              selected: _mode == m,
                              onSelected: (_) => setState(() => _mode = m),
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.sm),
                      Text(switch (_mode) {
                        LoadMode.none => 'Track reps only.',
                        LoadMode.added =>
                          'Log extra weight, e.g. a dip belt or vest.',
                        LoadMode.assisted =>
                          'Log assistance, e.g. a band or assisted machine.',
                      }, style: t.bodySmall?.copyWith(color: lift.muted)),
                      if (missingBodyweight) ...[
                        const SizedBox(height: Space.sm),
                        Text(
                          'Tip: set your body weight in Settings to get '
                          'volume and e1RM for bodyweight exercises.',
                          style: t.bodySmall?.copyWith(color: lift.rest),
                        ),
                      ],
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: Space.lg),
          if (_showNotes)
            TextField(
              controller: _notes,
              minLines: 1,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'Notes (seat height, grip, …)',
                counterText: '',
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showNotes = true),
                icon: const AppIcon(AppIcons.note, size: IconSizes.sm),
                label: const Text('Add note'),
              ),
            ),
          const SizedBox(height: Space.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(widget.existing == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.sm),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: LiftColors.of(context).muted, letterSpacing: 0.8),
    ),
  );
}
