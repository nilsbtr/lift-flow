import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart';

import '../domain/muscles.dart';
import 'database.dart';

const int kBackupVersion = 3;
const int kMaxBackupBytes = 20 * 1024 * 1024;

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// JSON export / import of all data. Import replaces everything in a single
/// transaction after strict validation. Progress photos are files on the
/// device and stay out of both.
class BackupService {
  BackupService(this._db);
  final AppDatabase _db;

  Future<Uint8List> export() async {
    final settings = await (_db.select(
      _db.appSettings,
    )..where((s) => s.id.equals(1))).getSingle();
    final exercises = await _db.select(_db.exercises).get();
    final folders = await _db.select(_db.templateFolders).get();
    final templates = await _db.select(_db.workoutTemplates).get();
    final templateItems = await _db.select(_db.templateExercises).get();
    final workouts = await _db.select(_db.workouts).get();
    final wExercises = await _db.select(_db.workoutExercises).get();
    final sets = await _db.select(_db.workoutSets).get();
    final bodyweight = await _db.select(_db.bodyweightEntries).get();

    final data = <String, Object?>{
      'app': 'lift_flow',
      'version': kBackupVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'settings': {
        'weightUnit': settings.weightUnit.name,
        'themeMode': settings.themeMode.name,
        'pureBlack': settings.pureBlack,
        'bodyweightKg': settings.bodyweightKg,
        'defaultRestSeconds': settings.defaultRestSeconds,
        'autoStartRest': settings.autoStartRest,
        'restAlerts': settings.restAlerts,
        'keepScreenOn': settings.keepScreenOn,
        'weeklyGoal': settings.weeklyGoal,
        'effortMode': settings.effortMode.name,
        'restSound': settings.restSound,
        'firstDayOfWeek': settings.firstDayOfWeek,
        'barWeightKg': settings.barWeightKg,
        'plates': settings.plates,
        'balanceMin': settings.balanceMin,
        'balanceMax': settings.balanceMax,
        'dynamicColor': settings.dynamicColor,
        'reminderDays': settings.reminderDays,
        'reminderMinutes': settings.reminderMinutes,
      },
      'bodyweight': [
        for (final b in bodyweight) {'date': _day(b.date), 'kg': b.kg},
      ],
      'exercises': [
        for (final e in exercises)
          {
            'id': e.id,
            'name': e.name,
            'muscleGroup': e.muscleGroup.name,
            'trackingType': e.trackingType.name,
            'loadMode': e.loadMode.name,
            'notes': e.notes,
            'isArchived': e.isArchived,
            'createdAt': _iso(e.createdAt),
            'equipment': e.equipment.name,
            'perSide': e.perSide,
            'perDumbbell': e.perDumbbell,
            'secondaryMuscles': [for (final g in e.secondaryMuscles) g.name],
          },
      ],
      'folders': [
        for (final f in folders)
          {
            'id': f.id,
            'name': f.name,
            'position': f.position,
            'isCollapsed': f.isCollapsed,
          },
      ],
      'templates': [
        for (final t in templates)
          {
            'id': t.id,
            'name': t.name,
            'position': t.position,
            'folderId': t.folderId,
            'items': [
              for (final i in templateItems)
                if (i.templateId == t.id)
                  {
                    'exerciseId': i.exerciseId,
                    'position': i.position,
                    'targetSets': i.targetSets,
                    'repsMin': i.repsMin,
                    'repsMax': i.repsMax,
                    'restSeconds': i.restSeconds,
                    'targetWeightKg': i.targetWeightKg,
                    'supersetGroup': i.supersetGroup,
                  },
            ],
          },
      ],
      'workouts': [
        for (final w in workouts)
          {
            'id': w.id,
            'templateId': w.templateId,
            'name': w.name,
            'startedAt': _iso(w.startedAt),
            'endedAt': w.endedAt == null ? null : _iso(w.endedAt!),
            'bodyweightKg': w.bodyweightKg,
            'totalSets': w.totalSets,
            'totalVolumeKg': w.totalVolumeKg,
            'exerciseCount': w.exerciseCount,
            'note': w.note,
            'exercises': [
              for (final we in wExercises)
                if (we.workoutId == w.id)
                  {
                    'exerciseId': we.exerciseId,
                    'position': we.position,
                    'targetRepsMin': we.targetRepsMin,
                    'targetRepsMax': we.targetRepsMax,
                    'note': we.note,
                    'supersetGroup': we.supersetGroup,
                    'restSeconds': we.restSeconds,
                    'targetWeightKg': we.targetWeightKg,
                    'sets': [
                      for (final s in sets)
                        if (s.workoutExerciseId == we.id)
                          {
                            'position': s.position,
                            'loadKg': s.loadKg,
                            'reps': s.reps,
                            'isCompleted': s.isCompleted,
                            'completedAt': s.completedAt == null
                                ? null
                                : _iso(s.completedAt!),
                            'setType': s.setType.name,
                            'rpe': s.rpe,
                            'note': s.note,
                            'durationSeconds': s.durationSeconds,
                            'distanceM': s.distanceM,
                          },
                    ],
                  },
            ],
          },
      ],
    };
    return Isolate.run(_encoder(data));
  }

