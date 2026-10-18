# Lift Flow

A fully local, minimal gym tracker built with Flutter. No accounts, no network, no ads. All data lives in an on-device SQLite database.

## Features

- **Workouts**: start empty or from a template. Log load × reps per set, see the previous session's sets, and complete sets with ✓. Mark sets as warm-up, drop, failure, or AMRAP, add a note, and optionally log RPE or RIR. Beaten records show up as you log. Unchecked sets are dropped on finish, or marked done first. A workout can end at its last set when you finish late, a forgotten one is caught after 4 h, and a default name becomes e.g. "Chest and arms". Link exercises into supersets or circuits (focus alternates and rest starts after the round), replace an exercise without losing its sets, add warm-up sets in one tap, set a rest time per exercise, and add a note to the workout or to an exercise in it. When every set reached the top of the rep range, the next weight is suggested. Barbell sets show the plates per side.
- **Rest timer**: starts automatically after each set or by hand from the app bar, with ±15 s, Skip, presets (60, 90, 120, 180 s) and a custom time. In the background, an ongoing workout notification stays up and a rest countdown adds Skip and +30 s buttons that also work from the lock screen. An alert fires when the rest ends, or an optional sound if the app is open.
- **Templates**: reusable workouts with target sets and rep ranges. Create one from scratch or from a finished workout. Group templates into collapsible folders, duplicate them, and set rest, a target weight and supersets per exercise.
- **Exercises**: weights, bodyweight, time (planks, holds) or distance (runs, rows, carries), filed under a muscle group (required, with optional secondary muscles), with equipment and per-side or per-dumbbell loads that count in volume. The picker lists recent and frequent exercises first and matches loosely (“db bench”). The exercise page shows a rep-max table and links each session to its workout. Bodyweight exercises can track added or assisted load. Time and distance exercises can carry a weight; distance is logged in km or mi, or in m or yd with a weight, and time sets have a stopwatch. An exercise that has logged sets is archived instead of deleted.
- **App lock**: optional. Unlocks with the phone’s own fingerprint, face, PIN, pattern or password, on a cold start and after 5 minutes in the background. The app is hidden while locked, and from the recents list on Android 13+ (older versions block screenshots instead).
- **App shortcuts**: long-press the app icon to start one of your four most recently used templates.
- **Home-screen widget** (Android): this week’s training days and a button that starts your next template, or continues the running workout.
- **Tablets and landscape**: from 600 dp wide the tabs move to a side rail, and from 840 dp History and the exercise list show the selected workout or exercise beside the list. Other screens keep a readable column width.
- **History & records**: workouts grouped by month, with search, template and exercise filters, and a month calendar; log a past workout, edit its date and times, or do it again. Home shows a tappable weekly strip (weeks start on Monday, Sunday, or Saturday), the last workout, and this week’s volume against the same point last week. Per-exercise history and PRs (heaviest, best e1RM, best load, most reps, longest time, longest distance, best pace).
- **Progress**: consistency calendar, weekly training (3M to All), muscle balance with a configurable weekly-sets band, top lifts, recent records, lifetime totals with a year in review, and body weight with a 7-day average. Weigh-ins can be backdated, edited, and undone after a delete.
- **Settings**: kg/lb, body weight, light/dark/system theme, pure-black mode, Material You colors (Android 12+), rest defaults, set effort (RPE or RIR), bar weight and available plates, keep screen on, and JSON backup export/import with the date of the last backup.
- **Reminders**: optional weekly notifications on the training days and time you pick, scheduled on the phone.
- **CSV export**: every completed set as one row, for spreadsheets.

## Tech stack

| Concern     | Package                                                                                                                         |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------- |
| UI          | `material_ui` (Material 3), custom theme and tokens, `dynamic_color`                                                            |
| State       | `flutter_riverpod` 3                                                                                                            |
| Routing     | `go_router` (`StatefulShellRoute` with 5 tabs)                                                                                  |
| Persistence | `drift` + `drift_flutter` (SQLite, WAL)                                                                                         |
| Icons       | Streamline Flex SVGs compiled with `vector_graphics_compiler`                                                                   |
| Platform    | `flutter_local_notifications`, `flutter_timezone`, `wakelock_plus`, `file_picker`, `local_auth`, `quick_actions`, `home_widget` |

## Getting started

Requires the Flutter SDK (Dart `^3.13.4`). Android is the primary target.

```sh
flutter pub get
dart run build_runner build   # regenerate lib/data/database.g.dart
flutter run
```

## Common commands

```sh
flutter analyze
flutter test
flutter build bundle             # catches kernel compile errors without an Android SDK
dart run flutter_launcher_icons  # regenerate launcher icons from assets/icon/
```

## Project layout

```
lib/
  main.dart        startup: open DB, preload settings/live workout/rest/icons, runApp
  app.dart         MaterialApp, theme mode, wakelock, background notifications
  router.dart      routes, navigation shell (bottom bar or rail), list-detail panes, live workout bar
  providers.dart   Riverpod providers (repositories, streams, settings, rest timer)
  data/            drift schema, enums, repositories, backup service
  domain/          pure logic: unit conversion/formatting, PR/e1RM calculation, stats, plate math, warm-ups, supersets, the widget’s next template
  features/        screens by tab: home, history, gym, workout, settings, plus the lock screen
  services/        local notifications, device authentication, launcher shortcuts, home-screen widget
  theme/           colors, text theme, spacing/radius/motion tokens, icons
  widgets/         shared widgets (sheets, dialogs, cards, PeriodicBuilder, adaptive layout)
assets/
  icons/           SVG icons (14×14 grid)
  fonts/           Quicksand (display), Nunito Sans (body)
  icon/            launcher icon sources
test/               unit, in-memory DB, chart, and schema migration tests
```

## Data & backups

- Weights are stored in kg, durations in seconds and distances in metres, and converted for display.
- App lock is a device setting: it isn’t exported, and importing a backup keeps this device’s choice.
- Warm-up sets are kept but left out of totals, stats, and records.
- Backups are versioned JSON files (format v4, max 20 MB). Import validates the file and then replaces all data in a single transaction. Backups from older versions still import.
- Home suggests a backup after every 10 finished workouts, and Settings shows the date of the last one. Importing a backup counts as backed up from the day the file was made.
- Import and “Delete all data” are refused while a workout is running.
- The CSV export is for spreadsheets and can’t be imported. Weights are listed in kg and in your unit.

## Contributing

Conventions and architecture notes for contributors and coding agents are in [AGENTS.md](AGENTS.md).

## Licenses

- Fonts: Quicksand and Nunito Sans, SIL OFL (see `assets/fonts/*-OFL.txt`).
- Icons: [Streamline Flex](https://www.streamlinehq.com) free set, CC BY 4.0. Some icons are custom and drawn to match.
