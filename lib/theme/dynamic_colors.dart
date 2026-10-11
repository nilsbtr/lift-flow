import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// The system's colors (Material You), in both brightnesses.
typedef DynamicSchemes = ({ColorScheme light, ColorScheme dark});

/// Reads the wallpaper colors once at startup. Null unless the system has
/// them: Android 12 and up. The accent colors of other platforms don't count.
Future<DynamicSchemes?> loadDynamicSchemes() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final palette = await DynamicColorPlugin.getCorePalette();
    if (palette == null) return null;
    return (
      light: palette.toColorScheme(),
      dark: palette.toColorScheme(brightness: Brightness.dark),
    );
  } catch (e) {
    debugPrint('Dynamic colors unavailable: $e');
    return null;
  }
}
