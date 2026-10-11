import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

import '../data/database.dart';

/// Long-press shortcuts on the launcher icon that start a template.
class ShortcutService {
  ShortcutService([QuickActions actions = const QuickActions()])
    : _actions = actions;

  final QuickActions _actions;

  static const _prefix = 'template:';
  static const _icon = 'ic_shortcut_workout';

  /// What the launcher currently shows, to skip no-op updates.
  List<String>? _shown;

  static String typeFor(int templateId) => '$_prefix$templateId';

  static int? templateIdOf(String type) => type.startsWith(_prefix)
      ? int.tryParse(type.substring(_prefix.length))
      : null;

  bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android && !kIsWeb;

  /// Reports shortcut taps, including the one that launched the app.
  Future<void> init(void Function(int templateId) onTemplate) async {
    if (!_supported) return;
    try {
      await _actions.initialize((type) {
        final id = templateIdOf(type);
        if (id != null) onTemplate(id);
      });
    } catch (e) {
      debugPrint('Shortcuts unavailable: $e');
    }
  }

  /// Makes [templates] the launcher's shortcuts, in order.
  Future<void> sync(List<WorkoutTemplate> templates) async {
    if (!_supported) return;
    final items = [
      for (final t in templates)
        if (t.name.trim().isNotEmpty)
          ShortcutItem(
            type: typeFor(t.id),
            localizedTitle: t.name.trim(),
            icon: _icon,
          ),
    ];
    final key = [for (final i in items) '${i.type} ${i.localizedTitle}'];
    if (listEquals(key, _shown)) return;
    _shown = key;
    try {
      if (items.isEmpty) {
        await _actions.clearShortcutItems();
      } else {
        await _actions.setShortcutItems(items);
      }
    } catch (e) {
      _shown = null;
      debugPrint('Shortcuts not updated: $e');
    }
  }
}
