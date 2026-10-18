import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../domain/history.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import '../workout/workout_actions.dart';
import 'month_calendar.dart';
import 'workout_day_sheet.dart';

/// Finished workouts that include an exercise; follows the history.
final _exerciseWorkoutsProvider = FutureProvider.autoDispose
    .family<Set<int>, int>((ref, exerciseId) {
      ref.watch(historyProvider);
      return ref.read(workoutRepoProvider).workoutIdsWithExercise(exerciseId);
    });

/// Search and view state. It outlives the screen, which is rebuilt when the
/// window crosses the list-detail breakpoint.
class _HistoryView {
  String query = '';
  bool searching = false;
  bool calendar = false;
  WorkoutTemplate? template;
  Exercise? exercise;
}

final _historyViewProvider = Provider((ref) => _HistoryView());

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key, this.selectedId});

  /// The workout open in the detail pane beside the list, if any.
  final int? selectedId;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final _view = ref.read(_historyViewProvider);
  late final TextEditingController _query = TextEditingController(
    text: _view.query,
  )..addListener(() => _view.query = _query.text);

  bool get _searching => _view.searching;
  set _searching(bool v) => _view.searching = v;
  bool get _calendar => _view.calendar;
  set _calendar(bool v) => _view.calendar = v;
  WorkoutTemplate? get _template => _view.template;
  set _template(WorkoutTemplate? v) => _view.template = v;
  Exercise? get _exercise => _view.exercise;
  set _exercise(Exercise? v) => _view.exercise = v;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _clearFilters() => setState(() {
    _query.clear();
    _template = null;
    _exercise = null;
  });

  Future<void> _pickTemplate() async {
    final all = ref.read(templatesProvider).value ?? const [];
    final picked = await showAppSheet<WorkoutTemplate>(
      context,
      (_) => _PickSheet<WorkoutTemplate>(
        title: 'Template',
        items: [for (final d in all) d.template],
        label: (t) => t.name,
      ),
    );
    if (picked != null) setState(() => _template = picked);
  }

  Future<void> _pickExercise() async {
    final active = ref.read(exercisesProvider).value ?? const <Exercise>[];
    final archived = await ref.read(archivedExercisesProvider.future);
    if (!mounted) return;
    final picked = await showAppSheet<Exercise>(
      context,
      (_) => _PickSheet<Exercise>(
        title: 'Exercise',
        items: [...active, ...archived],
        label: (e) => e.name,
        searchable: true,
      ),
    );
    if (picked != null) setState(() => _exercise = picked);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(historyProvider).value;
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final firstDay = ref.watch(
      settingsProvider.select((s) => s.firstDayOfWeek),
    );
    final exerciseIds = _exercise == null
        ? null
        : ref.watch(_exerciseWorkoutsProvider(_exercise!.id)).value;
    final list = all == null || (_exercise != null && exerciseIds == null)
        ? null
        : filterHistory(
            all,
            query: _query.text,
            templateId: _template?.id,
            exerciseWorkoutIds: exerciseIds,
          );

    Widget body;
    if (list == null) {
      body = const SizedBox.shrink();
    } else if (all!.isEmpty) {
      body = EmptyState(
        icon: AppIcons.history,
        title: 'No workouts yet',
        message: 'Finished workouts show up here.',
        action: OutlinedButton(
          onPressed: () => logPastWorkout(context, ref),
          child: const Text('Log past workout'),
        ),
      );
    } else if (_calendar) {
      body = MonthCalendar(
        workouts: list,
        firstDay: firstDay,
        onTapDay: (day) => showWorkoutDaySheet(
          context,
          day: day,
          history: list,
          workoutPath: (id) => '/history/$id',
        ),
      );
    } else if (list.isEmpty) {
      body = EmptyState(
        icon: AppIcons.search,
        title: 'No matching workouts',
        message: 'Try another name or clear the filters.',
        action: TextButton(
          onPressed: _clearFilters,
          child: const Text('Clear filters'),
        ),
      );
    } else {
      final monthFmt = DateFormat('MMMM y');
      final rows = <Object>[];
      String? month;
      for (final w in list) {
        final m = monthFmt.format(w.startedAt);
        if (m != month) {
          rows.add(m);
          month = m;
        }
        rows.add(w);
      }
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final r = rows[i];
          if (r is String) return SectionLabel(r);
          final w = r as Workout;
          return Padding(
            key: ValueKey(w.id),
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: WorkoutSummaryCard(
              workout: w,
              unit: unit,
              selected: w.id == widget.selectedId,
              onTap: () => context.go('/history/${w.id}'),
            ),
          );
        },
      );
    }

    final hasHistory = all?.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (hasHistory) ...[
            IconButton(
              tooltip: _searching ? 'Close search' : 'Search',
              onPressed: () => setState(() {
                if (_searching) _clearFilters();
                _searching = !_searching;
              }),
              icon: AppIcon(_searching ? AppIcons.close : AppIcons.search),
            ),
            IconButton(
              tooltip: _calendar ? 'Show list' : 'Show calendar',
              onPressed: () => setState(() => _calendar = !_calendar),
              icon: AppIcon(_calendar ? AppIcons.list : AppIcons.calendar),
            ),
          ],
          IconButton(
            tooltip: 'Log past workout',
            onPressed: () => logPastWorkout(context, ref),
            icon: const AppIcon(AppIcons.plus),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searching && hasHistory)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _query,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search by name',
                      prefixIcon: AppIcon(AppIcons.search),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      _FilterChip(
                        label: 'Template',
                        value: _template?.name,
                        onTap: _pickTemplate,
                        onClear: () => setState(() => _template = null),
                      ),
                      _FilterChip(
                        label: 'Exercise',
                        value: _exercise?.name,
                        onTap: _pickExercise,
                        onClear: () => setState(() => _exercise = null),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });
  final String label;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => value == null
      ? ActionChip(label: Text(label), onPressed: onTap)
      : InputChip(
          label: Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis),
          selected: true,
          onPressed: onTap,
          onDeleted: onClear,
          deleteButtonTooltipMessage: 'Clear $label',
        );
}

