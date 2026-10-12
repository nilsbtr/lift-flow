import 'dart:convert';

import '../data/database.dart';

/// Days of history the widget gets, so it can still draw the week when the
/// app has not been opened for a while.
const kWidgetDays = 21;

/// The template to offer next: the one after the most recently started
/// template (live or finished workout in [workouts]) within its folder, or
/// among the templates outside folders, wrapping around, since a folder is
/// usually a programme like Push / Pull / Legs. Before anything was started
/// it is the first template as Home lists them: [templates] in order, those
/// outside [folders] first, then folder by folder.
WorkoutTemplate? nextTemplate(
  List<WorkoutTemplate> templates,
  List<TemplateFolder> folders,
  Iterable<Workout> workouts,
) {
  if (templates.isEmpty) return null;
  final byFolder = {for (final f in folders) f.id: <WorkoutTemplate>[]};
  final unfiled = <WorkoutTemplate>[];
  for (final t in templates) {
    (byFolder[t.folderId] ?? unfiled).add(t);
  }
  final sections = [unfiled, ...byFolder.values];

  final ids = {for (final t in templates) t.id};
  Workout? last;
  for (final w in workouts) {
    if (!ids.contains(w.templateId)) continue;
    if (last == null || w.startedAt.isAfter(last.startedAt)) last = w;
  }
  if (last == null) return sections.firstWhere((s) => s.isNotEmpty).first;
  for (final s in sections) {
    final i = s.indexWhere((t) => t.id == last!.templateId);
    if (i >= 0) return s[(i + 1) % s.length];
  }
  return null;
}

/// What the home-screen widget draws. The native side picks the current week
/// out of [days] itself, so it stays right while the app is closed.
class HomeWidgetSnapshot {
  const HomeWidgetSnapshot({
    required this.firstDay,
    required this.days,
    this.templateId,
    this.templateName,
    this.live = false,
  });

  /// [DateTime.monday] … [DateTime.sunday].
  final int firstDay;

  /// Local days with a finished workout, as `yyyy-MM-dd`, oldest first.
  final List<String> days;

  /// The template the button starts; null starts an empty workout.
  final int? templateId;
  final String? templateName;

  /// A workout is running, so the button continues it.
  final bool live;

  /// Read by `WeekWidgetProvider.kt`, which must cope with older shapes.
  String encode() => jsonEncode({
    'firstDay': firstDay,
    'days': days,
    'templateId': ?templateId,
    'templateName': ?templateName,
    'live': live,
  });
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The widget's data: the days of the last [days] days that have a finished
/// workout (by its start, like Home's week strip), the [next] template and
/// whether a workout is [live].
HomeWidgetSnapshot widgetSnapshot({
  required Iterable<Workout> history,
  required int firstDay,
  required DateTime now,
  WorkoutTemplate? next,
  Workout? live,
  int days = kWidgetDays,
}) {
  final from = DateTime(now.year, now.month, now.day - (days - 1));
  final name = next?.name.trim() ?? '';
  return HomeWidgetSnapshot(
    firstDay: firstDay,
    days: {
      for (final w in history)
        if (w.endedAt != null && !w.startedAt.isBefore(from)) _ymd(w.startedAt),
    }.toList()..sort(),
    templateId: next?.id,
    templateName: name.isEmpty ? null : name,
    live: live != null,
  );
}

enum WidgetTap { open, resume, start }

/// A tap on the widget; [templateId] is set when [tap] starts a template.
typedef WidgetAction = ({WidgetTap tap, int? templateId});

/// Reads the URI the widget launches the app with: `liftflow://widget/open`,
/// `/workout`, `/start` or `/start?template=12`. Null for anything else.
WidgetAction? parseWidgetUri(Uri? uri) {
  if (uri == null || uri.scheme != 'liftflow' || uri.host != 'widget') {
    return null;
  }
  switch (uri.path) {
    case '/open':
      return (tap: WidgetTap.open, templateId: null);
    case '/workout':
      return (tap: WidgetTap.resume, templateId: null);
    case '/start':
      final raw = uri.queryParameters['template'];
      final id = raw == null ? null : int.tryParse(raw);
      if (raw != null && (id == null || id <= 0)) return null;
      return (tap: WidgetTap.start, templateId: id);
  }
  return null;
}
