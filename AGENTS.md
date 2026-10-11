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
- **Finishing**: `WorkoutEditor.finish({endedAt})` ends a live workout at that time (kept between start and now) and names a workout still called `kDefaultWorkoutName` from its muscles. `markAllDone()` completes sets with `DraftExercise.completion`, which must stay in step with `toggleDone`; marked sets get no `completedAt`, so they stay out of the timeline and the "last set" time. The finish dialogs live in `finish_dialogs.dart`.
- **Domain** (`lib/domain/`): pure functions, which are what the unit tests cover. `units.dart` handles kg↔lb, parsing, and formatting. `records.dart` handles volume, Epley e1RM, and PRs. `stats.dart` handles weeks, trends, and muscle balance. `muscles.dart` remaps legacy muscle groups. `rest.dart` has the rest adjustments, presets, and time parsing. `finish.dart` has the stale-set and forgotten-workout rules. `workout_name.dart` suggests a workout name.
- **Routing** (`router.dart`): tabs are `/`, `/history`, `/progress`, `/gym`, `/settings`. Full-screen routes (`/workout`, `…/edit`, `/gym/template/:templateId`) use `parentNavigatorKey: rootNavigatorKey`. Detail screens are nested in every tab that links to them (`_exerciseRoute`, `_workoutRoute`), so navigation never jumps tabs. Workout detail lives at `/workouts/:id` (Home), `/history/:id` and `/progress/workout/:id`. Exercise and workout pages link to each other, so those routes nest (`/gym/exercise/1/workout/2`) with numbered path parameters and stop after two hops; `ExerciseDetailScreen.canOpenWorkouts` is false where they stop. To show a day’s workouts, use `showWorkoutDaySheet` (`features/history/workout_day_sheet.dart`) with a `workoutPath` into the current tab. Log past workout creates a finished, empty workout (`createPast`) and opens `/history/log/:id`, which drops it if you leave without a logged set; `purgeEmpty` cleans up after a killed app. Link with `go` to a path in the current tab (`WorkoutDetailScreen` builds on `GoRouterState.of(context).matchedLocation`). Use `push` only for full-screen editors that pop back. The Gym segment is in the URL (`/gym?tab=templates`). Back from a tab root goes to Home.

## Rules and gotchas