/// Pick one item from a list, optionally searchable. Pops the chosen item.
class _PickSheet<T> extends StatefulWidget {
  const _PickSheet({
    required this.title,
    required this.items,
    required this.label,
    this.searchable = false,
  });
  final String title;
  final List<T> items;
  final String Function(T) label;
  final bool searchable;

  @override
  State<_PickSheet<T>> createState() => _PickSheetState<T>();
}

class _PickSheetState<T> extends State<_PickSheet<T>> {
  String _text = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final shown = [
      for (final i in widget.items)
        if (widget.label(i).toLowerCase().contains(_text.toLowerCase())) i,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
          child: Text(widget.title, style: t.titleLarge),
        ),
        if (widget.searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: TextField(
              onChanged: (v) => setState(() => _text = v),
              decoration: const InputDecoration(
                hintText: 'Search',
                prefixIcon: AppIcon(AppIcons.search),
              ),
            ),
          ),
        if (widget.items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Text(
              'Nothing to choose from yet.',
              style: t.bodyMedium?.copyWith(
                color: LiftColors.of(context).muted,
              ),
            ),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final i in shown)
                ListTile(
                  title: Text(widget.label(i)),
                  onTap: () => Navigator.pop(context, i),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.sm),
      ],
    );
  }
}

class WorkoutSummaryCard extends StatelessWidget {
  const WorkoutSummaryCard({
    super.key,
    required this.workout,
    required this.unit,
    this.selected = false,
    this.onTap,
  });

  final Workout workout;
  final WeightUnit unit;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    final w = workout;
    final duration = (w.endedAt ?? w.startedAt).difference(w.startedAt);
    final parts = [
      fmtDuration(duration),
      '${w.totalSets} ${w.totalSets == 1 ? 'set' : 'sets'}',
      if (w.totalVolumeKg > 0) fmtVolume(w.totalVolumeKg, unit),
    ];
    return FlatCard(
      onTap: onTap,
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(
                  DateFormat('EEE').format(w.startedAt).toUpperCase(),
                  style: t.labelSmall?.copyWith(color: muted),
                ),
                Text(
                  '${w.startedAt.day}',
                  style: t.headlineSmall?.copyWith(fontFeatures: Fonts.tabular),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.name, style: t.titleMedium),
                const SizedBox(height: 2),
                Text(
                  parts.join(' · '),
                  style: t.bodyMedium?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          AppIcon(AppIcons.chevronRight, color: muted),
        ],
      ),
    );
  }
}
