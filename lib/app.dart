import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'data/database.dart';
import 'features/lock/lock_gate.dart';
import 'providers.dart';
import 'router.dart';
import 'services/app_lock.dart';
import 'services/notifications.dart';
import 'theme/app_theme.dart';

class LiftFlowApp extends ConsumerStatefulWidget {
  const LiftFlowApp({super.key});

  @override
  ConsumerState<LiftFlowApp> createState() => _LiftFlowAppState();
}

class _LiftFlowAppState extends ConsumerState<LiftFlowApp> {
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<String?>? _taps;
  StreamSubscription<void>? _restChanges;
  bool? _wakelock;

  @override
  void initState() {
    super.initState();
    final notifications = ref.read(notificationsProvider);
    _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
    _taps = notifications.taps.listen((payload) {
      if (payload == NotificationService.payloadWorkout &&
          ref.read(liveWorkoutProvider) != null) {
        ref
            .read(appLockProvider.notifier)
            .whenUnlocked(() => ref.read(routerProvider).go('/workout'));
      }
    });
    _restChanges = notifications.restChanges.listen(
      (_) => unawaited(ref.read(restTimerProvider.notifier).reload()),
    );
    // Notifications of a killed process outlive it.
    unawaited(notifications.clear());

    ref.listenManual(
      settingsProvider.select((s) => s.appLock),
      (_, on) => unawaited(setRecentsHidden(on)),
      fireImmediately: true,
    );
  }

  void _onHide() {
    ref.read(appLockProvider.notifier).onHidden();
    final live = ref.read(liveWorkoutProvider);
    if (live == null) return;
    final notifications = ref.read(notificationsProvider);
    unawaited(notifications.showWorkout(live.name, live.startedAt));
    final rest = ref.read(restTimerProvider);
    if (rest != null && rest.endsAt.isAfter(DateTime.now())) {
      unawaited(
        notifications.showRest(
          rest.endsAt,
          alert: ref.read(settingsProvider).restAlerts,
        ),
      );
    }
  }

  /// A notification action may have changed the rest while the app was hidden.
  void _onShow() {
    ref.read(appLockProvider.notifier).onShown();
    unawaited(ref.read(notificationsProvider).clear());
    unawaited(ref.read(restTimerProvider.notifier).reload());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_taps?.cancel());
    unawaited(_restChanges?.cancel());
    super.dispose();
  }

  void _syncWakelock(bool enable) {
    if (_wakelock == enable) return;
    _wakelock = enable;
    unawaited(WakelockPlus.toggle(enable: enable));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final live = ref.watch(liveWorkoutProvider);
    final router = ref.watch(routerProvider);
    _syncWakelock(settings.keepScreenOn && live != null);

    return MaterialApp.router(
      title: 'Lift Flow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(pureBlack: settings.pureBlack),
      themeMode: switch (settings.themeMode) {
        ThemePref.system => ThemeMode.system,
        ThemePref.light => ThemeMode.light,
        ThemePref.dark => ThemeMode.dark,
      },
      routerConfig: router,
      builder: (_, child) => AppLockGate(child: child!),
    );
  }
}
