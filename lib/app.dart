import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'data/database.dart';
import 'domain/home_widget.dart';
import 'features/lock/lock_gate.dart';
import 'features/workout/workout_actions.dart';
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
    unawaited(ref.read(settingsProvider.notifier).syncReminders());

    unawaited(ref.read(shortcutsProvider).init(_onShortcut));
    ref.listenManual(
      shortcutTemplatesProvider,
      (_, templates) => unawaited(ref.read(shortcutsProvider).sync(templates)),
      fireImmediately: true,
    );
    unawaited(ref.read(homeWidgetProvider).init(_onWidgetTap));
    ref.listenManual(homeWidgetSnapshotProvider, (_, snapshot) {
      if (snapshot != null) {
        unawaited(ref.read(homeWidgetProvider).sync(snapshot));
      }
    }, fireImmediately: true);
    ref.listenManual(
      settingsProvider.select((s) => s.appLock),
      (_, on) => unawaited(setRecentsHidden(on)),
      fireImmediately: true,
    );
  }

  void _onShortcut(int templateId) => ref
      .read(appLockProvider.notifier)
      .whenUnlocked(() => unawaited(_startTemplate(templateId)));

  /// A tap on the home-screen widget. Open only brings the app to the front.
  void _onWidgetTap(WidgetAction action) =>
      ref.read(appLockProvider.notifier).whenUnlocked(() {
        switch (action.tap) {
          case WidgetTap.start:
            unawaited(_startTemplate(action.templateId));
          case WidgetTap.resume:
            if (ref.read(liveWorkoutProvider) != null) {
              ref.read(routerProvider).go('/workout');
            }
          case WidgetTap.open:
        }
      });

  /// Starts a template (or an empty workout) from a launcher shortcut or the
  /// widget, or opens Home if the template is gone.
  Future<void> _startTemplate(int? templateId) async {
    if (templateId != null) {
      final template = await ref.read(templateRepoProvider).get(templateId);
      if (!mounted) return;
      if (template == null) {
        ref.read(routerProvider).go('/');
        return;
      }
    }
    // A cold start can get here before the first frame has built the navigator.
    if (rootNavigatorKey.currentContext == null) {
      await WidgetsBinding.instance.endOfFrame;
    }
    final navigator = rootNavigatorKey.currentContext;
    if (!mounted || navigator == null || !navigator.mounted) return;
    await startWorkout(navigator, ref, templateId: templateId);
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
    unawaited(ref.read(settingsProvider.notifier).syncReminders());
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
    final system = settings.dynamicColor
        ? ref.watch(dynamicSchemesProvider)
        : null;

    return MaterialApp.router(
      title: 'Lift Flow',
      debugShowCheckedModeBanner: false,
      theme: system == null
          ? AppTheme.light()
          : AppTheme.dynamicTheme(system.light),
      darkTheme: system == null
          ? AppTheme.dark(pureBlack: settings.pureBlack)
          : AppTheme.dynamicTheme(system.dark, pureBlack: settings.pureBlack),
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
