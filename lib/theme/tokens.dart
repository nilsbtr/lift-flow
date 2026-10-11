import 'package:material_ui/material_ui.dart';

/// Spacing scale (dp).
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii (dp).
abstract final class Radii {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));

  /// Fully rounded ends.
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// Motion durations. Use [Motion.of] so reduced-motion settings are honored.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 280);

  /// Chart draw-in.
  static const Duration chart = Duration(milliseconds: 560);

  /// One-off celebration, e.g. the trophy on the finish sheet.
  static const Duration celebrate = Duration(milliseconds: 1100);
  static const Curve curve = Curves.easeOutCubic;

  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}

/// Raw palette. Blue = act, green = done, yellow = rest, violet = record, red = danger.
abstract final class Palette {
  // Dark
  static const darkBackground = Color(0xFF121416);
  static const darkSurface = Color(0xFF1A1D21);
  static const darkRaised = Color(0xFF23272C);
  static const darkOutline = Color(0xFF2E3338);
  static const darkText = Color(0xFFE8EAE7);
  static const darkMuted = Color(0xFF8E959C);
  static const darkBlue = Color(0xFF6F9DD6);
  static const darkGreen = Color(0xFF7BBE9C);
  static const darkYellow = Color(0xFFE5BC6A);
  static const darkViolet = Color(0xFFB39DF5);
  static const darkRed = Color(0xFFE27B70);

  // Pure black variant
  static const blackBackground = Color(0xFF000000);
  static const blackSurface = Color(0xFF0F1113);
  static const blackRaised = Color(0xFF1A1D21);

  // Light
  static const lightBackground = Color(0xFFF4F5F6);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightRaised = Color(0xFFECEEF0);
  static const lightOutline = Color(0xFFD9DDE1);
  static const lightText = Color(0xFF15181B);
  static const lightMuted = Color(0xFF5F676F);
  static const lightBlue = Color(0xFF2E6CB8);
  static const lightGreen = Color(0xFF2A7F57);
  static const lightYellow = Color(0xFF946B10);
  static const lightViolet = Color(0xFF6D3FC9);
  static const lightRed = Color(0xFFC6503F);
}

const kMinTap = 48.0;

/// Compact control height, e.g. inline segmented buttons in list rows.
const kCompactTap = 40.0;

/// Icon sizes (dp).
abstract final class IconSizes {
  /// Inside dense chips and tags.
  static const double xs = 16;

  /// Inline with body text and in compact buttons.
  static const double sm = 20;

  /// Default: navigation, list items, icon buttons.
  static const double md = 24;

  /// Empty states and confirmations.
  static const double lg = 48;
}

/// Font families bundled in assets/fonts.
abstract final class Fonts {
  static const body = 'NunitoSans';
  static const display = 'Quicksand';
  static const tabular = [FontFeature.tabularFigures()];
}