- **Units**: always store kg. Convert only at the UI edge with `kgToUnit`/`unitToKg`/`fmtWeight`. Bodyweight loads are signed: `added` ≥ 0, `assisted` ≤ 0, `none` is null.
- **Set types**: `WorkoutSets.setType` (`SetType`) replaced the old warm-up flag. Only `warmup` is left out of totals, facts, and records (`setType.isWarmup`); drop, failure, and AMRAP sets are working sets.
- **Volume**: use `setVolume`/`SetFact.volume`, which apply the exercise's `perSide` (reps ×2) and `perDumbbell` (load ×2) flags. Records and e1RM use the entered load.
- **Muscle groups**: `arms` and `legs` are legacy values kept for old data and backups. Offer `MuscleGroup.selectable` (or `selectableWith` to keep an exercise's current legacy group) in pickers. In balance stats a set counts 1 for the primary group and 0.5 for each of `secondaryMuscles`.
- **Weeks**: start on `AppSettings.firstDayOfWeek`. Pass it to `weekStart`, `weeklyStats`, `weekStreak`, and `DotCalendar`; never assume Monday.
- **Singleton rows** (`AppSettings`, `RestState`): always write with `id: Value(1)`. Leaving the id out creates a new rowid and duplicates the row.
- **Schema changes**: bump `schemaVersion`, add a migration step, and export schemas (`dart run drift_dev make-migrations`, configured in `build.yaml`). Update `BackupService` export/parse and `kBackupVersion` (now 3) when the shape changes; older versions must keep importing with defaults. Device-local settings (`permissionsPrompted`, `lastBackupAt`, `backupSnoozedAt`, `appLock`, `setMenuHintSeen`) are not exported and reset on import. `ProgressPhotos` stays out of backups, and import and delete-all leave it alone.
- **Isolates**: `Isolate.run` closures inside instance methods capture `this` (the DB can't be sent). Use static closure factories, as in `BackupService._encoder`/`_parser`.
- **Notifications** (`services/notifications.dart`): id 1 is the workout notification (channel `workout_ongoing`), 2 the scheduled rest-over alert, 3 the rest countdown (`rest_ongoing`, times out by itself). Skip and +30 s run in `onNotificationAction`, a top-level entry point in a separate isolate that also runs when the app process is dead. It opens its own `AppDatabase` (no providers or app state), updates the `RestState` row with `applyRestAction`, re-posts the notifications, and pings the app isolate through `IsolateNameServer`, which calls `restTimerProvider.notifier.reload()` (also done on resume). Channel settings are fixed once created, so change a channel's behavior with a new id. With `restSound` on, a rest that ends naturally while the app is in the foreground calls `playRestSound`: Android has no other system sound API, so it posts id 4 on its own `rest_sound` channel (a sound, no pop-up) that times out after 4 s. It never plays on Skip, and a hidden app gets the scheduled alert instead.
- **Riverpod 3**: family notifiers get their argument through the constructor. Use `AsyncValue.value` (there is no `valueOrNull`). `KeepAliveLink` comes from `package:flutter_riverpod/misc.dart`.
- **Sheets**: use `showAppSheet` (`widgets/common.dart`). It uses the root navigator and pads for both the keyboard and the gesture bar.
- **Timers in UI**: use `PeriodicBuilder` with an `anchor`, not a raw `Timer`/`setState`.
- **Templates**: supersets are neighboring template or workout exercises sharing a `supersetGroup`. Use `domain/superset_groups.dart` (`normalizeGroups`, `toggleLinkWithNext`, `reorderGroupIndices`) and `normalizedSupersets` before `TemplateRepository.save`; save itself does not clean up. Folder collapse is stored (`TemplateFolders.isCollapsed`) and shared by Home and Gym. Group templates with `groupTemplates` and reorder within a section with `reorderWithin`. Rep targets are edited in two digit-only fields (`parseRepsFields`). An assisted exercise’s target weight is stored negative.
- **Set delete**: delete sets in the workout screen with `removeSetWithUndo` (`set_menu_sheet.dart`). `WorkoutEditor.removeSet` only hides the set; `commitDelete` writes it when the snackbar closes and on finish, discard, pause, and dispose. A new command that ends or leaves the workout must call `commitDelete` first.
- **Set rows**: the header and rows share their column widths through `SetCols.fit`, which lets Previous shrink before the inputs at large text sizes. Add a column there, not as a fixed `SizedBox`. List finished sets with `SetList` (`widgets/set_list.dart`) and label them with `setLabels`/`setTypeColor`.
- **Effort**: `WorkoutSets.rpe` is always RPE. Convert at the UI edge with `fmtEffort`/`fmtEffortLabel`/`parseEffort` and `AppSettings.effortMode`, and show nothing when the mode is off.

## Theme and icons

- Use tokens from `theme/tokens.dart` (`Space`, `Radii`, `Motion.of(context, …)`, `IconSizes`, `kMinTap`), not magic numbers. Semantic colors come from `LiftColors.of(context)`: `done` (green), `rest` (yellow), `record` (violet), `raised`, `muted`. Red is only for danger and errors: use `colorScheme.error`. Everything else comes from `ColorScheme`.
- The text theme defines explicit sizes. Use `Theme.of(context).textTheme` styles and don't hard-code font sizes.
- Icons: use `AppIcon(AppIcons.x)`, not `Icon`/`Icons`. To add an icon, put `name.svg` (14×14 viewBox, Streamline Flex from `api.iconify.design/streamline-flex.json`) in `assets/icons/`, then add `static const x = AppIconData('name')` to `AppIcons`. Icons are precached at startup automatically. Don't use icon-font packages (`flexicon` and `phosphor_flutter` are broken here).
- Launcher icon padding is set by `adaptive_icon_foreground_inset` in `pubspec.yaml`. Don't rescale the PNG.

## Tests

`test/app_test.dart` runs against `AppDatabase(NativeDatabase.memory())`. Add tests there for repository, domain, and backup logic when you change it. Stats live in `test/stats_test.dart`; the workout screen, rest bar, rest sound, and finish dialogs in `test/workout_ui_test.dart`; `test/drift/lift_flow/migration_test.dart` covers every schema step, with data for the steps that convert it. Template, folder and superset tests live in `test/templates_test.dart`.
