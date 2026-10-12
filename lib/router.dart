import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'data/template_repository.dart';
import 'domain/units.dart';
import 'features/gym/template_editor_screen.dart';
import 'features/gym/exercise_detail_screen.dart';
import 'features/gym/gym_screen.dart';
import 'features/history/history_screen.dart';
import 'features/history/log_workout_route.dart';
import 'features/history/workout_detail_screen.dart';
import 'features/home/home_screen.dart';
import 'features/photos/photo_compare_screen.dart';
import 'features/photos/photo_viewer_screen.dart';
import 'features/photos/photos_screen.dart';
import 'features/progress/progress_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/workout/workout_screen.dart';
import 'providers.dart';
import 'theme/app_icons.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/periodic_builder.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  final live = ref.read(initialLiveWorkoutProvider);
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: live != null ? '/workout' : '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'workout',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (_, _) => const LiveWorkoutRoute(),
                  ),
                  _workoutRoute('workouts/:workoutId'),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (_, _) => const HistoryScreen(),
                routes: [
                  GoRoute(
                    path: 'log/:workoutId',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (_, s) =>
                        LogWorkoutRoute(workoutId: _param(s, 'workoutId')),
                  ),
                  _workoutRoute(':workoutId'),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/progress',
                builder: (_, _) => const ProgressScreen(),
                routes: [
                  _exerciseRoute(),
                  _workoutRoute('workout/:workoutId'),
                  _photosRoute(),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/gym',
                builder: (_, s) => GymScreen(
                  tab: s.uri.queryParameters['tab'] == 'templates'
                      ? GymTab.templates
                      : GymTab.exercises,
                ),
                routes: [
                  _exerciseRoute(),
                  GoRoute(
                    path: 'template/:templateId',
                    parentNavigatorKey: rootNavigatorKey,
                    // `new` parses to null, which creates a template.
                    builder: (_, s) => TemplateEditorScreen(
                      templateId: int.tryParse(s.pathParameters['templateId']!),
                      initialItems: s.extra as List<TemplateItem>?,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

int _param(GoRouterState s, String name) =>
    int.tryParse(s.pathParameters[name] ?? '') ?? -1;

/// Exercise and workout pages link to each other, so their routes nest
/// (`/gym/exercise/1/workout/2/exercise/3`). Each step gets a numbered path
/// parameter to keep them unique, and the chain ends at [_maxLinkLevel].
const _maxLinkLevel = 2;

String _id(String name, int level) => level == 0 ? name : '$name$level';

/// Exercise detail, nested in each tab that links to it so back stays there.
GoRoute _exerciseRoute({int level = 0}) => GoRoute(
  path: 'exercise/:${_id('exerciseId', level)}',
  builder: (_, s) => ExerciseDetailScreen(
    exerciseId: _param(s, _id('exerciseId', level)),
    canOpenWorkouts: level < _maxLinkLevel,
  ),
  routes: [
    if (level < _maxLinkLevel)
      _workoutRoute(
        'workout/:${_id('workoutId', level + 1)}',
        level: level + 1,
      ),
  ],
);

/// Workout detail with its full-screen editor and exercise links.
GoRoute _workoutRoute(String path, {int level = 0}) => GoRoute(
  path: path,
  builder: (_, s) =>
      WorkoutDetailScreen(workoutId: _param(s, _id('workoutId', level))),
  routes: [
    GoRoute(
      path: 'edit',
      parentNavigatorKey: rootNavigatorKey,
      builder: (_, s) =>
          WorkoutScreen(workoutId: _param(s, _id('workoutId', level))),
    ),
    _exerciseRoute(level: level),
  ],
);

/// Progress photos: the grid, a side-by-side comparison (`?a=` and `?b=` are
/// photo ids to start with) and a full-screen viewer that pops back.
GoRoute _photosRoute() => GoRoute(
  path: 'photos',
  builder: (_, _) => const PhotosScreen(),
  routes: [
    GoRoute(
      path: 'compare',
      builder: (_, s) => PhotoCompareScreen(
        a: int.tryParse(s.uri.queryParameters['a'] ?? ''),
        b: int.tryParse(s.uri.queryParameters['b'] ?? ''),
      ),
    ),
    GoRoute(
      path: ':photoId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (_, s) => PhotoViewerScreen(photoId: _param(s, 'photoId')),
    ),
  ],
);

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    // Back from another tab's root returns to Home before leaving the app.
    return PopScope(
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _LiveBar(),
          // Labels are fixed-height; cap their scaling so they stay on one line.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.15,
            child: NavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (i) =>
                  shell.goBranch(i, initialLocation: i == shell.currentIndex),
              destinations: const [
                NavigationDestination(
                  icon: AppIcon(AppIcons.home),
                  selectedIcon: AppIcon(AppIcons.homeSolid),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: AppIcon(AppIcons.history),
                  selectedIcon: AppIcon(AppIcons.historySolid),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: AppIcon(AppIcons.progress),
                  selectedIcon: AppIcon(AppIcons.progressSolid),
                  label: 'Progress',
                ),
                NavigationDestination(
                  icon: AppIcon(AppIcons.dumbbell),
                  selectedIcon: AppIcon(AppIcons.dumbbellSolid),
                  label: 'Gym',
                ),
                NavigationDestination(
                  icon: AppIcon(AppIcons.settings),
                  selectedIcon: AppIcon(AppIcons.settingsSolid),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Compact bar above the navigation showing the running workout.
class _LiveBar extends ConsumerWidget {
  const _LiveBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveWorkoutProvider);
    final rest = ref.watch(restTimerProvider);
    final colors = LiftColors.of(context);
    final t = Theme.of(context).textTheme;
    final onLive = Theme.of(context).colorScheme.onSecondary;

    return AnimatedSize(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.curve,
      alignment: Alignment.bottomCenter,
      child: live == null
          ? const SizedBox(width: double.infinity)
          : Material(
              color: colors.done,
              child: InkWell(
                onTap: () => context.go('/workout'),
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.lg,
                      vertical: Space.md,
                    ),
                    child: DefaultTextStyle.merge(
                      style: t.titleSmall?.copyWith(color: onLive),
                      child: IconTheme.merge(
                        data: IconThemeData(color: onLive, size: IconSizes.sm),
                        child: Row(
                          children: [
                            const AppIcon(AppIcons.playSolid),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: Text(
                                live.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (rest != null)
                              PeriodicBuilder(
                                period: const Duration(seconds: 1),
                                anchor: rest.endsAt,
                                builder: (_) => Text(
                                  'Rest ${fmtClock(rest.remainingSeconds())}',
                                  style: const TextStyle(
                                    fontFeatures: Fonts.tabular,
                                  ),
                                ),
                              )
                            else
                              PeriodicBuilder(
                                period: const Duration(minutes: 1),
                                anchor: live.startedAt,
                                builder: (_) => Text(
                                  fmtDuration(
                                    DateTime.now().difference(live.startedAt),
                                  ),
                                ),
                              ),
                            const SizedBox(width: Space.xs),
                            const AppIcon(AppIcons.chevronRight),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
