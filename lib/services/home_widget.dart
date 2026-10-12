import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../domain/home_widget.dart';

/// The plugin calls the service needs, so tests can fake them.
class HomeWidgetBackend {
  const HomeWidgetBackend();

  static const _provider = 'com.nilsbtr.liftflow.WeekWidgetProvider';
  static const _key = 'snapshot';

  /// Stores [snapshot] and redraws the widgets.
  Future<void> publish(String snapshot) async {
    await HomeWidget.saveWidgetData<String>(_key, snapshot);
    await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
  }

  /// The tap that launched the app, if a widget did.
  Future<Uri?> launchUri() => HomeWidget.initiallyLaunchedFromHomeWidget();

  /// Taps while the app is running.
  Stream<Uri?> get taps => HomeWidget.widgetClicked;
}

/// Feeds the Android home-screen widget and reports taps on it.
class HomeWidgetService {
  HomeWidgetService([
    HomeWidgetBackend backend = const HomeWidgetBackend(),
    DateTime Function() clock = DateTime.now,
  ]) : _backend = backend,
       _clock = clock;

  final HomeWidgetBackend _backend;
  final DateTime Function() _clock;

  static const _repeatWindow = Duration(seconds: 3);

  /// What the widget currently shows, to skip no-op updates.
  String? _shown;

  StreamSubscription<Uri?>? _taps;
  Uri? _lastTap;
  DateTime? _lastTapAt;

  bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android && !kIsWeb;

  /// Reports widget taps, including the one that launched the app.
  Future<void> init(void Function(WidgetAction action) onTap) async {
    if (!_supported) return;
    void report(Uri? uri) {
      final action = parseWidgetUri(uri);
      if (action != null && !_isRepeat(uri!)) onTap(action);
    }

    try {
      _taps = _backend.taps.listen(
        report,
        onError: (Object e) => debugPrint('Widget taps unavailable: $e'),
      );
      report(await _backend.launchUri());
    } catch (e) {
      debugPrint('Widget unavailable: $e');
    }
  }

  /// Like a shortcut, a launch may reach Dart both as the launch URI and as
  /// a tap, which would start the workout twice.
  bool _isRepeat(Uri uri) {
    final now = _clock();
    final last = _lastTapAt;
    if (uri == _lastTap &&
        last != null &&
        now.difference(last) < _repeatWindow) {
      return true;
    }
    _lastTap = uri;
    _lastTapAt = now;
    return false;
  }

  /// Makes the widget show [snapshot].
  Future<void> sync(HomeWidgetSnapshot snapshot) async {
    if (!_supported) return;
    final data = snapshot.encode();
    if (data == _shown) return;
    _shown = data;
    try {
      await _backend.publish(data);
    } catch (e) {
      _shown = null;
      debugPrint('Widget not updated: $e');
    }
  }

  void dispose() => unawaited(_taps?.cancel());
}
