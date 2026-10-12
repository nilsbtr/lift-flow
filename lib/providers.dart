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
import 'data/photo_repository.dart';
import 'data/photo_service.dart';
import 'data/photo_storage.dart';
import 'data/settings_repository.dart';
import 'data/template_repository.dart';
import 'data/workout_repository.dart';
import 'domain/exercise_search.dart';
import 'domain/home_widget.dart';
import 'domain/records.dart';
import 'domain/rest.dart';
import 'domain/shortcuts.dart';
import 'domain/stats.dart';
import 'services/app_lock.dart';
import 'services/home_widget.dart';
import 'services/notifications.dart';
import 'services/photo_picker.dart';
import 'services/shortcuts.dart';
import 'theme/dynamic_colors.dart';

// ------------------------------------------------------------ infrastructure

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final notificationsProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

final shortcutsProvider = Provider<ShortcutService>(
  (ref) => ShortcutService(),
);

/// Overridden in tests; the app asks the device itself.
final authenticatorProvider = Provider<Authenticator>(
  (ref) => DeviceAuthenticator(),
);

final initialSettingsProvider = Provider<UserSettings>(
  (ref) => throw UnimplementedError('initialSettingsProvider'),
);

final initialLiveWorkoutProvider = Provider<Workout?>((ref) => null);

final initialRestProvider = Provider<RestStateRow?>((ref) => null);

/// System colors, preloaded in main.dart. Null where the system has none.
final dynamicSchemesProvider = Provider<DynamicSchemes?>((ref) => null);

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
final photoRepoProvider = Provider(
  (ref) => PhotoRepository(ref.watch(databaseProvider)),
);

/// Looks up the photo folder on first use. Tests override it with a temp one.
final photoStorageProvider = Provider((ref) => PhotoStorage.appPrivate());
final photoServiceProvider = Provider(
  (ref) => PhotoService(
    ref.watch(photoRepoProvider),
    ref.watch(photoStorageProvider),
  ),
);
final photoPickerProvider = Provider((ref) => const PhotoPicker());

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

  /// Logs a weigh-in for [date] (today by default, never later), or moves the
  /// entry of the day [replacing] there. The current value is always that of
  /// the latest-dated entry.
  Future<void> logBodyweight(
    double kg, {
    DateTime? date,
    DateTime? replacing,
  }) async {
    final repo = ref.read(bodyweightRepoProvider);
    final now = DateTime.now();
    final day = date == null || date.isAfter(now) ? now : date;
    await (replacing == null
        ? repo.upsertDay(day, kg)
        : repo.move(replacing, day, kg));
    await setBodyweight((await repo.latest())?.kg);
  }

  /// Deletes an entry; the current value falls back to the latest remaining.
  Future<void> deleteBodyweightEntry(DateTime date) async {
    final repo = ref.read(bodyweightRepoProvider);
    await repo.delete(date);
    await setBodyweight((await repo.latest())?.kg);
  }

  /// Schedules the reminders the settings ask for. Call after anything that
  /// may have changed them: startup, resume, a change here, an import.
  Future<void> syncReminders() => ref
      .read(notificationsProvider)
      .syncReminders(state.reminderDays, state.reminderMinutes);

  Future<void> setReminders({int? days, int? minutes}) async {
    await update(
      AppSettingsCompanion(
        reminderDays: days == null ? const Value.absent() : Value(days),
        reminderMinutes: minutes == null
            ? const Value.absent()
            : Value(minutes),
      ),
    );
    await syncReminders();
  }

  Future<void> markBackedUp() =>
      update(AppSettingsCompanion(lastBackupAt: Value(DateTime.now())));

  Future<void> snoozeBackupNudge() =>
      update(AppSettingsCompanion(backupSnoozedAt: Value(DateTime.now())));

  Future<void> setWeeklyGoal(int? goal) =>
      update(AppSettingsCompanion(weeklyGoal: Value(goal?.clamp(1, 7))));
}

final settingsProvider = NotifierProvider<SettingsController, UserSettings>(
  SettingsController.new,
);

// ------------------------------------------------------------ app lock

/// How long the app may stay in the background before it asks again. Rests
/// run a few minutes and people check their phone meanwhile, so a shorter
/// grace would prompt on nearly every return during a workout.
const kLockGrace = Duration(minutes: 5);

class AppLockState {
  const AppLockState({this.locked = false, this.busy = false, this.failure});

  /// App content is hidden until the user authenticates.
  final bool locked;

  /// The system prompt is showing.
  final bool busy;

  /// Why the last unlock attempt didn't work.
  final AuthResult? failure;
}

