import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../data/template_repository.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'exercise_editor_sheet.dart';
import 'exercise_picker_sheet.dart';
import 'template_folders.dart';

enum GymTab { exercises, templates }

/// The segment lives in the URL (`/gym?tab=templates`) so links and the
/// restored tab stack land on the right list.
class GymScreen extends ConsumerWidget {
  const GymScreen({super.key, this.tab = GymTab.exercises, this.selectedId});
  final GymTab tab;

  /// The exercise open in the detail pane beside the list, if any.
  final int? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The empty state has its own create button.
    final isEmpty =
        switch (tab) {
          GymTab.exercises => ref.watch(exercisesProvider).value?.isEmpty,
          GymTab.templates => ref.watch(templatesProvider).value?.isEmpty,
        } ??
        true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gym'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kMinTap + Space.md),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<GymTab>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: GymTab.exercises,
                    label: _SegmentLabel('Exercises'),
                  ),
                  ButtonSegment(
                    value: GymTab.templates,
                    label: _SegmentLabel('Templates'),
                  ),
                ],
                selected: {tab},
                onSelectionChanged: (s) => context.go(
                  s.first == GymTab.templates ? '/gym?tab=templates' : '/gym',
                ),
              ),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: tab.index,
        children: [
          TickerMode(
            enabled: tab == GymTab.exercises,
            child: _ExerciseList(selectedId: selectedId),
          ),
          TickerMode(
            enabled: tab == GymTab.templates,
            child: const _TemplateList(),
          ),
        ],
      ),
      floatingActionButton: isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'gym-fab',
              onPressed: () => tab == GymTab.exercises
                  ? showExerciseEditor(context)
                  : context.push('/gym/template/new'),
              icon: const AppIcon(AppIcons.plus),
              label: Text(tab == GymTab.exercises ? 'Exercise' : 'Template'),
            ),
    );
  }
}

/// Shrinks instead of wrapping: the app bar has no room for a second line.
class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(text, softWrap: false));
}

class _ExerciseList extends ConsumerWidget {
  const _ExerciseList({this.selectedId});
  final int? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(exercisesProvider);
    final list = async.value;
    if (list == null) return const SizedBox.shrink();
    if (list.isEmpty) {
      return EmptyState(
        icon: AppIcons.dumbbell,
        title: 'No exercises yet',
        message:
            'Add the exercises you do. You can also create them '
            'on the fly during a workout.',
        action: FilledButton.icon(
          onPressed: () => showExerciseEditor(context),
          icon: const AppIcon(AppIcons.plus),
          label: const Text('Create exercise'),
        ),
      );
    }

    final groups = <MuscleGroup, List<Exercise>>{};
    for (final e in list) {
      (groups[e.muscleGroup] ??= []).add(e);
    }
    final rows = <Object>[];
    for (final g in MuscleGroup.values) {
      final items = groups[g];
      if (items == null) continue;
      rows
        ..add(g)
        ..addAll(items);
    }
    rows.add(_ArchivedLink(selectedId: selectedId));
    final scheme = Theme.of(context).colorScheme;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final r = rows[i];
        if (r is MuscleGroup) return SectionLabel(r.label);
        if (r is Exercise) {
          return ListTile(
            key: ValueKey(r.id),
            title: Text(r.name),
            subtitle: Text(exerciseSubtitle(r)),
            trailing: const AppIcon(AppIcons.chevronRight),
            selected: r.id == selectedId,
            selectedColor: scheme.onSurface,
            selectedTileColor: scheme.primaryContainer,
            onTap: () => context.go('/gym/exercise/${r.id}'),
          );
        }
        return r as Widget;
      },
    );
  }
}

class _ArchivedLink extends ConsumerWidget {
  const _ArchivedLink({this.selectedId});
  final int? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(archivedExercisesProvider).value ?? const [];
    if (archived.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.lg),
      child: ExpansionTile(
        title: Text('Archived (${archived.length})'),
        shape: const Border(),
        collapsedShape: const Border(),
        children: [
          for (final e in archived)
            ListTile(
              title: Text(
                e.name,
                style: TextStyle(color: LiftColors.of(context).muted),
              ),
              trailing: TextButton(
                onPressed: () =>
                    ref.read(exerciseRepoProvider).setArchived(e.id, false),
                child: const Text('Restore'),
              ),
              selected: e.id == selectedId,
              selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
              onTap: () => context.go('/gym/exercise/${e.id}'),
            ),
        ],
      ),
    );
  }
}

