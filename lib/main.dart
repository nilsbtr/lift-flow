import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/settings_repository.dart';
import 'data/workout_repository.dart';
import 'providers.dart';
import 'services/notifications.dart';
import 'theme/app_icons.dart';
import 'theme/dynamic_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Quicksand', 'NunitoSans']) {
      final text = await rootBundle.loadString('assets/fonts/$font-OFL.txt');
      yield LicenseEntryWithLineBreaks([font], text);
    }
    yield const LicenseEntryWithLineBreaks(
      ['Streamline Flex icons'],
      'Flex free icons by Streamline (https://www.streamlinehq.com), '
      'licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).',
    );
  });

  final db = AppDatabase();
  final notifications = NotificationService();
  final (settings, live, rest, _, _, pkg, _, dynamicSchemes) = await (
    SettingsRepository(db).get(),
    WorkoutRepository(db).getLive(),
    RestRepository(db).get(),
    notifications.init(),
    AppIcons.precache(),
    PackageInfo.fromPlatform(),
    // Drops a past workout abandoned by a killed app.
    WorkoutRepository(db).purgeEmpty(),
    loadDynamicSchemes(),
  ).wait;

  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        notificationsProvider.overrideWithValue(notifications),
        initialSettingsProvider.overrideWithValue(settings),
        initialLiveWorkoutProvider.overrideWithValue(live),
        initialRestProvider.overrideWithValue(rest),
        initialPackageInfoProvider.overrideWithValue(pkg),
        dynamicSchemesProvider.overrideWithValue(dynamicSchemes),
      ],
      child: const LiftFlowApp(),
    ),
  );
  unawaited(_deletePhotoFiles());
}

/// Progress photos were removed. Deletes the files older versions kept, which
/// nothing can reach any more.
Future<void> _deletePhotoFiles() async {
  try {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}photos');
    if (await dir.exists()) await dir.delete(recursive: true);
  } on FileSystemException {
    // Tried again on the next launch.
  }
}
