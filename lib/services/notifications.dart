import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Thin wrapper around local notifications for the rest timer.
class NotificationService {
  NotificationService();

  static const _ongoingId = 1;
  static const _alertId = 2;
  static const _icon = 'ic_stat_lift';
  static const payloadWorkout = 'workout';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String?> _taps = StreamController.broadcast();

  bool _ready = false;

  /// Payloads of tapped notifications while the app is running.
  Stream<String?> get taps => _taps.stream;

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
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        launchPayload = launch!.notificationResponse?.payload;
      }
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
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
      id: _ongoingId,
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

  /// Shows a silent ongoing notification with elapsed workout time.
  Future<void> showWorkout(String name, DateTime startedAt) async {
    if (!_ready) return;
    await _plugin.show(
      id: _ongoingId,
      title: name,
      body: 'Workout in progress',
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
          when: startedAt.millisecondsSinceEpoch,
          usesChronometer: true,
          category: AndroidNotificationCategory.stopwatch,
          visibility: NotificationVisibility.public,
        ),
      ),
    );
  }

  Future<void> clear() async {
    if (!_ready) return;
    await _plugin.cancel(id: _ongoingId);
    await _plugin.cancel(id: _alertId);
  }
}