class _TemplateList extends ConsumerStatefulWidget {
  const _TemplateList();

  @override
  ConsumerState<_TemplateList> createState() => _TemplateListState();
}

class _TemplateListState extends ConsumerState<_TemplateList> {
  List<TemplateDetail>? _optimistic;

  /// Reorders within one section; templates elsewhere keep their place.
  void _reorder(
    List<TemplateDetail> all,
    List<TemplateDetail> section,
    int from,
    int to,
  ) {
    final moved = [...section];
    moved.insert(to, moved.removeAt(from));
    final ids = reorderWithin(
      [for (final d in all) d.template.id],
      [for (final d in section) d.template.id],
      [for (final d in moved) d.template.id],
    );
    final byId = {for (final d in all) d.template.id: d};
    setState(() => _optimistic = [for (final id in ids) byId[id]!]);
    ref.read(templateRepoProvider).reorder(ids).whenComplete(() {
      if (mounted) setState(() => _optimistic = null);
    });
  }

  Widget _section(List<TemplateDetail> all, List<TemplateDetail> section) =>
      SliverReorderableList(
        itemCount: section.length,
        onReorderItem: (from, to) => _reorder(all, section, from, to),
        proxyDecorator: (child, _, animation) => AnimatedBuilder(
          animation: animation,
          builder: (_, child) => Material(
            elevation: Curves.easeInOut.transform(animation.value) * 6,
            color: Colors.transparent,
            child: child,
          ),
          child: child,
        ),
        itemBuilder: (context, i) {
          final d = section[i];
          return Padding(
            key: ValueKey(d.template.id),
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: TemplateCard(
              detail: d,
              onTap: () => context.push('/gym/template/${d.template.id}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TemplateMenu(template: d.template),
                  ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.all(Space.md),
                      child: AppIcon(
                        AppIcons.drag,
                        color: LiftColors.of(context).muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final stream = ref.watch(templatesProvider).value;
    if (stream == null) return const SizedBox.shrink();
    final templates = _optimistic ?? stream;
    if (templates.isEmpty) {
      return EmptyState(
        icon: AppIcons.notepad,
        title: 'No templates yet',
        message:
            'A template is a reusable workout, like “Push” or “Legs”. '
            'Start it from Home with one tap.',
        action: FilledButton.icon(
          onPressed: () => context.push('/gym/template/new'),
          icon: const AppIcon(AppIcons.plus),
          label: const Text('Create template'),
        ),
      );
    }
    final folders = ref.watch(templateFoldersProvider).value ?? const [];
    final sections = groupTemplates(templates, folders);
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: LiftColors.of(context).muted);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
          sliver: _section(templates, sections.unfiled),
        ),
        for (final s in sections.folders) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.sm, 0),
            sliver: SliverToBoxAdapter(
              child: FolderHeader(
                folder: s.folder,
                count: s.templates.length,
                onToggle: () => toggleFolder(ref, s.folder),
                trailing: FolderMenu(folder: s.folder, folders: folders),
              ),
            ),
          ),
          if (!s.folder.isCollapsed)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              sliver: s.templates.isEmpty
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.sm,
                          0,
                          Space.sm,
                          Space.md,
                        ),
                        child: Text(
                          'No templates in this folder',
                          style: muted,
                        ),
                      ),
                    )
                  : _section(templates, s.templates),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }
}

class TemplateCard extends StatelessWidget {
  const TemplateCard({
    super.key,
    required this.detail,
    this.onTap,
    this.trailing,
    this.caption,
  });

  final TemplateDetail detail;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    final names = templateSummary(detail.items);
    return FlatCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.sm,
        Space.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detail.template.name, style: t.titleMedium),
                const SizedBox(height: 2),
                Text(
                  detail.items.isEmpty ? 'No exercises' : names,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(color: muted),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(caption!, style: t.bodySmall?.copyWith(color: muted)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
