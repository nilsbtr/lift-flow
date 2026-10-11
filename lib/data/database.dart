import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/muscles.dart';
import 'database.steps.dart';
import 'enums.dart';

export 'enums.dart';

part 'database.g.dart';

/// Body-weight log seeded from dated snapshots, ordered by time: one entry
/// per local day wherever the value changed. Later snapshots of a day win.
Map<DateTime, double> bodyweightChanges(Iterable<(DateTime, double)> points) {
  final log = <DateTime, double>{};
  double? last;
  for (final (at, kg) in points) {
    if (last != null && (kg - last).abs() < 1e-6) continue;
    log[DateTime(at.year, at.month, at.day)] = kg;
    last = kg;
  }
  return log;
}

/// Stores muscle groups as comma-separated enum names, skipping unknown ones.
/// Equal texts map to the same list, so data classes stay comparable.
class MuscleGroupsConverter extends TypeConverter<List<MuscleGroup>, String> {
  const MuscleGroupsConverter();

  static final _cache = <String, List<MuscleGroup>>{};

  @override
  List<MuscleGroup> fromSql(String fromDb) =>
      _cache[fromDb] ??= List.unmodifiable([
        for (final name in fromDb.split(','))
          for (final g in MuscleGroup.values)
            if (g.name == name) g,
      ]);

  @override
  String toSql(List<MuscleGroup> value) => value.map((g) => g.name).join(',');
}

@DataClassName('Exercise')
@TableIndex(name: 'idx_exercises_archived', columns: {#isArchived})
class Exercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get muscleGroup => textEnum<MuscleGroup>()();
  TextColumn get trackingType => textEnum<TrackingType>()();
  TextColumn get loadMode =>
      textEnum<LoadMode>().withDefault(Constant(LoadMode.none.name))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get equipment =>
      textEnum<Equipment>().withDefault(Constant(Equipment.none.name))();

  /// Reps are entered for one side, so volume counts them twice.
  BoolColumn get perSide => boolean().withDefault(const Constant(false))();

  /// The load is entered for one dumbbell, so volume counts it twice.
  BoolColumn get perDumbbell => boolean().withDefault(const Constant(false))();
  TextColumn get secondaryMuscles => text()
      .map(const MuscleGroupsConverter())
      .withDefault(const Constant(''))();
}

@DataClassName('TemplateFolder')
class TemplateFolders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get position => integer().withDefault(const Constant(0))();
  BoolColumn get isCollapsed => boolean().withDefault(const Constant(false))();
}

