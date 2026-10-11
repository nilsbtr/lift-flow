import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../data/template_repository.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';

typedef FolderSection = ({
  TemplateFolder folder,
  List<TemplateDetail> templates,
});

/// Templates split into those outside any folder and one list per folder, in
/// folder order. Without folders, [unfiled] is the whole list.
class TemplateSections {
  const TemplateSections(this.unfiled, this.folders);
  final List<TemplateDetail> unfiled;
  final List<FolderSection> folders;
}

TemplateSections groupTemplates(
  List<TemplateDetail> templates,
  List<TemplateFolder> folders,
) {
  final byFolder = {for (final f in folders) f.id: <TemplateDetail>[]};
  final unfiled = <TemplateDetail>[];
  for (final d in templates) {
    (byFolder[d.template.folderId] ?? unfiled).add(d);
  }
  return TemplateSections(unfiled, [
    for (final f in folders) (folder: f, templates: byFolder[f.id]!),
  ]);
}

/// [allIds] with the ids of one section replaced by [newSection], which
/// reorders that section and leaves the others where they are.
List<int> reorderWithin(
  List<int> allIds,
  List<int> sectionIds,
  List<int> newSection,
) {
  final slots = sectionIds.toSet();
  final it = newSection.iterator;
  return [
    for (final id in allIds)
      slots.contains(id) && it.moveNext() ? it.current : id,
  ];
}

/// Names a template card's exercises, joining supersets with “+”.
String templateSummary(List<TemplateItem> items) {
  final parts = <String>[];
  for (var i = 0; i < items.length; i++) {
    final name = items[i].exercise.name;
    final g = items[i].supersetGroup;
    if (g != null && i > 0 && items[i - 1].supersetGroup == g) {
      parts[parts.length - 1] += ' + $name';
    } else {
      parts.add(name);
    }
  }
  return parts.join(' · ');
}

/// Collapsible folder row. The collapsed state is stored, so Home and Gym
/// agree.
class FolderHeader extends StatelessWidget {
  const FolderHeader({
    super.key,
    required this.folder,
    required this.count,
    required this.onToggle,
    this.trailing,
  });

  final TemplateFolder folder;
  final int count;
  final VoidCallback onToggle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    return Semantics(
      button: true,
      expanded: !folder.isCollapsed,
      label: '${folder.name}, $count',
      excludeSemantics: true,
      onTap: onToggle,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onToggle,
              borderRadius: Radii.smAll,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinTap),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: folder.isCollapsed ? 0 : 0.25,
                        duration: Motion.of(context, Motion.fast),
                        child: AppIcon(AppIcons.chevronRight, color: muted),
                      ),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          folder.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium,
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Text(
                        '$count',
                        style: t.bodyMedium?.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

void toggleFolder(WidgetRef ref, TemplateFolder f) => unawaited(
  ref.read(templateRepoProvider).setFolderCollapsed(f.id, !f.isCollapsed),
);

/// Asks for a folder name. Returns null on cancel.
Future<String?> askFolderName(BuildContext context, {String initial = ''}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _FolderNameDialog(initial),
    );

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog(this.initial);
  final String initial;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial.isEmpty ? 'New folder' : 'Rename folder'),
    content: TextField(
      controller: _ctrl,
      autofocus: true,
      maxLength: 60,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: const InputDecoration(
        hintText: 'e.g. Upper/lower',
        counterText: '',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _submit,
        child: Text(widget.initial.isEmpty ? 'Create' : 'Save'),
      ),
    ],
  );
}

/// Lets the user pick a folder, none, or a new one. Returns null if dismissed;
/// otherwise a record whose `id` is null for “no folder”.
Future<({int? id})?> pickFolder(
  BuildContext context,
  WidgetRef ref, {
  int? current,
}) async {
  final repo = ref.read(templateRepoProvider);
  final folders = ref.read(templateFoldersProvider).value ?? const [];
  final picked = await showAppSheet<Object>(
    context,
    (_) => _FolderSheet(folders: folders, current: current),
  );
  if (picked is int) return (id: picked == _noFolder ? null : picked);
  if (picked != _newFolder || !context.mounted) return null;
  final name = await askFolderName(context);
  return name == null ? null : (id: await repo.createFolder(name));
}

