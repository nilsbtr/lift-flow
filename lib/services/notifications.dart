import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/database.dart';
import '../data/settings_repository.dart';
import '../domain/rest.dart';

/// Thin wrapper around local notifications for the workout and rest timer.
///
/// While the app is hidden a live workout has an ongoing notification
/// ([_workoutId]) that stays through rests. A rest adds a countdown with Skip
/// and +30 s ([_restId], times out by itself) and a scheduled alert
/// ([_alertId]). Those actions run in [onNotificationAction]. With the app open
/// a rest end can play a short sound instead ([playRestSound], [_soundId]).
class NotificationService {
  NotificationService() : _ready = false;

  /// For the action isolate, which only posts and cancels.
  NotificationService.background()
    : _ready = defaultTargetPlatform == TargetPlatform.android;

  static const _workoutId = 1;
  static const _alertId = 2;
  static const _restId = 3;
  static const _soundId = 4;
  static const _icon = 'ic_stat_lift';
  static const _restChangedPort = 'lift_flow/rest_changed';
  static const payloadWorkout = 'workout';
  static const actionSkip = 'rest_skip';
  static const actionAdd = 'rest_add';
  static const addSeconds = 30;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String?> _taps = StreamController.broadcast();
  final StreamController<void> _restChanges = StreamController.broadcast();

  bool _ready;

  /// Payloads of tapped notifications while the app is running.
  Stream<String?> get taps => _taps.stream;

  /// Fires when a notification action changed the persisted rest.
  Stream<void> get restChanges => _restChanges.stream;

  /// Payload of the notification that launched the app, if any.
  String? launchPayload;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> init() async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_icon),
        ),
        onDidReceiveNotificationResponse: (r) => _taps.add(r.payload),
        onDidReceiveBackgroundNotificationResponse: onNotificationAction,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        launchPayload = launch!.notificationResponse?.payload;
      }
      _listenForRestChanges();
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  /// The action isolate can't reach this isolate's state, so it pings a port.
  void _listenForRestChanges() {
    final port = ReceivePort()..listen((_) => _restChanges.add(null));
    IsolateNameServer.removePortNameMapping(_restChangedPort);
    IsolateNameServer.registerPortWithName(port.sendPort, _restChangedPort);
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  Future<bool> canScheduleExact() async {
    if (!_ready) return false;
    return await _android?.canScheduleExactNotifications() ?? false;
  }

  Future<void> requestExactAlarms() async {
    if (!_ready) return;
    await _android?.requestExactAlarmsPermission();
  }

  /// Shows the silent ongoing countdown and schedules the alert at [endsAt].
  Future<void> showRest(DateTime endsAt, {required bool alert}) async {
    if (!_ready) return;
    final remaining = endsAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return;
    await _plugin.show(
      id: _restId,
      title: 'Resting',
      body: 'Tap to return to your workout',
      payload: payloadWorkout,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'rest_ongoing',
          'Rest countdown',
          channelDescription: 'Silent countdown while the app is hidden',
          importance: Importance.low,
          priority: Priority.low,
          icon: _icon,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          showWhen: true,
          when: endsAt.millisecondsSinceEpoch,
          usesChronometer: true,
          chronometerCountDown: true,
          timeoutAfter: remaining.inMilliseconds,
          category: AndroidNotificationCategory.stopwatch,
          visibility: NotificationVisibility.public,
          actions: const [
            AndroidNotificationAction(
              actionSkip,
              'Skip',
              cancelNotification: false,
            ),
            AndroidNotificationAction(
              actionAdd,
              '+$addSeconds s',
              cancelNotification: false,
            ),
          ],
        ),
      ),
    );
    if (!alert) return;
    final exact = await canScheduleExact();
    await _plugin.zonedSchedule(
      id: _alertId,
      title: 'Rest over',
      body: 'Time for your next set',
      payload: payloadWorkout,
      scheduledDate: tz.TZDateTime.now(tz.UTC).add(remaining),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'rest_alert',
          'Rest over',
          channelDescription: 'Alerts when your rest timer ends',
          importance: Importance.high,
          priority: Priority.high,
          icon: _icon,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          timeoutAfter: 60000,
        ),
      ),
    );
  }

  /// Plays the notification sound for a rest that ends while the app is open.
  /// Android has no other system sound API, so this posts a notification on its
  /// own channel (a sound but no pop-up, so the channel can't be the alert's)
  /// that removes itself. The sound follows the phone's ringer mode.
  Future<void> playRestSound() async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _soundId,
        title: 'Rest over',
        body: 'Time for your next set',
        payload: payloadWorkout,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'rest_sound',
            'Rest over sound',
            channelDescription: 'Short sound when a rest ends in the app',
            icon: _icon,
            enableVibration: false,
            timeoutAfter: 4000,
            visibility: NotificationVisibility.secret,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Rest sound unavailable: $e');
    }
  }

  /// Shows a silent ongoing notification with elapsed workout time.
  Future<void> showWorkout(String name, DateTime startedAt) async {
    if (!_ready) return;
    await _plugin.show(
      id: _workoutId,
      title: name,
      body: 'Workout in progress',
      payload: payloadWorkout,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'workout_ongoing',
          'Workout in progress',
          channelDescription:
              'Silent timer while a workout runs in the background',
          importance: Importance.low,
          priority: Priority.low,
          icon: _icon,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          showWhen: true,
          when: startedAt.millisecondsSinceEpoch,
          usesChronometer: true,
          category: AndroidNotificationCategory.stopwatch,
          visibility: NotificationVisibility.public,
        ),
      ),
    );
  }

  /// Removes the rest countdown and its pending alert, keeping the workout.
  Future<void> cancelRest() async {
    if (!_ready) return;
    await _plugin.cancel(id: _restId);
    await _plugin.cancel(id: _alertId);
  }

  Future<void> clear() async {
    if (!_ready) return;
    await _plugin.cancel(id: _workoutId);
    await cancelRest();
  }
}

