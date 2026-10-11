import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'data/backup_service.dart';
import 'data/bodyweight_repository.dart';
import 'data/database.dart';
import 'data/exercise_repository.dart';
import 'data/settings_repository.dart';
import 'data/template_repository.dart';
import 'data/workout_repository.dart';
import 'domain/exercise_search.dart';
import 'domain/records.dart';
import 'domain/rest.dart';
import 'domain/stats.dart';
import 'services/notifications.dart';

// ------------------------------------------------------------ infrastructure

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final notificationsProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

final initialSettingsProvider = Provider<UserSettings>(
  (ref) => throw UnimplementedError('initialSettingsProvider'),
);

final initialLiveWorkoutProvider = Provider<Workout?>((ref) => null);

final initialRestProvider = Provider<RestStateRow?>((ref) => null);

/// Overridden in main.dart; the fallback keeps tests that skip the override working.
final initialPackageInfoProvider = Provider<PackageInfo>(
  (ref) => PackageInfo(
    appName: 'Lift Flow',
    packageName: '',
    version: '0.0.0',
    buildNumber: '0',
  ),
);

final exerciseRepoProvider = Provider(
  (ref) => ExerciseRepository(ref.watch(databaseProvider)),
);
final templateRepoProvider = Provider(
  (ref) => TemplateRepository(ref.watch(databaseProvider)),
);
final workoutRepoProvider = Provider(
  (ref) => WorkoutRepository(ref.watch(databaseProvider)),
);
final settingsRepoProvider = Provider(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);
final restRepoProvider = Provider(
  (ref) => RestRepository(ref.watch(databaseProvider)),
);
final backupProvider = Provider(
  (ref) => BackupService(ref.watch(databaseProvider)),
);
final bodyweightRepoProvider = Provider(
  (ref) => BodyweightRepository(ref.watch(databaseProvider)),
);

// ------------------------------------------------------------ settings

class SettingsController extends Notifier<UserSettings> {
  @override
  UserSettings build() => ref.read(initialSettingsProvider);

  Future<void> update(AppSettingsCompanion changes) async {
    final repo = ref.read(settingsRepoProvider);
    await repo.write(changes);
    state = await repo.get();
  }

  Future<void> reload() async {
    state = await ref.read(settingsRepoProvider).get();
  }

  Future<void> setBodyweight(double? kg) =>
      update(AppSettingsCompanion(bodyweightKg: Value(kg)));

  /// Logs today's body weight and makes it the current value.
  Future<void> logBodyweight(double kg) async {
    await ref.read(bodyweightRepoProvider).upsertDay(DateTime.now(), kg);
    await setBodyweight(kg);
  }

  /// Deletes an entry; the current value falls back to the latest remaining.
  Future<void> deleteBodyweightEntry(DateTime date) async {
    final repo = ref.read(bodyweightRepoProvider);
    await repo.delete(date);
    await setBodyweight((await repo.latest())?.kg);
  }

  Future<void> setWeeklyGoal(int? goal) =>
      update(AppSettingsCompanion(weeklyGoal: Value(goal?.clamp(1, 7))));
}

final settingsProvider = NotifierProvider<SettingsController, UserSettings>(
  SettingsController.new,
);

// ------------------------------------------------------------ data streams

final exercisesProvider = StreamProvider<List<Exercise>>(
  (ref) => ref.watch(exerciseRepoProvider).watchActive(),
);

final archivedExercisesProvider = StreamProvider.autoDispose<List<Exercise>>(
  (ref) => ref.watch(exerciseRepoProvider).watchArchived(),
);

final exerciseProvider = StreamProvider.autoDispose.family<Exercise?, int>(
  (ref, id) => ref.watch(exerciseRepoProvider).watchById(id),
);

final exerciseSessionsProvider = StreamProvider.autoDispose
    .family<List<ExerciseSession>, int>(
      (ref, id) => ref.watch(workoutRepoProvider).watchExerciseSessions(id),
    );

final exerciseUsageProvider = StreamProvider<Map<int, ExerciseUsage>>(
  (ref) => ref.watch(workoutRepoProvider).watchExerciseUsage(),
);

final templatesProvider = StreamProvider<List<TemplateDetail>>(
  (ref) => ref.watch(templateRepoProvider).watchAll(),
);

final templateFoldersProvider = StreamProvider<List<TemplateFolder>>(
  (ref) => ref.watch(templateRepoProvider).watchFolders(),
);

final historyProvider = StreamProvider<List<Workout>>(
  (ref) => ref.watch(workoutRepoProvider).watchHistory(),
);

final bodyweightEntriesProvider =
    StreamProvider.autoDispose<List<BodyweightEntry>>(
      (ref) => ref.watch(bodyweightRepoProvider).watchAll(),
    );

final workoutDetailProvider = StreamProvider.autoDispose
    .family<LoadedWorkout?, int>(
      (ref, id) => ref.watch(workoutRepoProvider).watchLoaded(id),
    );