  static Uint8List Function() _encoder(Map<String, Object?> data) =>
      () => Uint8List.fromList(utf8.encode(jsonEncode(data)));

  static ParsedBackup Function() _parser(Uint8List bytes) =>
      () => parseBackup(bytes);

  /// Validates and imports a backup, replacing all data.
  Future<void> import(Uint8List bytes) async {
    if (bytes.length > kMaxBackupBytes) {
      throw const BackupFormatException('Backup file is too large.');
    }
    final parsed = await Isolate.run(_parser(bytes));
    await _db.transaction(() async {
      await _clear();
      await _db.update(_db.appSettings).write(parsed.settings);
      await _db.batch((b) {
        b.insertAll(_db.exercises, parsed.exercises);
        b.insertAll(_db.templateFolders, parsed.folders);
        b.insertAll(_db.workoutTemplates, parsed.templates);
        b.insertAll(_db.templateExercises, parsed.templateItems);
        b.insertAll(_db.workouts, parsed.workouts);
        b.insertAll(_db.bodyweightEntries, parsed.bodyweight);
      });
      for (final we in parsed.workoutExercises) {
        final id = await _db.into(_db.workoutExercises).insert(we.row);
        await _db.batch((b) {
          b.insertAll(_db.workoutSets, [
            for (final s in we.sets) s.copyWith(workoutExerciseId: Value(id)),
          ]);
        });
      }
    });
  }

  Future<void> deleteAll() => _db.transaction(() async {
    await _clear();
    await _db.delete(_db.appSettings).go();
    await _db
        .into(_db.appSettings)
        .insert(const AppSettingsCompanion(id: Value(1)));
  });

  Future<void> _clear() async {
    await _db.delete(_db.restState).go();
    await _db.delete(_db.bodyweightEntries).go();
    await _db.delete(_db.workoutSets).go();
    await _db.delete(_db.workoutExercises).go();
    await _db.delete(_db.workouts).go();
    await _db.delete(_db.templateExercises).go();
    await _db.delete(_db.workoutTemplates).go();
    await _db.delete(_db.templateFolders).go();
    await _db.delete(_db.exercises).go();
  }

  static String _iso(DateTime d) => d.toUtc().toIso8601String();

  /// Local calendar day, e.g. "2025-01-31".
  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------- parsing

class ParsedWorkoutExercise {
  ParsedWorkoutExercise(this.row, this.sets);
  final WorkoutExercisesCompanion row;
  final List<WorkoutSetsCompanion> sets;
}

class ParsedBackup {
  ParsedBackup({
    required this.settings,
    required this.exercises,
    required this.folders,
    required this.templates,
    required this.templateItems,
    required this.workouts,
    required this.workoutExercises,
    required this.bodyweight,
  });

