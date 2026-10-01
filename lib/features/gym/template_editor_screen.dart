import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/template_repository.dart';
import '../../domain/units.dart';
import '../../providers.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/common.dart';
import 'exercise_picker_sheet.dart';

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
        _items = [...d.items];
      }
    } else if (widget.initialItems != null) {
      _items = [...widget.initialItems!];
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
    await ref
        .read(templateRepoProvider)
        .save(id: widget.templateId, name: name, items: _items);
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
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
                  child: TextField(
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
                onReorderItem: (from, to) => setState(() {
                  _dirty = true;
                  _items.insert(to, _items.removeAt(from));
                  _keys.insert(to, _keys.removeAt(from));
                }),
                itemBuilder: (context, i) => Padding(
                  key: ValueKey(_keys[i]),
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: _ItemCard(
                    index: i,
                    item: _items[i],
                    onChanged: (v) => setState(() {
                      _dirty = true;
                      _items[i] = v;
                    }),
                    onRemove: () => setState(() {
                      _dirty = true;
                      _items.removeAt(i);
                      _keys.removeAt(i);
                    }),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ItemCard extends StatefulWidget {
  const _ItemCard({
    required this.index,
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final TemplateItem item;
  final ValueChanged<TemplateItem> onChanged;
  final VoidCallback onRemove;

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  late final TextEditingController _reps = TextEditingController(
    text: fmtRepsRange(widget.item.repsMin, widget.item.repsMax),
  );
  bool _invalid = false;

  @override
  void dispose() {
    _reps.dispose();
    super.dispose();
  }

  void _onReps(String v) {
    final r = parseRepsRange(v);
    setState(() => _invalid = r == null);
    if (r == null) return;
    widget.onChanged(
      widget.item.copyWith(repsMin: () => r.min, repsMax: () => r.max),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final muted = LiftColors.of(context).muted;
    final item = widget.item;
    return FlatCard(
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
                tooltip: 'Remove',
                onPressed: widget.onRemove,
                icon: AppIcon(
                  AppIcons.close,
                  size: IconSizes.sm,
                  color: muted,
                ),
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
          Row(
            children: [
              Text('Sets', style: t.bodyMedium?.copyWith(color: muted)),
              const SizedBox(width: Space.sm),
              IconButton(
                tooltip: 'Fewer sets',
                onPressed: item.targetSets > 1
                    ? () => widget.onChanged(
                        item.copyWith(targetSets: item.targetSets - 1),
                      )
                    : null,
                icon: const AppIcon(AppIcons.minus),
              ),
              SizedBox(
                width: 24,
                child: Text(
                  '${item.targetSets}',
                  textAlign: TextAlign.center,
                  style: t.titleMedium?.copyWith(fontFeatures: Fonts.tabular),
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
              const Spacer(),
              Text('Reps', style: t.bodyMedium?.copyWith(color: muted)),
              const SizedBox(width: Space.sm),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _reps,
                  onChanged: _onReps,
                  keyboardType: TextInputType.phone,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '8-12',
                    errorText: _invalid ? '' : null,
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
            ],
          ),
        ],
      ),
    );
  }
}