final workoutInsightsProvider = FutureProvider.autoDispose
    .family<WorkoutInsights?, int>((ref, id) async {
      final loaded = await ref.watch(workoutDetailProvider(id).future);
      if (loaded == null) return null;
      final history = await ref.watch(historyProvider.future);
      final facts = await ref
          .read(workoutRepoProvider)
          .setFacts(loaded.exercises.map((e) => e.exercise.id));
      return workoutInsights(
        workout: loaded.workout,
        facts: facts,
        history: history,
      );
    });

final workoutPrsProvider = FutureProvider.autoDispose
    .family<Map<int, Set<PrKind>>, int>(
      (ref, id) async =>
          (await ref.watch(workoutInsightsProvider(id).future))?.prs ??
          const {},
    );

class WeekSummary {
  const WeekSummary({
    required this.workouts,
    required this.goal,
    required this.streak,
  });

  /// Finished workouts this week.
  final int workouts;
  final int? goal;

  /// Weeks in a row meeting the goal (or with a workout when it's off).
  final int streak;
}

final weekSummaryProvider = Provider.autoDispose<WeekSummary>((ref) {
  final history = ref.watch(historyProvider).value ?? const <Workout>[];
  final goal = ref.watch(settingsProvider.select((s) => s.weeklyGoal));
  final firstDay = ref.watch(settingsProvider.select((s) => s.firstDayOfWeek));
  final now = DateTime.now();
  final start = weekStart(now, firstDay);
  return WeekSummary(
    workouts: history.where((w) => !w.startedAt.isBefore(start)).length,
    goal: goal,
    streak: weekStreak(history, now: now, goal: goal, firstDay: firstDay),
  );
});

final _liveStreamProvider = StreamProvider<Workout?>(
  (ref) => ref.watch(workoutRepoProvider).watchLive(),
);

/// The live (unfinished) workout, seeded with the value preloaded at startup.
final liveWorkoutProvider = Provider<Workout?>((ref) {
  final async = ref.watch(_liveStreamProvider);
  if (async.hasValue) return async.value;
  return ref.read(initialLiveWorkoutProvider);
});

/// Live workouts already asked about being forgotten in this app session.
final forgottenAskedProvider = Provider<Set<int>>((ref) => {});

// ------------------------------------------------------------ rest timer

class RestTimerState {
  const RestTimerState(this.endsAt, this.totalSeconds);
  final DateTime endsAt;
  final int totalSeconds;

  int remainingSeconds([DateTime? now]) {
    final ms = endsAt.difference(now ?? DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  double progress([DateTime? now]) {
    if (totalSeconds <= 0) return 0;
    final ms = endsAt.difference(now ?? DateTime.now()).inMilliseconds;
    return (ms / (totalSeconds * 1000)).clamp(0.0, 1.0);
  }
}

class RestTimerController extends Notifier<RestTimerState?> {
  Timer? _end;

  @override
  RestTimerState? build() {
    ref.onDispose(() => _end?.cancel());
    final s = _fromRow(ref.read(initialRestProvider));
    if (s != null) _arm(s);
    return s;
  }

  static RestTimerState? _fromRow(RestStateRow? row) =>
      row == null || !row.endsAt.isAfter(DateTime.now())
      ? null
      : RestTimerState(row.endsAt, row.totalSeconds);

  /// Re-reads the persisted rest, which a notification action may have changed.
  Future<void> reload() async {
    final s = _fromRow(await ref.read(restRepoProvider).get());
    if (!ref.mounted) return;
    final cur = state;
    if (s?.endsAt == cur?.endsAt && s?.totalSeconds == cur?.totalSeconds) {
      return;
    }
    _end?.cancel();
    state = s;
    if (s != null) _arm(s);
  }

  void start(int seconds) {
    if (seconds <= 0) return;
    seconds = seconds.clamp(1, kMaxRestSeconds);
    _set(
      RestTimerState(DateTime.now().add(Duration(seconds: seconds)), seconds),
    );
  }

  void adjust(int deltaSeconds) {
    final s = state;
    if (s == null) return;
    final next = adjustRest(
      s.endsAt,
      s.totalSeconds,
      deltaSeconds,
      DateTime.now(),
    );
    if (next == null) {
      skip();
      return;
    }
    _set(RestTimerState(next.endsAt, next.totalSeconds));
  }

  void skip() {
    _end?.cancel();
    state = null;
    unawaited(ref.read(restRepoProvider).clear());
  }

  void _set(RestTimerState s) {
    state = s;
    _arm(s);
    unawaited(ref.read(restRepoProvider).save(s.endsAt, s.totalSeconds));
  }

  /// A hidden app gets the scheduled alert instead.
  static bool get _inForeground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null ||
        s == AppLifecycleState.resumed ||
        s == AppLifecycleState.inactive;
  }

  void _arm(RestTimerState s) {
    _end?.cancel();
    _end = Timer(s.endsAt.difference(DateTime.now()), () {
      if (state != s) return;
      unawaited(HapticFeedback.heavyImpact());
      unawaited(HapticFeedback.vibrate());
      if (_inForeground && ref.read(settingsProvider).restSound) {
        unawaited(ref.read(notificationsProvider).playRestSound());
      }
      skip();
    });
  }
}

final restTimerProvider =
    NotifierProvider<RestTimerController, RestTimerState?>(
      RestTimerController.new,
    );