  final AppSettingsCompanion settings;
  final List<ExercisesCompanion> exercises;
  final List<TemplateFoldersCompanion> folders;
  final List<WorkoutTemplatesCompanion> templates;
  final List<TemplateExercisesCompanion> templateItems;
  final List<WorkoutsCompanion> workouts;
  final List<ParsedWorkoutExercise> workoutExercises;
  final List<BodyweightEntriesCompanion> bodyweight;
}

Never _fail(String msg) => throw BackupFormatException('Invalid backup: $msg');

Map<String, Object?> _map(Object? v, String what) =>
    v is Map<String, Object?> ? v : _fail('$what must be an object');

List<Object?> _list(Map<String, Object?> m, String k) {
  final v = m[k];
  return v is List<Object?> ? v : _fail('"$k" must be a list');
}

int _int(Map<String, Object?> m, String k, {int? min, int? max}) {
  final v = m[k];
  if (v is! int) _fail('"$k" must be an integer');
  if ((min != null && v < min) || (max != null && v > max)) {
    _fail('"$k" out of range');
  }
  return v;
}

int? _intOrNull(Map<String, Object?> m, String k, {int? min, int? max}) =>
    m[k] == null ? null : _int(m, k, min: min, max: max);

double? _numOrNull(
  Map<String, Object?> m,
  String k, {
  double? min,
  double? max,
}) {
  final v = m[k];
  if (v == null) return null;
  if (v is! num || !v.isFinite) _fail('"$k" must be a number');
  final d = v.toDouble();
  if ((min != null && d < min) || (max != null && d > max)) {
    _fail('"$k" out of range');
  }
  return d;
}

String _str(Map<String, Object?> m, String k, {int min = 0, int max = 1000}) {
  final v = m[k];
  if (v is! String) _fail('"$k" must be a string');
  if (v.length < min || v.length > max) _fail('"$k" has invalid length');
  return v;
}

String? _strOrNull(Map<String, Object?> m, String k, {int max = 1000}) =>
    m[k] == null ? null : _str(m, k, max: max);

bool _bool(Map<String, Object?> m, String k) {
  final v = m[k];
  return v is bool ? v : _fail('"$k" must be true or false');
}

DateTime _date(Map<String, Object?> m, String k) {
  final d = DateTime.tryParse(_str(m, k, max: 40));
  return d ?? _fail('"$k" must be a date');
}

DateTime? _dateOrNull(Map<String, Object?> m, String k) =>
    m[k] == null ? null : _date(m, k);

final _dayPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

DateTime _localDay(Map<String, Object?> m, String k) {
  final match = _dayPattern.firstMatch(_str(m, k, max: 10));
  if (match == null) _fail('"$k" must be a day like 2025-01-31');
  final [y, mo, d] = [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
  final day = DateTime(y, mo, d);
  if (day.month != mo || day.day != d) _fail('"$k" is not a valid day');
  return day;
}

T _enum<T extends Enum>(List<T> values, Map<String, Object?> m, String k) {
  final s = _str(m, k, max: 40);
  for (final v in values) {
    if (v.name == s) return v;
  }
  _fail('"$k" has unknown value "$s"');
}

List<T> _enumList<T extends Enum>(
  List<T> values,
  Map<String, Object?> m,
  String k,
) => [
  for (final raw in _list(m, k).toSet())
    values.firstWhere(
      (v) => v.name == raw,
      orElse: () => _fail('"$k" has unknown value "$raw"'),
    ),
];

int? _restOrNull(Map<String, Object?> m) =>
    _intOrNull(m, 'restSeconds', min: 0, max: 3600);

double? _targetOrNull(Map<String, Object?> m) =>
    _numOrNull(m, 'targetWeightKg', min: 0, max: 2000);

/// Comma-separated positive kg values, e.g. "25,20,10,5,2.5,1.25".
String? _platesOrNull(Map<String, Object?> m, String k) {
  final s = _strOrNull(m, k, max: 200);
  if (s == null || s.trim().isEmpty) return s;
  for (final part in s.split(',')) {
    final kg = double.tryParse(part.trim());
    if (kg == null || !kg.isFinite || kg <= 0) _fail('"$k" is not a plate list');
  }
  return s;
}

/// Pure parser + validator (runs in a background isolate).
ParsedBackup parseBackup(Uint8List bytes) {
  final Object? root;
  try {
    root = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const BackupFormatException('This file is not a Lift Flow backup.');
  }
  final m = _map(root, 'backup');
  if (m['app'] != 'lift_flow') {
    throw const BackupFormatException('This file is not a Lift Flow backup.');
  }
  final version = _int(m, 'version');
  if (version > kBackupVersion) {
    throw const BackupFormatException(
      'This backup was made with a newer version of the app.',
    );
  }
  final v2 = version >= 2;
  final v3 = version >= 3;

  // Settings
  final s = _map(m['settings'], 'settings');
  final balanceMin = v3 ? _int(s, 'balanceMin', min: 0, max: 100) : 10;
  final balanceMax = v3 ? _int(s, 'balanceMax', min: 1, max: 100) : 20;
  if (balanceMax < balanceMin) _fail('invalid balance range');
  final settings = AppSettingsCompanion(
    weightUnit: Value(_enum(WeightUnit.values, s, 'weightUnit')),
    themeMode: Value(_enum(ThemePref.values, s, 'themeMode')),
    pureBlack: Value(_bool(s, 'pureBlack')),
    bodyweightKg: Value(_numOrNull(s, 'bodyweightKg', min: 20, max: 400)),
    defaultRestSeconds: Value(_int(s, 'defaultRestSeconds', min: 0, max: 3600)),
    autoStartRest: Value(_bool(s, 'autoStartRest')),
    restAlerts: Value(_bool(s, 'restAlerts')),
    keepScreenOn: Value(_bool(s, 'keepScreenOn')),
    permissionsPrompted: const Value(false),
    weeklyGoal: Value(v2 ? _intOrNull(s, 'weeklyGoal', min: 1, max: 7) : null),
    effortMode: Value(
      v3 ? _enum(EffortMode.values, s, 'effortMode') : EffortMode.off,
    ),
    restSound: Value(v3 && _bool(s, 'restSound')),
    firstDayOfWeek: Value(
      v3
          ? _int(s, 'firstDayOfWeek', min: DateTime.monday, max: DateTime.sunday)
          : DateTime.monday,
    ),
    barWeightKg: Value(
      v3 ? _numOrNull(s, 'barWeightKg', min: 0, max: 500) : null,
    ),
    plates: Value(v3 ? _platesOrNull(s, 'plates') : null),
    balanceMin: Value(balanceMin),
    balanceMax: Value(balanceMax),
    // Device-local state starts fresh, like the permission prompt.
    lastBackupAt: const Value(null),
    backupSnoozedAt: const Value(null),
    appLock: const Value(false),
    setMenuHintSeen: const Value(false),
    dynamicColor: Value(v3 && _bool(s, 'dynamicColor')),
    reminderDays: Value(v3 ? _int(s, 'reminderDays', min: 0, max: 127) : 0),
    reminderMinutes: Value(
      v3 ? _int(s, 'reminderMinutes', min: 0, max: 1439) : 1080,
    ),
  );

  // Exercises
  final exerciseInfo = <int, (TrackingType, LoadMode)>{};
  final names = <String>{};
  final exercises = <ExercisesCompanion>[];
  for (final raw in _list(m, 'exercises')) {
    final e = _map(raw, 'exercise');
    final id = _int(e, 'id', min: 1);
    final name = _str(e, 'name', min: 1, max: 60).trim();
    if (name.isEmpty) _fail('exercise name is empty');
    if (!names.add(name.toLowerCase())) _fail('duplicate exercise "$name"');
    if (exerciseInfo.containsKey(id)) _fail('duplicate exercise id $id');
    final type = _enum(TrackingType.values, e, 'trackingType');
    final mode = type == TrackingType.weights
        ? LoadMode.none
        : _enum(LoadMode.values, e, 'loadMode');
    exerciseInfo[id] = (type, mode);
    final group = _enum(MuscleGroup.values, e, 'muscleGroup');
    exercises.add(
      ExercisesCompanion.insert(
        id: Value(id),
        name: name,
        // Older backups only know the generic arms and legs groups.
        muscleGroup: v3 ? group : refineMuscleGroup(name, group),
        trackingType: type,
        loadMode: Value(mode),
        notes: Value(_strOrNull(e, 'notes', max: 500)),
        isArchived: Value(_bool(e, 'isArchived')),
        createdAt: _date(e, 'createdAt'),
        equipment: Value(
          v3 ? _enum(Equipment.values, e, 'equipment') : Equipment.none,
        ),
        perSide: Value(v3 && _bool(e, 'perSide')),
        perDumbbell: Value(v3 && _bool(e, 'perDumbbell')),
        secondaryMuscles: Value(
          v3 ? _enumList(MuscleGroup.values, e, 'secondaryMuscles') : const [],
        ),
      ),
    );
  }

  int exerciseRef(Map<String, Object?> m) {
    final id = _int(m, 'exerciseId');
    if (!exerciseInfo.containsKey(id)) _fail('unknown exercise id $id');
    return id;
  }

  // Template folders
  final folderIds = <int>{};
  final folders = <TemplateFoldersCompanion>[];
  for (final raw in v3 ? _list(m, 'folders') : const <Object?>[]) {
    final f = _map(raw, 'folder');
    final id = _int(f, 'id', min: 1);
    if (!folderIds.add(id)) _fail('duplicate folder id $id');
    final name = _str(f, 'name', min: 1, max: 60).trim();
    if (name.isEmpty) _fail('folder name is empty');
    folders.add(
      TemplateFoldersCompanion.insert(
        id: Value(id),
        name: name,
        position: Value(_int(f, 'position', min: 0)),
        isCollapsed: Value(_bool(f, 'isCollapsed')),
      ),
    );
  }

  // Templates
  final templateIds = <int>{};
  final templates = <WorkoutTemplatesCompanion>[];
  final templateItems = <TemplateExercisesCompanion>[];
  for (final raw in _list(m, 'templates')) {
    final t = _map(raw, 'template');
    final id = _int(t, 'id', min: 1);
    if (!templateIds.add(id)) _fail('duplicate template id $id');
    final folderId = v3 ? _intOrNull(t, 'folderId') : null;
    templates.add(
      WorkoutTemplatesCompanion.insert(
        id: Value(id),
        name: _str(t, 'name', min: 1, max: 60),
        position: Value(_int(t, 'position', min: 0)),
        folderId: Value(folderIds.contains(folderId) ? folderId : null),
      ),
    );
    for (final rawItem in _list(t, 'items')) {
      final i = _map(rawItem, 'template item');
      final min = _intOrNull(i, 'repsMin', min: 1, max: 100);
      final max = _intOrNull(i, 'repsMax', min: 1, max: 100);
      if (min != null && max != null && max < min) _fail('invalid reps range');
      templateItems.add(
        TemplateExercisesCompanion.insert(
          templateId: id,
          exerciseId: exerciseRef(i),
          position: _int(i, 'position', min: 0),
          targetSets: Value(_int(i, 'targetSets', min: 1, max: 10)),
          repsMin: Value(min),
          repsMax: Value(max),
          restSeconds: Value(v3 ? _restOrNull(i) : null),
          targetWeightKg: Value(v3 ? _targetOrNull(i) : null),
          supersetGroup: Value(v3 ? _intOrNull(i, 'supersetGroup') : null),
        ),
      );
    }
  }

  // Workouts
  final workoutIds = <int>{};
  var liveCount = 0;
  final workouts = <WorkoutsCompanion>[];
  final workoutExercises = <ParsedWorkoutExercise>[];
  final snapshots = <(DateTime, double)>[];
  for (final raw in _list(m, 'workouts')) {
    final w = _map(raw, 'workout');
    final id = _int(w, 'id', min: 1);
    if (!workoutIds.add(id)) _fail('duplicate workout id $id');
    final startedAt = _date(w, 'startedAt');
    final endedAt = _dateOrNull(w, 'endedAt');
    if (endedAt == null) liveCount++;
    if (liveCount > 1) _fail('more than one unfinished workout');
    if (endedAt != null && endedAt.isBefore(startedAt)) {
      _fail('workout ends before it starts');
    }
    final templateId = _intOrNull(w, 'templateId');
    final bodyweightKg = _numOrNull(w, 'bodyweightKg', min: 20, max: 400);
    if (endedAt != null && bodyweightKg != null) {
      snapshots.add((startedAt.toLocal(), bodyweightKg));
    }
    workouts.add(
      WorkoutsCompanion.insert(
        id: Value(id),
        templateId: Value(
          templateId != null && templateIds.contains(templateId)
              ? templateId
              : null,
        ),
        name: _str(w, 'name', min: 1, max: 60),
        startedAt: startedAt,
        endedAt: Value(endedAt),
        bodyweightKg: Value(bodyweightKg),
        totalSets: Value(_int(w, 'totalSets', min: 0)),
        totalVolumeKg: Value(_numOrNull(w, 'totalVolumeKg', min: 0) ?? 0),
        exerciseCount: Value(_int(w, 'exerciseCount', min: 0)),
        note: Value(v3 ? _strOrNull(w, 'note', max: 500) : null),
      ),
    );
    for (final rawEx in _list(w, 'exercises')) {
      final e = _map(rawEx, 'workout exercise');
      final exId = exerciseRef(e);
      final (type, mode) = exerciseInfo[exId]!;
      final sets = <WorkoutSetsCompanion>[];
      for (final rawSet in _list(e, 'sets')) {
        final st = _map(rawSet, 'set');
        final load = _numOrNull(st, 'loadKg', min: -2000, max: 2000);
        final ok = switch ((type, mode)) {
          (TrackingType.weights, _) => load == null || load >= 0,
          (_, LoadMode.none) => load == null || load == 0,
          (_, LoadMode.added) => load == null || load >= 0,
          (_, LoadMode.assisted) => load == null || load <= 0,
        };
        if (!ok) _fail('set load does not match exercise type');
        sets.add(
          WorkoutSetsCompanion.insert(
            workoutExerciseId: 0,
            position: _int(st, 'position', min: 0),
            loadKg: Value(
              type == TrackingType.bodyweight && mode == LoadMode.none
                  ? null
                  : load,
            ),
            reps: Value(_intOrNull(st, 'reps', min: 0, max: 1000)),
            isCompleted: Value(_bool(st, 'isCompleted')),
            completedAt: Value(_dateOrNull(st, 'completedAt')),
            setType: Value(switch (version) {
              1 => SetType.normal,
              2 => _bool(st, 'isWarmup') ? SetType.warmup : SetType.normal,
              _ => _enum(SetType.values, st, 'setType'),
            }),
            rpe: Value(v3 ? _numOrNull(st, 'rpe', min: 1, max: 10) : null),
            note: Value(v3 ? _strOrNull(st, 'note', max: 500) : null),
            durationSeconds: Value(
              v3 ? _intOrNull(st, 'durationSeconds', min: 0, max: 86400) : null,
            ),
            distanceM: Value(
              v3 ? _numOrNull(st, 'distanceM', min: 0, max: 1000000) : null,
            ),
          ),
        );
      }
      workoutExercises.add(
        ParsedWorkoutExercise(
          WorkoutExercisesCompanion.insert(
            workoutId: id,
            exerciseId: exId,
            position: _int(e, 'position', min: 0),
            targetRepsMin: Value(
              _intOrNull(e, 'targetRepsMin', min: 1, max: 100),
            ),
            targetRepsMax: Value(
              _intOrNull(e, 'targetRepsMax', min: 1, max: 100),
            ),
            note: Value(v3 ? _strOrNull(e, 'note', max: 500) : null),
            supersetGroup: Value(v3 ? _intOrNull(e, 'supersetGroup') : null),
            restSeconds: Value(v3 ? _restOrNull(e) : null),
            targetWeightKg: Value(v3 ? _targetOrNull(e) : null),
          ),
          sets,
        ),
      );
    }
  }

  // Body-weight log. v1 backups have none, so seed it like the v2 migration.
  final Map<DateTime, double> log;
  if (v2) {
    log = {};
    for (final raw in _list(m, 'bodyweight')) {
      final b = _map(raw, 'body-weight entry');
      final day = _localDay(b, 'date');
      if (log.containsKey(day)) _fail('more than one body weight per day');
      log[day] = _numOrNull(b, 'kg', min: 20, max: 400) ?? _fail('"kg" missing');
    }
  } else {
    snapshots.sort((a, b) => a.$1.compareTo(b.$1));
    log = bodyweightChanges(snapshots);
  }

  return ParsedBackup(
    settings: settings,
    exercises: exercises,
    folders: folders,
    templates: templates,
    templateItems: templateItems,
    workouts: workouts,
    workoutExercises: workoutExercises,
    bodyweight: [
      for (final MapEntry(:key, :value) in log.entries)
        BodyweightEntriesCompanion.insert(date: key, kg: value),
    ],
  );
}