const _noFolder = -1;
const _newFolder = 'new';

class _FolderSheet extends StatelessWidget {
  const _FolderSheet({required this.folders, required this.current});
  final List<TemplateFolder> folders;
  final int? current;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final primary = Theme.of(context).colorScheme.primary;
    Widget tile(String label, int value, bool selected) => ListTile(
      title: Text(label),
      trailing: selected ? AppIcon(AppIcons.check, color: primary) : null,
      onTap: () => Navigator.pop(context, value),
    );
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: Text('Move to folder', style: t.headlineSmall),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                tile('No folder', _noFolder, current == null),
                for (final f in folders) tile(f.name, f.id, current == f.id),
                ListTile(
                  leading: AppIcon(AppIcons.plus, color: primary),
                  title: const Text('New folder'),
                  onTap: () => Navigator.pop(context, _newFolder),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a folder and moves [template] there.
Future<void> moveTemplate(
  BuildContext context,
  WidgetRef ref,
  WorkoutTemplate template,
) async {
  final pick = await pickFolder(context, ref, current: template.folderId);
  if (pick == null || pick.id == template.folderId) return;
  await ref.read(templateRepoProvider).moveToFolder(template.id, pick.id);
}

enum _FolderAction { rename, up, down, delete }

/// Overflow menu of a folder header in Gym.
class FolderMenu extends ConsumerWidget {
  const FolderMenu({super.key, required this.folder, required this.folders});
  final TemplateFolder folder;
  final List<TemplateFolder> folders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(templateRepoProvider);
    final i = folders.indexWhere((f) => f.id == folder.id);
    return PopupMenuButton<_FolderAction>(
      tooltip: 'Folder options',
      icon: const AppIcon(AppIcons.more),
      onSelected: (a) async {
        switch (a) {
          case _FolderAction.rename:
            final name = await askFolderName(context, initial: folder.name);
            if (name != null) await repo.renameFolder(folder.id, name);
          case _FolderAction.up || _FolderAction.down:
            final ids = [for (final f in folders) f.id];
            final to = a == _FolderAction.up ? i - 1 : i + 1;
            ids.insert(to, ids.removeAt(i));
            await repo.reorderFolders(ids);
          case _FolderAction.delete:
            final ok = await confirm(
              context,
              title: 'Delete folder?',
              message: 'Its templates stay in your list.',
              action: 'Delete',
              destructive: true,
            );
            if (ok) await repo.deleteFolder(folder.id);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: _FolderAction.rename, child: Text('Rename')),
        if (i > 0)
          const PopupMenuItem(value: _FolderAction.up, child: Text('Move up')),
        if (i >= 0 && i < folders.length - 1)
          const PopupMenuItem(
            value: _FolderAction.down,
            child: Text('Move down'),
          ),
        PopupMenuItem(
          value: _FolderAction.delete,
          child: Text(
            'Delete folder',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }
}

enum _TemplateAction { duplicate, move }

/// Overflow menu of a template card in Gym.
class TemplateMenu extends ConsumerWidget {
  const TemplateMenu({super.key, required this.template});
  final WorkoutTemplate template;

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => PopupMenuButton<_TemplateAction>(
    tooltip: 'Template options',
    icon: const AppIcon(AppIcons.more),
    onSelected: (a) async {
      switch (a) {
        case _TemplateAction.duplicate:
          await ref.read(templateRepoProvider).duplicate(template.id);
          if (context.mounted) toast(context, 'Template duplicated');
        case _TemplateAction.move:
          await moveTemplate(context, ref, template);
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: _TemplateAction.duplicate, child: Text('Duplicate')),
      PopupMenuItem(value: _TemplateAction.move, child: Text('Move to folder')),
    ],
  );
}