/// Locks on a cold start and after [kLockGrace] in the background. While
/// locked, `AppLockGate` hides everything and blocks navigation.
class AppLockController extends Notifier<AppLockState> {
  DateTime? _hiddenAt;
  VoidCallback? _pending;

  @override
  AppLockState build() =>
      AppLockState(locked: ref.read(settingsProvider).appLock);

  bool get _enabled => ref.read(settingsProvider).appLock;

  /// The app left the screen: the grace period starts.
  void onHidden([DateTime? now]) {
    if (state.busy) return; // The prompt itself can background the app.
    if (state.locked) {
      _pending = null; // Abandoned, so don't run it at a much later unlock.
    } else if (_enabled) {
      _hiddenAt ??= now ?? DateTime.now();
    }
  }

  /// The app is back: locks it if it was away longer than [kLockGrace].
  void onShown([DateTime? now]) {
    _relockIfAway(now);
    _hiddenAt = null;
  }

  void _relockIfAway(DateTime? now) {
    final at = _hiddenAt;
    if (at == null || state.locked || !_enabled) return;
    final away = (now ?? DateTime.now()).difference(at);
    // A clock set back counts as away.
    if (away.isNegative || away >= kLockGrace) {
      _hiddenAt = null;
      state = const AppLockState(locked: true);
    }
  }

  /// Runs [action] now, or after the next unlock (only the latest waits).
  /// Intents like notification taps arrive before the resume event, so the
  /// grace period is checked here too.
  void whenUnlocked(VoidCallback action, [DateTime? now]) {
    _relockIfAway(now);
    if (state.locked) {
      _pending = action;
    } else {
      action();
    }
  }

  /// Shows the system prompt. A failed or cancelled prompt leaves it locked.
  Future<void> unlock() async {
    if (!state.locked || state.busy) return;
    state = const AppLockState(locked: true, busy: true);
    final result = await ref
        .read(authenticatorProvider)
        .authenticate('Unlock Lift Flow');
    if (!ref.mounted) return;
    if (result != AuthResult.success) {
      state = AppLockState(locked: true, failure: result);
      return;
    }
    state = const AppLockState();
    _hiddenAt = null;
    final run = _pending;
    _pending = null;
    run?.call();
  }

  /// Turns the lock on or off once the user has authenticated. A device
  /// without a screen lock can't authenticate, but may still turn it off.
  Future<AuthResult> setEnabled(bool enabled) async {
    if (state.busy) return AuthResult.failed;
    state = const AppLockState(busy: true);
    final result = await ref
        .read(authenticatorProvider)
        .authenticate(enabled ? 'Turn on app lock' : 'Turn off app lock');
    final done =
        result == AuthResult.success ||
        (!enabled && result == AuthResult.unavailable);
    if (done && ref.mounted) {
      await ref
          .read(settingsProvider.notifier)
          .update(AppSettingsCompanion(appLock: Value(enabled)));
    }
    if (!ref.mounted) return result;
    state = const AppLockState();
    _hiddenAt = null;
    return done ? AuthResult.success : result;
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
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

/// Progress photos, newest first.
final photosProvider = StreamProvider<List<ProgressPhoto>>(
  (ref) => ref.watch(photoRepoProvider).watchAll(),
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

/// Templates offered as launcher shortcuts, most recently used first.
final shortcutTemplatesProvider = Provider<List<WorkoutTemplate>>((ref) {
  final templates = ref.watch(templatesProvider).value ?? const [];
  final history = ref.watch(historyProvider).value ?? const <Workout>[];
  final live = ref.watch(liveWorkoutProvider);
  return shortcutTemplates(
    [for (final d in templates) d.template],
    [?live, ...history],
  );
});

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

// ------------------------------------------------------------ home widget

final homeWidgetProvider = Provider<HomeWidgetService>((ref) {
  final service = HomeWidgetService();
  ref.onDispose(service.dispose);
  return service;
});

/// What the home-screen widget shows; null until the data has loaded, so a
/// start doesn't blank the widget first.
final homeWidgetSnapshotProvider = Provider<HomeWidgetSnapshot?>((ref) {
  final templates = ref.watch(templatesProvider).value;
  final folders = ref.watch(templateFoldersProvider).value;
  final history = ref.watch(historyProvider).value;
  if (templates == null || folders == null || history == null) return null;
  final live = ref.watch(liveWorkoutProvider);
  return widgetSnapshot(
    history: history,
    firstDay: ref.watch(settingsProvider.select((s) => s.firstDayOfWeek)),
    now: DateTime.now(),
    next: nextTemplate(
      [for (final d in templates) d.template],
      folders,
      [?live, ...history],
    ),
    live: live,
  );
});
