import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_icons.dart';
import 'tokens.dart';

/// App-specific semantic colors not covered by [ColorScheme].
@immutable
class LiftColors extends ThemeExtension<LiftColors> {
  const LiftColors({
    required this.done,
    required this.rest,
    required this.record,
    required this.raised,
    required this.muted,
  });

  final Color done;
  final Color rest;
  final Color record;
  final Color raised;
  final Color muted;

  static LiftColors of(BuildContext context) =>
      Theme.of(context).extension<LiftColors>()!;

  @override
  LiftColors copyWith({
    Color? done,
    Color? rest,
    Color? record,
    Color? raised,
    Color? muted,
  }) => LiftColors(
    done: done ?? this.done,
    rest: rest ?? this.rest,
    record: record ?? this.record,
    raised: raised ?? this.raised,
    muted: muted ?? this.muted,
  );

  @override
  LiftColors lerp(LiftColors? other, double t) {
    if (other == null) return this;
    return LiftColors(
      done: Color.lerp(done, other.done, t)!,
      rest: Color.lerp(rest, other.rest, t)!,
      record: Color.lerp(record, other.record, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

abstract final class AppTheme {
  static ThemeData light() => _build(
    brightness: Brightness.light,
    background: Palette.lightBackground,
    surface: Palette.lightSurface,
    raised: Palette.lightRaised,
    outline: Palette.lightOutline,
    text: Palette.lightText,
    muted: Palette.lightMuted,
    blue: Palette.lightBlue,
    green: Palette.lightGreen,
    yellow: Palette.lightYellow,
    violet: Palette.lightViolet,
    red: Palette.lightRed,
  );

  static ThemeData dark({bool pureBlack = false}) => _build(
    brightness: Brightness.dark,
    background: pureBlack ? Palette.blackBackground : Palette.darkBackground,
    surface: pureBlack ? Palette.blackSurface : Palette.darkSurface,
    raised: pureBlack ? Palette.blackRaised : Palette.darkRaised,
    outline: Palette.darkOutline,
    text: Palette.darkText,
    muted: Palette.darkMuted,
    blue: Palette.darkBlue,
    green: Palette.darkGreen,
    yellow: Palette.darkYellow,
    violet: Palette.darkViolet,
    red: Palette.darkRed,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color raised,
    required Color outline,
    required Color text,
    required Color muted,
    required Color blue,
    required Color green,
    required Color yellow,
    required Color violet,
    required Color red,
  }) {
    final isDark = brightness == Brightness.dark;
    final onAccent = isDark ? Palette.darkBackground : Colors.white;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: blue,
      onPrimary: onAccent,
      primaryContainer: Color.alphaBlend(blue.withValues(alpha: 0.16), surface),
      onPrimaryContainer: text,
      secondary: green,
      onSecondary: onAccent,
      secondaryContainer: Color.alphaBlend(
        green.withValues(alpha: 0.16),
        surface,
      ),
      onSecondaryContainer: text,
      tertiary: yellow,
      onTertiary: onAccent,
      error: red,
      onError: onAccent,
      errorContainer: Color.alphaBlend(red.withValues(alpha: 0.16), surface),
      onErrorContainer: text,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: muted,
      surfaceDim: background,
      surfaceBright: raised,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: raised,
      surfaceContainerHighest: raised,
      outline: outline,
      outlineVariant: outline,
      shadow: Colors.transparent,
      scrim: Colors.black54,
      inverseSurface: text,
      onInverseSurface: background,
      inversePrimary: blue,
      surfaceTint: Colors.transparent,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: Fonts.body,
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );

    // Explicit scale: base.textTheme carries no sizes until it is localized,
    // so styles pulled from it for component themes would fall back to 14.
    TextStyle display(double size, double height) => TextStyle(
      fontFamily: Fonts.display,
      fontSize: size,
      height: height / size,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      fontFeatures: Fonts.tabular,
    );
    TextStyle body(
      double size,
      double height,
      FontWeight weight, [
      double letterSpacing = 0,
    ]) => TextStyle(
      fontFamily: Fonts.body,
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      fontFeatures: Fonts.tabular,
    );
    final textTheme = TextTheme(
      displayLarge: display(52, 58),
      displayMedium: display(44, 50),
      displaySmall: display(36, 42),
      headlineLarge: display(30, 36),
      headlineMedium: display(27, 32),
      headlineSmall: display(24, 30),
      titleLarge: display(20, 26),
      titleMedium: body(16, 22, FontWeight.w700),
      titleSmall: body(15, 20, FontWeight.w700),
      bodyLarge: body(16, 22, FontWeight.w500),
      bodyMedium: body(14, 20, FontWeight.w500),
      bodySmall: body(13, 18, FontWeight.w500),
      labelLarge: body(15, 20, FontWeight.w700, 0.1),
      labelMedium: body(13, 16, FontWeight.w700, 0.2),
      labelSmall: body(12, 16, FontWeight.w700, 0.6),
    ).apply(bodyColor: text, displayColor: text);

    final overlay = isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          );

    const shapeMd = RoundedRectangleBorder(borderRadius: Radii.mdAll);
    const pill = StadiumBorder();
    final buttonSize = WidgetStateProperty.all(const Size(64, kMinTap));

    return base.copyWith(
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      dividerColor: outline,
      iconTheme: IconThemeData(color: text, size: IconSizes.md),
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const AppIcon(AppIcons.arrowLeft),
        closeButtonIconBuilder: (_) => const AppIcon(AppIcons.close),
      ),
      extensions: [
        LiftColors(
          done: green,
          rest: yellow,
          record: violet,
          raised: raised,
          muted: muted,
        ),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: overlay,
        titleTextStyle: textTheme.headlineSmall?.copyWith(color: text),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const StadiumBorder(),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: IconSizes.md,
            color: s.contains(WidgetState.selected) ? blue : muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => textTheme.labelMedium?.copyWith(
            color: s.contains(WidgetState.selected) ? blue : muted,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.mdAll,
          side: BorderSide(color: outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        minTileHeight: 56,
        minLeadingWidth: IconSizes.md,
        horizontalTitleGap: Space.lg,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(color: muted),
        leadingAndTrailingTextStyle: textTheme.bodyLarge?.copyWith(
          color: muted,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: buttonSize,
          elevation: const WidgetStatePropertyAll(0),
          shape: const WidgetStatePropertyAll(pill),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: buttonSize,
          shape: const WidgetStatePropertyAll(pill),
          side: WidgetStatePropertyAll(BorderSide(color: outline)),
          foregroundColor: WidgetStatePropertyAll(text),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: buttonSize,
          shape: const WidgetStatePropertyAll(pill),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(kMinTap, kMinTap)),
          iconSize: const WidgetStatePropertyAll(IconSizes.md),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: blue,
        foregroundColor: onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: pill,
        extendedTextStyle: textTheme.labelLarge,
        extendedIconLabelSpacing: Space.sm,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: buttonSize,
          side: WidgetStatePropertyAll(BorderSide(color: outline)),
          shape: const WidgetStatePropertyAll(pill),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          iconSize: const WidgetStatePropertyAll(IconSizes.sm),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? muted
                : s.contains(WidgetState.selected)
                ? blue
                : text,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: scheme.primaryContainer,
        side: WidgetStateBorderSide.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.selected) ? blue : outline,
          ),
        ),
        shape: pill,
        // Chips resolve only the label color per state, not the whole style.
        labelStyle: textTheme.labelLarge?.copyWith(
          color: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? blue : text,
          ),
        ),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.md,
        ),
        hintStyle: textTheme.bodyLarge?.copyWith(color: muted),
        labelStyle: textTheme.bodyLarge?.copyWith(color: muted),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(color: muted),
        helperStyle: textTheme.bodySmall?.copyWith(color: muted),
        errorStyle: textTheme.bodySmall?.copyWith(color: red),
        border: const OutlineInputBorder(
          borderRadius: Radii.smAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: Radii.smAll,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.smAll,
          borderSide: BorderSide(color: blue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.smAll,
          borderSide: BorderSide(color: red, width: 1.5),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.lgAll,
          side: isDark ? BorderSide(color: outline) : BorderSide.none,
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyLarge?.copyWith(color: muted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: text,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: background),
        actionTextColor: isDark ? Palette.lightBlue : Palette.darkBlue,
        shape: shapeMd,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll(outline),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: raised,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyLarge,
        labelTextStyle: WidgetStatePropertyAll(textTheme.bodyLarge),
        shape: RoundedRectangleBorder(
          borderRadius: Radii.mdAll,
          side: BorderSide(color: outline),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: yellow,
        linearTrackColor: raised,
      ),
      pageTransitionsTheme: base.pageTransitionsTheme,
    );
  }
}
