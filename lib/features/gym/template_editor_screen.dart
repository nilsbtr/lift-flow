import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/enums.dart';
import '../../data/template_repository.dart';
import '../../domain/supersets.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'exercise_picker_sheet.dart';
import 'template_folders.dart';
import 'template_item_sheet.dart';

class TemplateEditorScreen extends ConsumerStatefulWidget {
  const TemplateEditorScreen({super.key, this.templateId, this.initialItems});

  /// Null to create a new template.
  final int? templateId;
  final List<TemplateItem>? initialItems;

  @override
  ConsumerState<TemplateEditorScreen> createState() =>
      _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends ConsumerState<TemplateEditorScreen> {
  final _name = TextEditingController();
  List<TemplateItem> _items = [];
  final List<int> _keys = [];
  int _nextKey = 0;
  bool _loading = true;
  bool _dirty = false;
  String _savedName = '';
  String? _nameError;
  int? _folderId;
  int? _savedFolderId;

  /// Keys of items whose rep fields hold something unusable.
  final Set<int> _badReps = {};

  @override
  void initState() {
    super.initState();
    // Selection changes also notify, so compare the text itself.
    _name.addListener(() {
      if (!_dirty && _name.text != _savedName) setState(() => _dirty = true);
    });
    _load();
  }

  Future<void> _load() async {
    final id = widget.templateId;
    if (id != null) {
      final d = await ref.read(templateRepoProvider).get(id);
      if (d != null) {
        _savedName = d.template.name;
        _name.text = _savedName;
        _items = normalizedSupersets(d.items);
        _folderId = _savedFolderId = d.template.folderId;
      }
    } else if (widget.initialItems != null) {
      _items = normalizedSupersets(widget.initialItems!);
    }
    _keys
      ..clear()
      ..addAll([for (var i = 0; i < _items.length; i++) _nextKey++]);
    if (mounted) {
      setState(() {
        _loading = false;
        _dirty = false;
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final picked = await showExercisePicker(
      context,
      exclude: {for (final i in _items) i.exercise.id},
    );
    if (picked == null || picked.isEmpty) return;
    setState(() {
      _dirty = true;
      for (final e in picked) {
        _items.add(TemplateItem(exercise: e, targetSets: 3));
        _keys.add(_nextKey++);
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Give your template a name');
      return;
    }
    if (_badReps.isNotEmpty) {
      toast(context, 'Fix the rep ranges first');
      return;
    }
    final repo = ref.read(templateRepoProvider);
    final id = await repo.save(
      id: widget.templateId,
      name: name,
      items: normalizedSupersets(_items),
      folderId: _folderId,
    );
    if (widget.templateId != null && _folderId != _savedFolderId) {
      await repo.moveToFolder(id, _folderId);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete template?',
      message: 'Past workouts stay in your history.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || widget.templateId == null) return;
    await ref.read(templateRepoProvider).delete(widget.templateId!);
    if (mounted) Navigator.pop(context);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return confirm(
      context,
      title: 'Discard changes?',
      action: 'Discard',
      destructive: true,
    );
  }

  Future<void> _pickFolder() async {
    final pick = await pickFolder(context, ref, current: _folderId);
    if (pick == null || pick.id == _folderId) return;
    setState(() {
      _dirty = true;
      _folderId = pick.id;
    });
  }

  void _removeAt(int i) => setState(() {
    _dirty = true;
    _items.removeAt(i);
    _badReps.remove(_keys.removeAt(i));
    _items = normalizedSupersets(_items);
  });

  Future<void> _options(int i) async {
    final linked = isLinkedWithNext([
      for (final it in _items) it.supersetGroup,
    ], i);
    final settings = ref.read(settingsProvider);
    final result = await showTemplateItemSheet(
      context,
      item: _items[i],
      canLink: i + 1 < _items.length,
      linked: linked,
      unit: settings.weightUnit,
      defaultRest: settings.defaultRestSeconds,
    );
    if (!mounted) return;
    if (result == removeItem) return _removeAt(i);
    if (result is! ItemEdit) return;
    setState(() {
      _dirty = true;
      _items[i] = result.item;
      if (result.link != linked) {
        final groups = toggleLinkWithNext([
          for (final it in _items) it.supersetGroup,
        ], i);
        _items = [
          for (var k = 0; k < _items.length; k++)
            _items[k].copyWith(supersetGroup: () => groups[k]),
        ];
      }
    });
  }

  void _reorder(int from, int to) => setState(() {
    _dirty = true;
    final groups = normalizeGroups([for (final it in _items) it.supersetGroup]);
    final order = moveGrouped([
      for (var i = 0; i < groups.length; i++) i,
    ], from, to, (i) => groups[i], nearest: true);
    final keys = [for (final i in order) _keys[i]];
    _items = [for (final i in order) _items[i]];
    _keys
      ..clear()
      ..addAll(keys);
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final folders = ref.watch(templateFoldersProvider).value ?? const [];
    final unit = ref.watch(settingsProvider.select((s) => s.weightUnit));
    final groups = [for (final it in _items) it.supersetGroup];
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.templateId == null ? 'New template' : 'Edit template',
          ),
          actions: [
            if (widget.templateId != null)
              IconButton(
                tooltip: 'Delete template',
                onPressed: _delete,
                icon: const AppIcon(AppIcons.trash),
              ),
            Padding(
              padding: const EdgeInsets.only(right: Space.lg),
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, kCompactTap),
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
        body: _loading
            ? const SizedBox.shrink()
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  0,
                  Space.lg,
                  Space.xxl,
                ),
                buildDefaultDragHandles: false,
                header: Padding(
                  padding: const EdgeInsets.only(bottom: Space.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        autofocus: widget.templateId == null,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 60,
                        style: t.titleLarge,
                        decoration: InputDecoration(
                          hintText: 'Name, e.g. Push',
                          errorText: _nameError,
                          counterText: '',
                        ),
                      ),
                      if (folders.isNotEmpty) ...[
                        const SizedBox(height: Space.sm),
                        _FolderField(
                          name: folders
                              .where((f) => f.id == _folderId)
                              .firstOrNull
                              ?.name,
                          onTap: _pickFolder,
                        ),
                      ],
                    ],
                  ),
                ),
                footer: Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: OutlinedButton.icon(
                    onPressed: _add,
                    icon: const AppIcon(AppIcons.plus),
                    label: const Text('Add exercises'),
                  ),
                ),
                itemCount: _items.length,
                onReorderItem: _reorder,
                itemBuilder: (context, i) {
                  final linkedNext = isLinkedWithNext(groups, i);
                  final linkedPrev = i > 0 && isLinkedWithNext(groups, i - 1);
                  final key = _keys[i];
                  return Padding(
                    key: ValueKey(key),
                    padding: EdgeInsets.only(
                      bottom: linkedNext ? Space.xs : Space.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (linkedNext && !linkedPrev)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Space.xs,
                              0,
                              0,
                              Space.xs,
                            ),
                            child: Text(
                              'Superset',
                              style: t.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        _ItemCard(
                          index: i,
                          item: _items[i],
                          unit: unit,
                          linked: linkedNext || linkedPrev,
                          onChanged: (v) => setState(() {
                            _dirty = true;
                            _items[i] = v;
                          }),
                          onBadReps: (bad) =>
                              bad ? _badReps.add(key) : _badReps.remove(key),
                          onOptions: () => _options(i),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Tappable “Folder” row under the name.
class _FolderField extends StatelessWidget {
  const _FolderField({required this.name, required this.onTap});
  final String? name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    return FlatCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTap),
        child: Row(
          children: [
            Text('Folder', style: t.bodyMedium?.copyWith(color: muted)),
            const SizedBox(width: Space.md),
            Expanded(child: Text(name ?? 'None', textAlign: TextAlign.end)),
            const SizedBox(width: Space.sm),
            AppIcon(AppIcons.chevronRight, color: muted),
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatefulWidget {
  const _ItemCard({
    required this.index,
    required this.item,
    required this.unit,
    required this.linked,
    required this.onChanged,
    required this.onBadReps,
    required this.onOptions,
  });

  final int index;
  final TemplateItem item;
  final WeightUnit unit;

  /// In a superset with a neighbor.
  final bool linked;
  final ValueChanged<TemplateItem> onChanged;

  /// Tells the editor whether the rep fields are currently unusable.
  final ValueChanged<bool> onBadReps;
  final VoidCallback onOptions;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  late final TextEditingController _min = TextEditingController(
    text: widget.item.repsMin?.toString() ?? '',
  );
  late final TextEditingController _max = TextEditingController(
    text: widget.item.repsMax?.toString() ?? '',
  );
  String? _repsError;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _onReps(String _) {
    final r = parseRepsFields(_min.text, _max.text);
    setState(() => _repsError = r.error);
    widget.onBadReps(r.error != null);
    if (r.error != null) return;
    widget.onChanged(
      widget.item.copyWith(repsMin: () => r.min, repsMax: () => r.max),
    );
  }

  /// “Rest 2:00 · 80 kg” for what differs from the defaults.
  String? get _summary {
    final item = widget.item;
    final kg = item.targetWeightKg;
    final parts = [
      if (item.restSeconds != null) 'Rest ${fmtClock(item.restSeconds!)}',
      if (kg != null && takesLoad(item))
        '${kg < 0 ? kMinus : ''}${fmtWeight(kg.abs(), widget.unit)} '
            '${widget.unit.label}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _repsField(String hint, TextEditingController c) {
    final bad = _repsError != null;
    return Semantics(
      label: '$hint reps',
      child: SizedBox(
        width: MediaQuery.textScalerOf(context)
            .scale(48)
            .clamp(48.0, 72.0)
            .toDouble(),
        child: TextField(
          controller: c,
          onChanged: _onReps,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 3,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Space.xs,
              vertical: Space.md,
            ),
            errorText: bad ? '' : null,
            errorStyle: const TextStyle(height: 0, fontSize: 0),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = LiftColors.of(context).muted;
    final item = widget.item;
    final summary = _summary;
    return FlatCard(
      color: widget.linked
          ? Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.08),
              scheme.surface,
            )
          : null,
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.xs,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.exercise.name, style: t.titleMedium)),
              IconButton(
                tooltip: 'Exercise options',
                onPressed: widget.onOptions,
                icon: AppIcon(AppIcons.more, color: muted),
              ),
              ReorderableDragStartListener(
                index: widget.index,
                child: Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: AppIcon(AppIcons.drag, color: muted),
                ),
              ),
            ],
          ),
          if (summary != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: GestureDetector(
                onTap: widget.onOptions,
                child: Text(
                  summary,
                  style: t.bodySmall?.copyWith(color: muted),
                ),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Fewer sets',
                    onPressed: item.targetSets > 1
                        ? () => widget.onChanged(
                            item.copyWith(targetSets: item.targetSets - 1),
                          )
                        : null,
                    icon: const AppIcon(AppIcons.minus),
                  ),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 56),
                      child: Text(
                        item.targetSets == 1
                            ? '1 set'
                            : '${item.targetSets} sets',
                        textAlign: TextAlign.center,
                        style: t.titleMedium?.copyWith(
                          fontFeatures: Fonts.tabular,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'More sets',
                    onPressed: item.targetSets < 10
                        ? () => widget.onChanged(
                            item.copyWith(targetSets: item.targetSets + 1),
                          )
                        : null,
                    icon: const AppIcon(AppIcons.plus),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: Space.md),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Space.xs,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: Space.xs),
                      child: Text(
                        'Reps',
                        style: t.bodyMedium?.copyWith(color: muted),
                      ),
                    ),
                    _repsField('Min', _min),
                    Text('–', style: t.bodyMedium),
                    _repsField('Max', _max),
                  ],
                ),
              ),
            ],
          ),
          if (_repsError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, Space.xs, Space.md, 0),
              child: Text(
                _repsError!,
                style: t.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