/// Applies a rest notification [action] to the persisted rest and returns the
/// new countdown, or null when the rest is over.
Future<({DateTime endsAt, int totalSeconds})?> applyRestAction(
  RestRepository repo,
  String action, {
  DateTime? now,
}) async {
  now ??= DateTime.now();
  final row = await repo.get();
  final next = row != null && row.endsAt.isAfter(now)
      ? switch (action) {
          NotificationService.actionAdd => adjustRest(
            row.endsAt,
            row.totalSeconds,
            NotificationService.addSeconds,
            now,
          ),
          _ => null,
        }
      : null;
  if (next == null) {
    await repo.clear();
  } else {
    await repo.save(next.endsAt, next.totalSeconds);
  }
  return next;
}

Future<void> _actions = Future.value();

/// Entry point for notification actions that don't open the app. Runs in a
/// separate isolate, also when the app process was killed: it has its own
/// database connection, so it can't use providers or any other app state.
@pragma('vm:entry-point')
void onNotificationAction(NotificationResponse response) {
  final action = response.actionId;
  if (action == null ||
      (action != NotificationService.actionSkip &&
          action != NotificationService.actionAdd)) {
    return;
  }
  _actions = _actions.then((_) => _runRestAction(action));
}

Future<void> _runRestAction(String action) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    final db = AppDatabase();
    try {
      final next = await applyRestAction(RestRepository(db), action);
      final service = NotificationService.background();
      if (next == null) {
        await service.cancelRest();
      } else {
        final settings = await SettingsRepository(db).get();
        await service.showRest(next.endsAt, alert: settings.restAlerts);
      }
    } finally {
      await db.close();
    }
    IsolateNameServer.lookupPortByName(NotificationService._restChangedPort)
        ?.send(null);
  } catch (e) {
    debugPrint('Rest action failed: $e');
  }
}
