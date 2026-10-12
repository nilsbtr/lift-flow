import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lift_flow/data/database.dart';
import 'package:lift_flow/data/settings_repository.dart';
import 'package:lift_flow/features/lock/lock_gate.dart';
import 'package:lift_flow/providers.dart';
import 'package:lift_flow/services/app_lock.dart';
import 'package:lift_flow/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// Answers each prompt from [results] (success when empty) and remembers the
/// reasons. A [gate] holds the answer until it completes.
class FakeAuthenticator implements Authenticator {
  final results = <AuthResult>[];
  final reasons = <String>[];
  Completer<void>? gate;

  @override
  Future<AuthResult> authenticate(String reason) async {
    reasons.add(reason);
    await gate?.future;
    return results.isEmpty ? AuthResult.success : results.removeAt(0);
  }
}

final t0 = DateTime(2026, 1, 1, 12);

void main() {
  late AppDatabase db;
  late FakeAuthenticator auth;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    auth = FakeAuthenticator();
  });
  tearDown(() => db.close());

  Future<ProviderContainer> container({bool lock = true}) async {
    final repo = SettingsRepository(db);
    await repo.write(AppSettingsCompanion(appLock: Value(lock)));
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        initialSettingsProvider.overrideWithValue(await repo.get()),
        authenticatorProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('app lock state', () {
    test('locks on a cold start only when enabled', () async {
      expect((await container()).read(appLockProvider).locked, isTrue);
      expect(
        (await container(lock: false)).read(appLockProvider).locked,
        isFalse,
      );
    });

    test('a failed or cancelled prompt leaves the app locked', () async {
      auth.results.addAll([AuthResult.failed, AuthResult.unavailable]);
      final c = await container();
      final lock = c.read(appLockProvider.notifier);

      await lock.unlock();
      expect(c.read(appLockProvider).locked, isTrue);
      expect(c.read(appLockProvider).failure, AuthResult.failed);

      await lock.unlock();
      expect(c.read(appLockProvider).locked, isTrue);
      expect(c.read(appLockProvider).failure, AuthResult.unavailable);

      await lock.unlock();
      expect(c.read(appLockProvider).locked, isFalse);
      expect(c.read(appLockProvider).failure, isNull);
      expect(auth.reasons, hasLength(3));
    });

    test('only one prompt at a time, and none when unlocked', () async {
      auth.gate = Completer<void>();
      final c = await container();
      final lock = c.read(appLockProvider.notifier);

      final first = lock.unlock();
      expect(c.read(appLockProvider).busy, isTrue);
      await lock.unlock();
      expect(auth.reasons, hasLength(1));

      auth.gate!.complete();
      await first;
      expect(c.read(appLockProvider).locked, isFalse);
      await lock.unlock();
      expect(auth.reasons, hasLength(1));
    });

    test('stays unlocked within the grace period, locks after it', () async {
      final c = await container();
      final lock = c.read(appLockProvider.notifier);
      await lock.unlock();

      lock.onHidden(t0);
      lock.onShown(t0.add(kLockGrace - const Duration(seconds: 1)));
      expect(c.read(appLockProvider).locked, isFalse);

      lock.onHidden(t0);
      lock.onShown(t0.add(kLockGrace));
      expect(c.read(appLockProvider).locked, isTrue);
    });

    test('the grace period runs from the first hide', () async {
      final c = await container();
      final lock = c.read(appLockProvider.notifier);
      await lock.unlock();

      lock.onHidden(t0);
      lock.onHidden(t0.add(const Duration(minutes: 4)));
      lock.onShown(t0.add(kLockGrace));
      expect(c.read(appLockProvider).locked, isTrue);
    });

    test('never locks again when disabled', () async {
      final c = await container(lock: false);
      final lock = c.read(appLockProvider.notifier);

      lock.onHidden(t0);
      lock.onShown(t0.add(const Duration(days: 2)));
      expect(c.read(appLockProvider).locked, isFalse);
    });

    test('a clock set back counts as away', () async {
      final c = await container();
      final lock = c.read(appLockProvider.notifier);
      await lock.unlock();

      lock.onHidden(t0);
      lock.onShown(t0.subtract(const Duration(minutes: 1)));
      expect(c.read(appLockProvider).locked, isTrue);
    });

    test('hiding during a prompt does not start the grace period', () async {
      final c = await container();
      final lock = c.read(appLockProvider.notifier);
      await lock.unlock();

      auth.gate = Completer<void>();
      auth.results.add(AuthResult.failed);
      final prompt = lock.setEnabled(false);
      lock.onHidden(t0); // The credential screen covered the app.
      auth.gate!.complete();
      await prompt;
      lock.onShown(t0.add(const Duration(hours: 1)));
      expect(c.read(appLockProvider).locked, isFalse);
    });

    test('showing the app while locked does not unlock it', () async {
      final c = await container();
      final lock = c.read(appLockProvider.notifier);

      lock.onHidden(t0);
      lock.onShown(t0.add(const Duration(seconds: 1)));
      expect(c.read(appLockProvider).locked, isTrue);
      expect(auth.reasons, isEmpty);
    });
  });

  group('actions that wait for the unlock', () {
    test('run at once when unlocked', () async {
      final c = await container(lock: false);
      var ran = 0;
      c.read(appLockProvider.notifier).whenUnlocked(() => ran++);
      expect(ran, 1);
    });

    test('wait for a successful unlock, and only the latest runs', () async {
      auth.results.add(AuthResult.failed);
      final c = await container();
      final lock = c.read(appLockProvider.notifier);
      final ran = <String>[];

      lock.whenUnlocked(() => ran.add('first'));
      lock.whenUnlocked(() => ran.add('second'));
      await lock.unlock(); // Fails.
      expect(ran, isEmpty);

      await lock.unlock();
      expect(ran, ['second']);
    });

    test('an intent before the resume event still respects the grace', () async {
      final c = await container();
      final lock = c.read(appLockProvider.notifier);
      await lock.unlock();
      var ran = 0;

      lock.onHidden(t0);
      lock.whenUnlocked(() => ran++, t0.add(const Duration(minutes: 1)));
      expect(ran, 1);

      lock.onHidden(t0);
      lock.whenUnlocked(() => ran++, t0.add(kLockGrace));
      expect(ran, 1);
      expect(c.read(appLockProvider).locked, isTrue);

      await lock.unlock();
      expect(ran, 2);
    });

    test('are dropped when the user leaves without unlocking', () async {
      auth.results.add(AuthResult.failed);
      final c = await container();
      final lock = c.read(appLockProvider.notifier);
      var ran = 0;

      lock.whenUnlocked(() => ran++);
      await lock.unlock(); // Cancelled.
      lock.onHidden(t0);
      await lock.unlock();
      expect(ran, 0);
    });
  });

  group('turning the lock on and off', () {
    Future<bool> stored() async => (await SettingsRepository(db).get()).appLock;

    test('on needs a successful authentication', () async {
      auth.results.add(AuthResult.failed);
      final c = await container(lock: false);
      final lock = c.read(appLockProvider.notifier);

      expect(await lock.setEnabled(true), AuthResult.failed);
      expect(await stored(), isFalse);
      expect(c.read(settingsProvider).appLock, isFalse);

      expect(await lock.setEnabled(true), AuthResult.success);
      expect(await stored(), isTrue);
      expect(c.read(settingsProvider).appLock, isTrue);
      // The session that turned it on stays unlocked.
      expect(c.read(appLockProvider).locked, isFalse);
      expect(auth.reasons, ['Turn on app lock', 'Turn on app lock']);
    });

    test('is not enabled without a screen lock', () async {
      auth.results.add(AuthResult.unavailable);
      final c = await container(lock: false);

      expect(
        await c.read(appLockProvider.notifier).setEnabled(true),
        AuthResult.unavailable,
      );
      expect(await stored(), isFalse);
    });

    test('off needs authentication too, unless the device has none', () async {
      final c = await container();
      final lock = c.read(appLockProvider.notifier);
      await lock.unlock();

      auth.results.addAll([AuthResult.failed, AuthResult.success]);
      expect(await lock.setEnabled(false), AuthResult.failed);
      expect(await stored(), isTrue);
      expect(await lock.setEnabled(false), AuthResult.success);
      expect(await stored(), isFalse);
      expect(auth.reasons.last, 'Turn off app lock');

      // The screen lock was removed from the device later on.
      expect(await lock.setEnabled(true), AuthResult.success);
      auth.results.add(AuthResult.unavailable);
      expect(await lock.setEnabled(false), AuthResult.success);
      expect(await stored(), isFalse);
    });
  });

  group('lock gate', () {
    late GoRouter router;

    Future<Widget> app(WidgetTester tester, {bool lock = true}) async {
      final settings = (await tester.runAsync(() async {
        final repo = SettingsRepository(db);
        await repo.write(AppSettingsCompanion(appLock: Value(lock)));
        return repo.get();
      }))!;
      router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const _Counter()),
          GoRoute(
            path: '/other',
            builder: (_, _) => const Scaffold(body: Text('other')),
          ),
        ],
      );
      addTearDown(router.dispose);
      return ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          initialSettingsProvider.overrideWithValue(settings),
          authenticatorProvider.overrideWithValue(auth),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (_, child) => AppLockGate(child: child!),
        ),
      );
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(AppLockGate)));

    /// Turns the lock on and lets the grace period lapse, as after a long
    /// time in the background.
    Future<void> lockAfterAbsence(WidgetTester tester) async {
      final lock = containerOf(tester).read(appLockProvider.notifier);
      await tester.runAsync(() => lock.setEnabled(true));
      auth.results.add(AuthResult.failed); // The automatic prompt fails.
      lock.onHidden(t0);
      lock.onShown(t0.add(kLockGrace));
      await tester.pump();
    }

    testWidgets('hides the app from the first frame and prompts once', (
      tester,
    ) async {
      auth.results.add(AuthResult.failed);
      await tester.pumpWidget(await app(tester));

      expect(find.text('count 0'), findsNothing);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.text('Lift Flow is locked'), findsOneWidget);
      // The prompt is asked for once, right after the lock appears.
      expect(auth.reasons, ['Unlock Lift Flow']);
      await tester.pump();
      expect(auth.reasons, hasLength(1));
      expect(find.text('Couldn’t unlock. Try again.'), findsOneWidget);
      expect(find.text('count 0'), findsNothing);

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(auth.reasons, hasLength(2));
      expect(find.text('count 0'), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets('keeps the app and its state while locked', (tester) async {
      await tester.pumpWidget(await app(tester, lock: false));
      await tester.tap(find.text('count 0'));
      await tester.pump();
      expect(find.text('count 1'), findsOneWidget);

      await lockAfterAbsence(tester);
      await tester.pump();
      expect(find.text('count 1'), findsNothing);
      expect(find.byType(LockScreen), findsOneWidget);

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('count 1'), findsOneWidget);
    });

    testWidgets('does not touch the app when the lock is off', (tester) async {
      await tester.pumpWidget(await app(tester, lock: false));
      expect(find.text('count 0'), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);
      expect(auth.reasons, isEmpty);
    });

    testWidgets('back leaves the app instead of reaching the app', (
      tester,
    ) async {
      final platformCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platformCalls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(await app(tester, lock: false));
      unawaited(router.push<void>('/other'));
      await tester.pumpAndSettle();
      Finder other() => find.text('other', skipOffstage: false);
      expect(other(), findsOneWidget);

      await lockAfterAbsence(tester);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(other(), findsOneWidget); // Not popped underneath the lock.
      expect(platformCalls, contains('SystemNavigator.pop'));

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      platformCalls.clear();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(other(), findsNothing);
      expect(platformCalls, isEmpty);
    });
  });
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => setState(() => _n++),
      child: Text('count $_n'),
    ),
  );
}
