import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../providers.dart';
import '../../services/app_lock.dart';
import '../../theme/app_icons.dart';
import '../../widgets/common.dart';

/// Wraps the app (above the router). While locked, the app is kept alive but
/// not painted, focusable or reachable by touch, semantics or the back
/// button, and [LockScreen] covers it.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Registered before the router's, so it sees back presses first.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    if (!ref.read(appLockProvider).locked) return false;
    await SystemNavigator.pop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockProvider.select((s) => s.locked));
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: locked,
          child: TickerMode(
            enabled: !locked,
            child: Offstage(offstage: locked, child: widget.child),
          ),
        ),
        if (locked) const LockScreen(),
      ],
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _prompted = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _autoPrompt);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) _autoPrompt();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Asks once when the lock appears. After a cancel, the button asks again.
  void _autoPrompt() {
    if (_prompted || !mounted) return;
    _prompted = true;
    _unlock();
  }

  void _unlock() => unawaited(ref.read(appLockProvider.notifier).unlock());

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: EmptyState(
          icon: AppIcons.lock,
          title: 'Lift Flow is locked',
          message: switch (lock.failure) {
            AuthResult.failed => 'Couldn’t unlock. Try again.',
            AuthResult.unavailable =>
              'Set a screen lock in your phone’s settings to unlock.',
            _ => 'Unlock with your fingerprint or screen lock.',
          },
          action: FilledButton(
            onPressed: lock.busy ? null : _unlock,
            child: const Text('Unlock'),
          ),
        ),
      ),
    );
  }
}