@DataClassName('WorkoutTemplate')
@TableIndex(name: 'idx_workout_templates_folder', columns: {#folderId})
class WorkoutTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get position => integer().withDefault(const Constant(0))();

  /// Null for templates outside any folder.
  IntColumn get folderId => integer().nullable().references(
    TemplateFolders,
    #id,
    onDelete: KeyAction.setNull,
  )();
}

@DataClassName('TemplateExercise')
@TableIndex(name: 'idx_template_exercises_template', columns: {#templateId})
@TableIndex(name: 'idx_template_exercises_exercise', columns: {#exerciseId})
class TemplateExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get templateId => integer().references(
    WorkoutTemplates,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get exerciseId =>
      integer().references(Exercises, #id, onDelete: KeyAction.restrict)();
  IntColumn get position => integer()();
  IntColumn get targetSets => integer().withDefault(const Constant(3))();
  IntColumn get repsMin => integer().nullable()();
  IntColumn get repsMax => integer().nullable()();

  /// Rest after a set. Null uses the default from settings.
  IntColumn get restSeconds => integer().nullable()();
  RealColumn get targetWeightKg => real().nullable()();

  /// Rows of one template sharing a value form a superset.
  IntColumn get supersetGroup => integer().nullable()();
}

@DataClassName('Workout')
@TableIndex(name: 'idx_workouts_template', columns: {#templateId})
@TableIndex(name: 'idx_workouts_ended', columns: {#endedAt})
@TableIndex(name: 'idx_workouts_started', columns: {#startedAt})
class Workouts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get templateId => integer().nullable().references(
    WorkoutTemplates,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get name => text()();
  DateTimeColumn get startedAt => dateTime()();

  /// Null while the workout is live.
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// Body weight snapshot at finish time (kg).
  RealColumn get bodyweightKg => real().nullable()();
  IntColumn get totalSets => integer().withDefault(const Constant(0))();
  RealColumn get totalVolumeKg => real().withDefault(const Constant(0))();
  IntColumn get exerciseCount => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
}

@DataClassName('WorkoutExercise')
@TableIndex(name: 'idx_workout_exercises_workout', columns: {#workoutId})
@TableIndex(name: 'idx_workout_exercises_exercise', columns: {#exerciseId})
class WorkoutExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workoutId =>
      integer().references(Workouts, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId =>
      integer().references(Exercises, #id, onDelete: KeyAction.restrict)();
  IntColumn get position => integer()();
  IntColumn get targetRepsMin => integer().nullable()();
  IntColumn get targetRepsMax => integer().nullable()();
  TextColumn get note => text().nullable()();

  /// Rows of one workout sharing a value form a superset.
  IntColumn get supersetGroup => integer().nullable()();

  /// Rest after a set. Null uses the default from settings.
  IntColumn get restSeconds => integer().nullable()();
  RealColumn get targetWeightKg => real().nullable()();
}

@DataClassName('WorkoutSet')
@TableIndex(name: 'idx_workout_sets_exercise', columns: {#workoutExerciseId})
class WorkoutSets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workoutExerciseId => integer().references(
    WorkoutExercises,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get position => integer()();

  /// Canonical kg. Signed for bodyweight exercises (assisted < 0).
  RealColumn get loadKg => real().nullable()();
  IntColumn get reps => integer().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get setType =>
      textEnum<SetType>().withDefault(Constant(SetType.normal.name))();

  /// RPE 1–10 in 0.5 steps. RIR is shown as 10 − RPE.
  RealColumn get rpe => real().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
  RealColumn get distanceM => real().nullable()();
}

@DataClassName('UserSettings')
class AppSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get weightUnit =>
      textEnum<WeightUnit>().withDefault(Constant(WeightUnit.kg.name))();
  TextColumn get themeMode =>
      textEnum<ThemePref>().withDefault(Constant(ThemePref.system.name))();
  BoolColumn get pureBlack => boolean().withDefault(const Constant(false))();
  RealColumn get bodyweightKg => real().nullable()();
  IntColumn get defaultRestSeconds =>
      integer().withDefault(const Constant(90))();
  BoolColumn get autoStartRest => boolean().withDefault(const Constant(true))();
  BoolColumn get restAlerts => boolean().withDefault(const Constant(true))();
  BoolColumn get keepScreenOn => boolean().withDefault(const Constant(false))();
  BoolColumn get permissionsPrompted =>
      boolean().withDefault(const Constant(false))();

  /// Workouts per week, 1–7. Null when off.
  IntColumn get weeklyGoal => integer().nullable()();
  TextColumn get effortMode =>
      textEnum<EffortMode>().withDefault(Constant(EffortMode.off.name))();
  BoolColumn get restSound => boolean().withDefault(const Constant(false))();

  /// [DateTime.monday] … [DateTime.sunday].
  IntColumn get firstDayOfWeek =>
      integer().withDefault(const Constant(DateTime.monday))();

  /// Null uses the default bar for the current unit.
  RealColumn get barWeightKg => real().nullable()();

  /// Comma-separated kg values. Null uses the default set for the current unit.
  TextColumn get plates => text().nullable()();

  /// Target band of weekly sets per muscle group.
  IntColumn get balanceMin => integer().withDefault(const Constant(10))();
  IntColumn get balanceMax => integer().withDefault(const Constant(20))();
  DateTimeColumn get lastBackupAt => dateTime().nullable()();
  DateTimeColumn get backupSnoozedAt => dateTime().nullable()();
  BoolColumn get appLock => boolean().withDefault(const Constant(false))();
  BoolColumn get dynamicColor => boolean().withDefault(const Constant(false))();

  /// Bitmask of days: bit 0 is Monday, bit 6 is Sunday.
  IntColumn get reminderDays => integer().withDefault(const Constant(0))();

  /// Minutes after midnight.
  IntColumn get reminderMinutes =>
      integer().withDefault(const Constant(1080))();
  BoolColumn get setMenuHintSeen =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One body-weight entry per day.
@DataClassName('BodyweightEntry')
class BodyweightEntries extends Table {
  /// Local midnight.
  DateTimeColumn get date => dateTime()();
  RealColumn get kg => real()();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

@DataClassName('ProgressPhoto')
class ProgressPhotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get takenAt => dateTime()();

  /// File name relative to the app's photo directory.
  TextColumn get fileName => text()();
  TextColumn get note => text().nullable()();
}

@DataClassName('RestStateRow')
class RestState extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  DateTimeColumn get endsAt => dateTime()();
  IntColumn get totalSeconds => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Exercises,
    TemplateFolders,
    WorkoutTemplates,
    TemplateExercises,
    Workouts,
    WorkoutExercises,
    WorkoutSets,
    AppSettings,
    RestState,
    BodyweightEntries,
    ProgressPhotos,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  static QueryExecutor _open() => driftDatabase(
    name: 'lift_flow',
    native: const DriftNativeOptions(
      databaseDirectory: getApplicationSupportDirectory,
    ),
  );

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.addColumn(schema.workoutSets, schema.workoutSets.isWarmup);
        await m.addColumn(schema.appSettings, schema.appSettings.weeklyGoal);
        await m.createTable(schema.bodyweightEntries);
        final rows = await customSelect(
          'SELECT started_at, bodyweight_kg FROM workouts '
          'WHERE ended_at IS NOT NULL AND bodyweight_kg IS NOT NULL '
          'ORDER BY started_at',
          readsFrom: {},
        ).get();
        final log = bodyweightChanges([
          for (final r in rows)
            (r.read<DateTime>('started_at'), r.read<double>('bodyweight_kg')),
        ]);
        for (final MapEntry(:key, :value) in log.entries) {
          await customInsert(
            'INSERT INTO bodyweight_entries (date, kg) VALUES (?, ?)',
            variables: [Variable<DateTime>(key), Variable<double>(value)],
          );
        }
      },
      from2To3: (m, schema) async {
        final e = schema.exercises;
        await m.addColumn(e, e.equipment);
        await m.addColumn(e, e.perSide);
        await m.addColumn(e, e.perDumbbell);
        await m.addColumn(e, e.secondaryMuscles);
        await m.createTable(schema.templateFolders);
        await m.addColumn(
          schema.workoutTemplates,
          schema.workoutTemplates.folderId,
        );
        await m.createIndex(schema.idxWorkoutTemplatesFolder);
        final te = schema.templateExercises;
        await m.addColumn(te, te.restSeconds);
        await m.addColumn(te, te.targetWeightKg);
        await m.addColumn(te, te.supersetGroup);
        await m.addColumn(schema.workouts, schema.workouts.note);
        final we = schema.workoutExercises;
        await m.addColumn(we, we.note);
        await m.addColumn(we, we.supersetGroup);
        await m.addColumn(we, we.restSeconds);
        await m.addColumn(we, we.targetWeightKg);
        // Rebuilds the table, turning is_warmup into set_type.
        final s = schema.workoutSets;
        await m.alterTable(
          TableMigration(
            s,
            columnTransformer: {
              s.setType: const CustomExpression<String>(
                "CASE WHEN is_warmup = 1 THEN 'warmup' ELSE 'normal' END",
              ),
            },
            newColumns: [
              s.setType,
              s.rpe,
              s.note,
              s.durationSeconds,
              s.distanceM,
            ],
          ),
        );
        final a = schema.appSettings;
        for (final c in [
          a.effortMode,
          a.restSound,
          a.firstDayOfWeek,
          a.barWeightKg,
          a.plates,
          a.balanceMin,
          a.balanceMax,
          a.lastBackupAt,
          a.backupSnoozedAt,
          a.appLock,
          a.dynamicColor,
          a.reminderDays,
          a.reminderMinutes,
          a.setMenuHintSeen,
        ]) {
          await m.addColumn(a, c);
        }
        await m.createTable(schema.progressPhotos);

        final legacy = await customSelect(
          'SELECT id, name, muscle_group FROM exercises '
          "WHERE muscle_group IN ('arms', 'legs')",
          readsFrom: {},
        ).get();
        for (final r in legacy) {
          final from = MuscleGroup.values.byName(
            r.read<String>('muscle_group'),
          );
          final to = refineMuscleGroup(r.read<String>('name'), from);
          if (to == from) continue;
          await customUpdate(
            'UPDATE exercises SET muscle_group = ? WHERE id = ?',
            variables: [
              Variable<String>(to.name),
              Variable<int>(r.read<int>('id')),
            ],
          );
        }
      },
    ),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      if (executor.dialect == SqlDialect.sqlite) {
        await customStatement('PRAGMA journal_mode = WAL');
        await customStatement('PRAGMA synchronous = NORMAL');
      }
      // Earlier builds inserted without an explicit id, adding a row per launch.
      await (delete(appSettings)..where((s) => s.id.equals(1).not())).go();
      await into(appSettings).insert(
        const AppSettingsCompanion(id: Value(1)),
        mode: InsertMode.insertOrIgnore,
      );
    },
  );
}
