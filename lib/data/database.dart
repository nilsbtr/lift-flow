import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

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
}

@DataClassName('WorkoutTemplate')
class WorkoutTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get position => integer().withDefault(const Constant(0))();
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
  BoolColumn get isWarmup => boolean().withDefault(const Constant(false))();
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
    WorkoutTemplates,
    TemplateExercises,
    Workouts,
    WorkoutExercises,
    WorkoutSets,
    AppSettings,
    RestState,
    BodyweightEntries,
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
  int get schemaVersion => 2;

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
