import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../data/exercise_repository.dart';
import '../../domain/muscles.dart';
import '../../domain/units.dart';
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
  final _groupKey = GlobalKey();
  late MuscleGroup? _group;
  late Set<MuscleGroup> _secondary;
  late TrackingType _type;
  late LoadMode _mode;
  late Equipment _equipment;
  late bool _perSide;
  late bool _perDumbbell;
  bool _typeLocked = false;
  bool _showNotes = false;
  bool _saving = false;
  bool _groupMissing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? widget.initialName ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _group = e?.muscleGroup;
    _secondary = {...?e?.secondaryMuscles};
    _type = e?.trackingType ?? TrackingType.weights;
    _mode = e?.loadMode ?? LoadMode.none;
    _equipment = e?.equipment ?? Equipment.none;
    _perSide = e?.perSide ?? false;
    _perDumbbell = e?.perDumbbell ?? false;
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
    final group = _group;
    if (name.isEmpty || group == null) {
      setState(() {
        _error = name.isEmpty ? 'Give it a name' : null;
        _groupMissing = group == null;
      });
      if (name.isNotEmpty) {
        Scrollable.ensureVisible(
          _groupKey.currentContext!,
          duration: Motion.of(context, Motion.medium),
        );
      }
      return;
    }
    final secondary = [
      for (final g in MuscleGroup.values)
        if (_secondary.contains(g)) g,
    ];
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(exerciseRepoProvider);
    // Only what the type offers is kept.
    final perSide = _perSide && _type != TrackingType.distance;
    final perDumbbell = _perDumbbell && _type.hasReps;
    try {
      final Exercise saved;
      final e = widget.existing;
      if (e == null) {
        saved = await repo.create(
          name: name,
          muscleGroup: group,
          trackingType: _type,
          loadMode: _mode,
          notes: _notes.text,
          equipment: _equipment,
          perSide: perSide,
          perDumbbell: perDumbbell,
          secondaryMuscles: secondary,
        );
      } else {
        await repo.update(
          e.id,
          name: name,
          muscleGroup: group,
          trackingType: _type,
          loadMode: _mode,
          notes: _notes.text,
          equipment: _equipment,
          perSide: perSide,
          perDumbbell: perDumbbell,
          secondaryMuscles: secondary,
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
    final scheme = Theme.of(context).colorScheme;
    final e = widget.existing;
    final group = _group;
    final suggested = group == null
        ? null
        : refineMuscleGroup(_name.text, group);
    final flagsChanged =
        e != null &&
        _typeLocked &&
        (e.perSide != _perSide || e.perDumbbell != _perDumbbell);
    final missingBodyweight =
        _type == TrackingType.bodyweight &&
        ref.watch(settingsProvider.select((s) => s.bodyweightKg)) == null;
    final mode = _mode.forType(_type);
    final distanceUnit = _type != TrackingType.distance
        ? null
        : DistanceUnit.of(
            ref.watch(settingsProvider.select((s) => s.weightUnit)),
            mode,
          ).label;

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
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: Space.lg),
          KeyedSubtree(key: _groupKey, child: _Label('Muscle group')),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final g in MuscleGroup.selectableWith([?e?.muscleGroup]))
                ChoiceChip(
                  label: Text(g.label),
                  selected: _group == g,
                  onSelected: (_) => setState(() {
                    _group = g;
                    _groupMissing = false;
                    _secondary.remove(g);
                  }),
                ),
            ],
          ),
          if (_groupMissing)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'Pick a muscle group',
                style: t.bodyMedium?.copyWith(color: scheme.error),
              ),
            ),
          if (group != null && group.isLegacy)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Wrap(
                spacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '${group.label} is split into single muscles now. '
                    'Pick one to refile this exercise.',
                    style: t.bodySmall?.copyWith(color: lift.rest),
                  ),
                  if (suggested != null && suggested != group)
                    ActionChip(
                      label: Text('Use ${suggested.label}'),
                      onPressed: () => setState(() {
                        _group = suggested;
                        _secondary.remove(suggested);
                      }),
                    ),
                ],
              ),
            ),
          AnimatedSize(
            duration: Motion.of(context, Motion.medium),
            curve: Motion.curve,
            alignment: Alignment.topCenter,
            child: group == null
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: Space.lg),
                      _Label('Also works'),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final g in MuscleGroup.selectableWith(
                            _secondary,
                          ))
                            if (g != group &&
                                g != MuscleGroup.fullBody &&
                                g != MuscleGroup.other)
                              FilterChip(
                                label: Text(g.label),
                                selected: _secondary.contains(g),
                                showCheckmark: false,
                                onSelected: (on) => setState(
                                  () => on
                                      ? _secondary.add(g)
                                      : _secondary.remove(g),
                                ),
                              ),
                        ],
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'Each counts as half a set in your muscle stats.',
                        style: t.bodySmall?.copyWith(color: lift.muted),
                      ),
                    ],
                  ),
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
            child: _type != TrackingType.weights
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
                            if (m.forType(_type) == m)
                              ChoiceChip(
                                label: Text(
                                  m == LoadMode.none && !_type.hasReps
                                      ? 'No weight'
                                      : m.label,
                                ),
                                selected: mode == m,
                                onSelected: (_) => setState(() => _mode = m),
                              ),
                        ],
                      ),
                      const SizedBox(height: Space.sm),
                      Text(switch ((_type, mode)) {
                        (TrackingType.duration, LoadMode.none) =>
                          'Track time only, e.g. a plank or a hang.',
                        (TrackingType.duration, _) =>
                          'Log the weight too, e.g. a weighted plank or hold.',
                        (TrackingType.distance, LoadMode.none) =>
                          'Track distance in $distanceUnit, with a time if '
                              'you like, e.g. a run or a row.',
                        (TrackingType.distance, _) =>
                          'Log the weight too, e.g. a carry or a sled push. '
                              'Distance is in $distanceUnit.',
                        (_, LoadMode.none) => 'Track reps only.',
                        (_, LoadMode.added) =>
                          'Log extra weight, e.g. a dip belt or vest.',
                        (_, LoadMode.assisted) =>
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
          _Label('Equipment'),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final q in Equipment.values)
                ChoiceChip(
                  label: Text(q.label),
                  selected: _equipment == q,
                  onSelected: (_) => setState(() {
                    _equipment = q;
                    if (q != Equipment.dumbbell) _perDumbbell = false;
                  }),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          if (_type != TrackingType.distance)
            _Toggle(
              title: 'Per side',
              subtitle: _type.hasReps
                  ? 'Reps are logged for one side, so volume counts them twice.'
                  : 'Time is logged for one side, so total time counts it '
                        'twice.',
              value: _perSide,
              onChanged: (v) => setState(() => _perSide = v),
            ),
          if (_equipment == Equipment.dumbbell && _type.hasReps)
            _Toggle(
              title: 'Per dumbbell',
              subtitle:
                  'The load is for one dumbbell, so volume counts it twice.',
              value: _perDumbbell,
              onChanged: (v) => setState(() => _perDumbbell = v),
            ),
          if (flagsChanged)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'Volume of past workouts will be recalculated.',
                style: t.bodySmall?.copyWith(color: lift.muted),
              ),
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

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: onChanged,
  );
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
