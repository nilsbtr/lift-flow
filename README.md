# Lift Flow

A fully local, minimal gym tracker built with Flutter. No accounts, no network, no ads. All data lives in an on-device SQLite database.

## Features

- **Workouts**: start empty or from a template. Log load × reps per set, see the previous session's sets, and complete sets with ✓. Unchecked sets are dropped on finish.
- **Rest timer**: starts automatically after each set, with ±15 s and Skip. In the background, an ongoing workout notification stays up and a rest countdown adds Skip and +30 s buttons that also work from the lock screen. An alert fires when the rest ends.
- **Templates**: reusable workouts with target sets and rep ranges. Create one from scratch or from a finished workout.
- **Exercises**: weights or bodyweight, filed under a muscle group (required, with optional secondary muscles), with equipment and per-side or per-dumbbell loads that count in volume. The picker lists recent and frequent exercises first and matches loosely (“db bench”). The exercise page shows a rep-max table and links each session to its workout. Bodyweight exercises can track added or assisted load. An exercise that has logged sets is archived instead of deleted.
- **History & records**: workouts grouped by month, with search, template and exercise filters, and a month calendar; log a past workout, edit its date and times, or do it again. Home shows a tappable weekly strip (weeks start on Monday, Sunday, or Saturday), the last workout, and this week’s volume against the same point last week. Per-exercise history and PRs (heaviest, best e1RM, best load, most reps).
- **Settings**: kg/lb, body weight, light/dark/system theme, pure-black mode, rest defaults, keep screen on, and JSON backup export/import.

## Tech stack

| Concern     | Package                                                       |
| ----------- | ------------------------------------------------------------- |
| UI          | `material_ui` (Material 3), custom theme and tokens           |
| State       | `flutter_riverpod` 3                                          |
| Routing     | `go_router` (`StatefulShellRoute` with 4 tabs)                |
| Persistence | `drift` + `drift_flutter` (SQLite, WAL)                       |
| Icons       | Streamline Flex SVGs compiled with `vector_graphics_compiler` |
| Platform    | `flutter_local_notifications`, `wakelock_plus`, `file_picker` |

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
  router.dart      routes, bottom navigation shell, live workout bar
  providers.dart   Riverpod providers (repositories, streams, settings, rest timer)
  data/            drift schema, enums, repositories, backup service
  domain/          pure logic: unit conversion/formatting, PR/e1RM calculation, stats
  features/        screens by tab: home, history, gym, workout, settings
  services/        local notifications
  theme/           colors, text theme, spacing/radius/motion tokens, icons
  widgets/         shared widgets (sheets, dialogs, cards, PeriodicBuilder)
assets/
  icons/           SVG icons (14×14 grid)
  fonts/           Quicksand (display), Nunito Sans (body)
  icon/            launcher icon sources
test/               unit, in-memory DB, chart, and schema migration tests
```

## Data & backups

- Weights are stored in kg and converted for display.
- Warm-up sets are kept but left out of totals, stats, and records.
- Backups are versioned JSON files (format v3, max 20 MB). Import validates the file and then replaces all data in a single transaction. Backups from older versions still import.

## Contributing

Conventions and architecture notes for contributors and coding agents are in [AGENTS.md](AGENTS.md).

## Licenses

- Fonts: Quicksand and Nunito Sans, SIL OFL (see `assets/fonts/*-OFL.txt`).
- Icons: [Streamline Flex](https://www.streamlinehq.com) free set, CC BY 4.0. Some icons are custom and drawn to match.
