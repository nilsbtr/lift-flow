# AGENTS.md

Lift Flow is a local-only Flutter gym tracker (Android first). See [README.md](README.md) for features and layout.

## Commands

- Codegen after editing `lib/data/database.dart`: `dart run build_runner build` (build_runner 2.16 no longer has `--delete-conflicting-outputs`).
- Validate every change with `flutter analyze` and `flutter test`. Run `flutter build bundle` too: it catches kernel compile errors that analyze/test miss.
- Android package id: `com.nilsbtr.liftflow`. Clear app data with `adb shell pm clear com.nilsbtr.liftflow`. Read startup errors with `adb logcat -d -s flutter:*`.

## Conventions

- Import `package:material_ui/material_ui.dart`, never `package:flutter/material.dart`.
- Relative imports inside `lib/`. Lints are strict (`strict-casts`, `strict-inference`, `strict-raw-types`, `unawaited_futures`, `prefer_final_locals`). Wrap fire-and-forget futures in `unawaited(...)`.
- Keep code terse and match the surrounding style. Add a short comment only when the code can't explain itself.
- User-facing copy is English, sentence case, and short. Use `’` in text and `kMinus`/`kTimes` from `domain/units.dart` for `−`/`×`.

## Architecture

- **Data** (`lib/data/`): drift tables live in `database.dart` (schema v3), enums in `enums.dart` (re-exported). Repositories wrap all queries; UI never touches `AppDatabase` directly.
- **Providers** (`lib/providers.dart`): repo providers, `StreamProvider`s over drift `watch*()`, `settingsProvider` (Notifier), `restTimerProvider`, `liveWorkoutProvider`. `databaseProvider` and the `initial*Provider`s are overridden in `main.dart` with values preloaded before `runApp`, so the first frame has no loading state.
- **Workout editing**: `workoutEditorProvider(id)` (`features/workout/workout_controller.dart`) is an `AsyncNotifier` family. Edits update state right away and are written to the DB after a 400 ms debounce, plus a flush on blur, pause, or dispose. Live workouts are kept alive.
- **Domain** (`lib/domain/`): pure functions, which are what the unit tests cover. `units.dart` handles kg↔lb, parsing, and formatting. `records.dart` handles volume, Epley e1RM, and PRs. `stats.dart` handles weeks, trends, and muscle balance. `muscles.dart` remaps legacy muscle groups.
- **Routing** (`router.dart`): tabs are `/`, `/history`, `/progress`, `/gym`, `/settings`. Full-screen routes (`/workout`, `…/edit`, `/gym/template/:templateId`) use `parentNavigatorKey: rootNavigatorKey`. Detail screens are nested in every tab that links to them (`_exerciseRoute`, `_workoutRoute`), so navigation never jumps tabs. Link with `go` to a path in the current tab (`WorkoutDetailScreen` builds on `GoRouterState.of(context).matchedLocation`). Use `push` only for full-screen editors that pop back. The Gym segment is in the URL (`/gym?tab=templates`). Back from a tab root goes to Home.

## Rules and gotchas

- **Units**: always store kg. Convert only at the UI edge with `kgToUnit`/`unitToKg`/`fmtWeight`. Bodyweight loads are signed: `added` ≥ 0, `assisted` ≤ 0, `none` is null.
- **Set types**: `WorkoutSets.setType` (`SetType`) replaced the old warm-up flag. Only `warmup` is left out of totals, facts, and records (`setType.isWarmup`); drop, failure, and AMRAP sets are working sets.
- **Volume**: use `setVolume`/`SetFact.volume`, which apply the exercise's `perSide` (reps ×2) and `perDumbbell` (load ×2) flags. Records and e1RM use the entered load.
- **Muscle groups**: `arms` and `legs` are legacy values kept for old data and backups. Offer `MuscleGroup.selectable` (or `selectableWith` to keep an exercise's current legacy group) in pickers. In balance stats a set counts 1 for the primary group and 0.5 for each of `secondaryMuscles`.
- **Weeks**: start on `AppSettings.firstDayOfWeek`. Pass it to `weekStart`, `weeklyStats`, `weekStreak`, and `DotCalendar`; never assume Monday.
- **Singleton rows** (`AppSettings`, `RestState`): always write with `id: Value(1)`. Leaving the id out creates a new rowid and duplicates the row.
- **Schema changes**: bump `schemaVersion`, add a migration step, and export schemas (`dart run drift_dev make-migrations`, configured in `build.yaml`). Update `BackupService` export/parse and `kBackupVersion` (now 3) when the shape changes; older versions must keep importing with defaults. Device-local settings (`permissionsPrompted`, `lastBackupAt`, `backupSnoozedAt`, `appLock`, `setMenuHintSeen`) are not exported and reset on import. `ProgressPhotos` stays out of backups, and import and delete-all leave it alone.
- **Isolates**: `Isolate.run` closures inside instance methods capture `this` (the DB can't be sent). Use static closure factories, as in `BackupService._encoder`/`_parser`.
- **Riverpod 3**: family notifiers get their argument through the constructor. Use `AsyncValue.value` (there is no `valueOrNull`). `KeepAliveLink` comes from `package:flutter_riverpod/misc.dart`.
- **Sheets**: use `showAppSheet` (`widgets/common.dart`). It uses the root navigator and pads for both the keyboard and the gesture bar.
- **Timers in UI**: use `PeriodicBuilder` with an `anchor`, not a raw `Timer`/`setState`.

## Theme and icons

- Use tokens from `theme/tokens.dart` (`Space`, `Radii`, `Motion.of(context, …)`, `IconSizes`, `kMinTap`), not magic numbers. Semantic colors come from `LiftColors.of(context)`: `done` (green), `rest` (yellow), `record` (red), `raised`, `muted`. Everything else comes from `ColorScheme`.
- The text theme defines explicit sizes. Use `Theme.of(context).textTheme` styles and don't hard-code font sizes.
- Icons: use `AppIcon(AppIcons.x)`, not `Icon`/`Icons`. To add an icon, put `name.svg` (14×14 viewBox, Streamline Flex from `api.iconify.design/streamline-flex.json`) in `assets/icons/`, then add `static const x = AppIconData('name')` to `AppIcons`. Icons are precached at startup automatically. Don't use icon-font packages (`flexicon` and `phosphor_flutter` are broken here).
- Launcher icon padding is set by `adaptive_icon_foreground_inset` in `pubspec.yaml`. Don't rescale the PNG.

## Tests

`test/app_test.dart` runs against `AppDatabase(NativeDatabase.memory())`. Add tests there for repository, domain, and backup logic when you change it. Stats live in `test/stats_test.dart`; `test/drift/lift_flow/migration_test.dart` covers every schema step, with data for the steps that convert it.
